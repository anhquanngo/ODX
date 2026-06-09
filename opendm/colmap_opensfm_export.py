"""
Export COLMAP sparse model (sparse/0/*.bin) to OpenSfM reconstruction.json.

Pose convention matches OpenSfM/bin/import_colmap.py (COLMAP world-to-camera
quaternion + translation -> OpenSfM angle-axis + translation).
"""

import json
import math
import os
from datetime import datetime
from struct import unpack

import numpy as np

from opendm import log
from opendm import system

try:
    from opensfm import features
    from opensfm import pymap
    from opensfm import pygeometry
    from opensfm.align import align_reconstruction
    from opensfm.dataset import DataSet
    from opensfm.reconstruction_helpers import get_image_metadata
except ImportError:
    features = pymap = DataSet = None
    pygeometry = None
    align_reconstruction = None
    get_image_metadata = None

INVALID_POINT3D = np.iinfo(np.uint64).max

try:
    from opensfm.undistort import add_image_format_extension
except ImportError:
    add_image_format_extension = None

# COLMAP camera model ids (subset used by ODX COLMAP feature_extractor PINHOLE).
CAMERA_MODELS = {
    0: ("SIMPLE_PINHOLE", 3),
    1: ("PINHOLE", 4),
    2: ("SIMPLE_RADIAL", 4),
    3: ("RADIAL", 5),
    4: ("OPENCV", 8),
}


def quaternion_to_angle_axis(quaternion):
    q = quaternion / max(1e-12, (quaternion ** 2).sum() ** 0.5)
    qw, qx, qy, qz = q
    s = max(0.001, math.sqrt(1 - qw * qw))
    angle = 2 * math.acos(max(-1.0, min(1.0, qw)))
    return [angle * qx / s, angle * qy / s, angle * qz / s]


def _read_cameras_bin(path):
    cameras = {}
    with open(path, "rb") as f:
        n_cameras = unpack("<Q", f.read(8))[0]
        for _ in range(n_cameras):
            camera_id = unpack("<i", f.read(4))[0]
            model_id = unpack("<i", f.read(4))[0]
            width = unpack("<Q", f.read(8))[0]
            height = unpack("<Q", f.read(8))[0]
            n_params = CAMERA_MODELS.get(model_id, (None, 0))[1]
            if n_params == 0:
                raise ValueError(
                    "Unsupported COLMAP camera model id %s (%s)"
                    % (model_id, path)
                )
            params = [unpack("<d", f.read(8))[0] for _ in range(n_params)]
            cameras[camera_id] = {
                "model_id": model_id,
                "width": int(width),
                "height": int(height),
                "params": params,
            }
    return cameras


def _read_images_bin(path):
    shots = {}
    with open(path, "rb") as f:
        n_images = unpack("<Q", f.read(8))[0]
        for _ in range(n_images):
            _image_id = unpack("<I", f.read(4))[0]
            q = [unpack("<d", f.read(8))[0] for _ in range(4)]
            t = [unpack("<d", f.read(8))[0] for _ in range(3)]
            camera_id = unpack("<I", f.read(4))[0]
            name = ""
            while True:
                ch = f.read(1)
                if not ch or ch == b"\0":
                    break
                name += ch.decode("utf-8", errors="replace")
            filename = os.path.basename(name)
            n_points_2d = unpack("<Q", f.read(8))[0]
            if n_points_2d:
                f.seek(24 * n_points_2d, 1)
            shots[filename] = {
                "camera_id": camera_id,
                "rotation": quaternion_to_angle_axis(np.array(q, dtype=float)),
                "translation": t,
            }
    return shots


def _read_points_bin(path, max_points=None):
    points = {}
    with open(path, "rb") as f:
        n_points = unpack("<Q", f.read(8))[0]
        limit = n_points if max_points is None else min(n_points, max_points)
        for _ in range(limit):
            pid = unpack("<Q", f.read(8))[0]
            x, y, z = unpack("<ddd", f.read(24))
            r, g, b = unpack("<BBB", f.read(3))
            f.read(8)  # error
            track_len = unpack("<Q", f.read(8))[0]
            if track_len:
                f.seek(8 * track_len, 1)
            points[str(pid)] = {
                "coordinates": [x, y, z],
                "color": [float(r), float(g), float(b)],
            }
        if max_points is not None and n_points > max_points:
            log.WARNING(
                "COLMAP has %s points; exported %s to reconstruction.json"
                % (n_points, max_points)
            )
    return points


def _colmap_camera_to_opensfm(cam, camera_key):
    """Map COLMAP PINHOLE / SIMPLE_PINHOLE to OpenSfM perspective JSON."""
    model_id = cam["model_id"]
    w, h = cam["width"], cam["height"]
    normalizer = max(w, h)
    params = cam["params"]

    if model_id == 0:  # SIMPLE_PINHOLE: f, cx, cy
        f, cx, cy = params
        fx = fy = f
    elif model_id == 1:  # PINHOLE: fx, fy, cx, cy
        fx, fy, cx, cy = params
    else:
        raise ValueError(
            "COLMAP camera model %s is not supported for OpenSfM export; "
            "use PINHOLE in feature_extractor." % CAMERA_MODELS[model_id][0]
        )

    focal = (fx + fy) / (2.0 * normalizer)
    return {
        camera_key: {
            "projection_type": "perspective",
            "width": w,
            "height": h,
            "focal": focal,
            "k1": 0.0,
            "k2": 0.0,
        }
    }


def _shot_metadata_from_exif(exif_dir, filename):
    meta = {
        "orientation": 1,
        "capture_time": 0.0,
        "gps_dop": 10.0,
        "vertices": [],
        "faces": [],
        "scale": 1.0,
        "covariance": [],
        "merge_cc": 0,
    }
    exif_path = os.path.join(exif_dir, "%s.exif" % filename)
    if os.path.isfile(exif_path):
        try:
            with open(exif_path, "r") as f:
                exif = json.load(f)
            meta["orientation"] = exif.get("orientation", 1)
            meta["capture_time"] = exif.get("capture_time", 0.0)
            # gps_position is filled by export_geocoords (local/topocentric), not from raw EXIF.
        except Exception as e:
            log.WARNING("Could not read %s: %s" % (exif_path, str(e)))
    return meta


def _read_points_colors(path):
    colors = {}
    if not os.path.isfile(path):
        return colors
    with open(path, "rb") as f:
        n_points = unpack("<Q", f.read(8))[0]
        for _ in range(n_points):
            pid = unpack("<Q", f.read(8))[0]
            f.read(24)
            r, g, b = unpack("<BBB", f.read(3))
            f.read(8)
            track_len = unpack("<Q", f.read(8))[0]
            if track_len:
                f.seek(8 * track_len, 1)
            colors[str(pid)] = (int(r), int(g), int(b))
    return colors


def export_colmap_tracks_manager(sparse_model_dir, opensfm_path):
    """Build OpenSfM tracks.csv from COLMAP 2D–3D associations in images.bin."""
    if pymap is None or DataSet is None or features is None:
        raise ImportError("OpenSfM Python modules are required for COLMAP tracks export")

    images_bin = os.path.join(sparse_model_dir, "images.bin")
    cameras_bin = os.path.join(sparse_model_dir, "cameras.bin")
    points_bin = os.path.join(sparse_model_dir, "points3D.bin")

    if not os.path.isfile(images_bin):
        raise IOError("Missing COLMAP file: %s" % images_bin)

    colmap_cameras = _read_cameras_bin(cameras_bin)
    point_colors = _read_points_colors(points_bin)
    tracks_manager = pymap.TracksManager()
    n_obs = 0

    with open(images_bin, "rb") as f:
        n_images = unpack("<Q", f.read(8))[0]
        for _ in range(n_images):
            unpack("<I", f.read(4))
            f.read(8 * 7)
            camera_id = unpack("<I", f.read(4))[0]
            name = ""
            while True:
                ch = f.read(1)
                if not ch or ch == b"\0":
                    break
                name += ch.decode("utf-8", errors="replace")
            shot_id = os.path.basename(name)
            cam = colmap_cameras[camera_id]
            w, h = cam["width"], cam["height"]
            n_points_2d = unpack("<Q", f.read(8))[0]
            for point2d_ix in range(n_points_2d):
                x, y = unpack("<dd", f.read(16))
                point3d_id = unpack("<Q", f.read(8))[0]
                if point3d_id == INVALID_POINT3D:
                    continue
                track_id = str(point3d_id)
                norm = features.normalized_image_coordinates(
                    np.array([[x, y]], dtype=float), w, h
                )[0]
                rgb = point_colors.get(track_id, (128, 128, 128))
                obs = pymap.Observation(
                    float(norm[0]),
                    float(norm[1]),
                    0.0,
                    rgb[0],
                    rgb[1],
                    rgb[2],
                    point2d_ix,
                )
                tracks_manager.add_observation(shot_id, track_id, obs)
                n_obs += 1

    data = DataSet(opensfm_path)
    data.save_tracks_manager(tracks_manager)
    log.INFO("Exported COLMAP tracks to %s (%s observations)" % (data._tracks_manager_file(), n_obs))
    return tracks_manager


def colmap_undistort_needed(opensfm_path):
    """
    True when undistorted .tif images are missing (e.g. only COLMAP JPG symlinks).
    texrecon / NVM require real undistorted TIFFs.
    """
    if add_image_format_extension is None:
        return True

    recon_path = os.path.join(opensfm_path, "reconstruction.json")
    if not os.path.isfile(recon_path):
        return True

    with open(recon_path, "r") as f:
        shots = json.load(f)[0].get("shots", {})

    if not shots:
        return True

    images_dir = os.path.join(opensfm_path, "undistorted", "images")
    for shot_id in shots:
        tif_path = os.path.join(
            images_dir, add_image_format_extension(shot_id, "tif")
        )
        if not os.path.isfile(tif_path):
            return True

    return False


def align_colmap_reconstruction(opensfm_path, rerun=False):
    """
    Apply GPS/GCP similarity alignment to a COLMAP-exported OpenSfM reconstruction.

    COLMAP sparse is correct up to an arbitrary similarity transform; this step
    brings poses and points to metric topocentric coordinates (same as OpenSfM
    reconstruct + align_reconstruction) before export_geocoords and OpenMVS.
    """
    if DataSet is None or align_reconstruction is None or get_image_metadata is None:
        raise ImportError(
            "OpenSfM Python modules are required for COLMAP GPS alignment"
        )

    flag = os.path.join(opensfm_path, "colmap_gps_aligned.txt")
    if rerun and os.path.isfile(flag):
        os.remove(flag)

    if os.path.isfile(flag) and not rerun:
        log.WARNING("COLMAP GPS alignment already done, skipping")
        return

    data = DataSet(opensfm_path)
    if not data.reconstruction_exists():
        raise IOError("Missing reconstruction.json for COLMAP GPS alignment")

    reconstructions = data.load_reconstruction()
    if not reconstructions:
        raise system.ExitException("Empty COLMAP reconstruction")

    reconstruction = reconstructions[0]
    reconstruction.reference = data.load_reference()

    for shot_id in list(reconstruction.shots.keys()):
        if shot_id not in data.images():
            continue
        reconstruction.shots[shot_id].metadata = get_image_metadata(data, shot_id)

    gcp = data.load_ground_control_points()
    result = align_reconstruction(reconstruction, gcp, data.config)

    if result is None:
        log.WARNING(
            "COLMAP GPS/GCP alignment did not run (no constraints?). "
            "Dense mesh and NVM may still be consistent but not metric."
        )
    else:
        scale, _rotation, _translation = result
        log.INFO("COLMAP aligned to GPS/GCP reference (scale factor: %.6f)" % scale)

    if pygeometry is not None:
        for camera_id in reconstruction.cameras:
            if camera_id not in reconstruction.biases:
                reconstruction.set_bias(
                    camera_id,
                    pygeometry.Similarity([0.0, 0.0, 0.0], [0.0, 0.0, 0.0], 1.0),
                )

    data.save_reconstruction([reconstruction])

    with open(flag, "w") as f:
        f.write("done\n")


def export_colmap_sparse_to_opensfm(
    sparse_model_dir,
    opensfm_path,
    camera_key="colmap_pinhole",
    max_points=500000,
):
    """
    Write opensfm/reconstruction.json from COLMAP sparse/0 binaries.

    Returns path to reconstruction.json.
    """
    cameras_bin = os.path.join(sparse_model_dir, "cameras.bin")
    images_bin = os.path.join(sparse_model_dir, "images.bin")
    points_bin = os.path.join(sparse_model_dir, "points3D.bin")

    for path in (cameras_bin, images_bin):
        if not os.path.isfile(path):
            raise IOError("Missing COLMAP file: %s" % path)

    colmap_cameras = _read_cameras_bin(cameras_bin)
    colmap_shots = _read_images_bin(images_bin)

    if len(colmap_cameras) != 1:
        log.WARNING(
            "COLMAP export used %s cameras; OpenSfM JSON will use the first only."
            % len(colmap_cameras)
        )
    first_cam = colmap_cameras[next(iter(colmap_cameras))]
    cameras_json = _colmap_camera_to_opensfm(first_cam, camera_key)

    exif_dir = os.path.join(opensfm_path, "exif")
    shots_json = {}
    for filename, shot in colmap_shots.items():
        entry = {
            "rotation": shot["rotation"],
            "translation": shot["translation"],
            "camera": camera_key,
        }
        entry.update(_shot_metadata_from_exif(exif_dir, filename))
        shots_json[filename] = entry

    points_json = {}
    if os.path.isfile(points_bin):
        points_json = _read_points_bin(points_bin, max_points=max_points)

    reconstruction = [
        {
            "cameras": cameras_json,
            "shots": shots_json,
            "points": points_json,
        }
    ]

    out_path = os.path.join(opensfm_path, "reconstruction.json")
    with open(out_path, "w") as f:
        json.dump(reconstruction, f)

    log.INFO(
        "Exported COLMAP sparse model to %s (%s shots, %s points)"
        % (out_path, len(shots_json), len(points_json))
    )

    export_colmap_tracks_manager(sparse_model_dir, opensfm_path)
    return out_path


def _attach_reconstruction_metadata(data, reconstructions):
    reference = data.load_reference()
    for reconstruction in reconstructions:
        reconstruction.reference = reference
        for shot_id in list(reconstruction.shots.keys()):
            if shot_id in data.images():
                reconstruction.shots[shot_id].metadata = get_image_metadata(
                    data, shot_id
                )


def _colmap_features_statistics(tracks_manager, reconstructions):
    from collections import defaultdict

    per_shot_all = {}
    for shot_id in tracks_manager.get_shot_ids():
        per_shot_all[shot_id] = len(tracks_manager.get_shot_observations(shot_id))
    all_counts = list(per_shot_all.values())

    stats = {
        "note": "COLMAP SfM engine; OpenSfM feature files were not generated.",
    }
    if all_counts:
        stats["detected_features"] = {
            "min": min(all_counts),
            "max": max(all_counts),
            "mean": int(np.mean(all_counts)),
            "median": int(np.median(all_counts)),
        }
    else:
        stats["detected_features"] = {"min": -1, "max": -1, "mean": -1, "median": -1}

    per_shots = defaultdict(int)
    for rec in reconstructions:
        all_points_keys = set(rec.points.keys())
        for shot_id in rec.shots:
            if shot_id not in tracks_manager.get_shot_ids():
                continue
            for point_id in tracks_manager.get_shot_observations(shot_id):
                if point_id not in all_points_keys:
                    continue
                per_shots[shot_id] += 1
    per_shots = list(per_shots.values())

    stats["reconstructed_features"] = {
        "min": int(min(per_shots)) if per_shots else -1,
        "max": int(max(per_shots)) if per_shots else -1,
        "mean": int(np.mean(per_shots)) if per_shots else -1,
        "median": int(np.median(per_shots)) if per_shots else -1,
    }
    return stats


def _safe_projection_error(tracks_manager, reconstructions):
    """
    Like OpenSfM stats._projection_error but skips non-finite residuals.

    COLMAP-exported tracks can yield inf normalized errors when intrinsics do
    not match OpenSfM's perspective camera model (e.g. principal point offset).
    """
    import math

    from opensfm import pymap as osfm_pymap
    from opensfm.stats import RESIDUAL_PIXEL_CUTOFF, _compute_errors, _norm2d

    all_errors_normalized, all_errors_pixels, all_errors_angular = [], [], []
    average_error_normalized, average_error_pixels, average_error_angular = 0, 0, 0
    for i in range(len(reconstructions)):
        errors_normalized = _compute_errors(reconstructions, tracks_manager)(
            i, osfm_pymap.ErrorType.Normalized
        )
        errors_unnormalized = _compute_errors(reconstructions, tracks_manager)(
            i, osfm_pymap.ErrorType.Pixel
        )
        errors_angular = _compute_errors(reconstructions, tracks_manager)(
            i, osfm_pymap.ErrorType.Angular
        )

        for shot_id, shot_errors_normalized in errors_normalized.items():
            shot = reconstructions[i].get_shot(shot_id)
            normalizer = max(shot.camera.width, shot.camera.height)

            for error_normalized, error_unnormalized, error_angular in zip(
                shot_errors_normalized.values(),
                errors_unnormalized[shot_id].values(),
                errors_angular[shot_id].values(),
            ):
                norm_pixels = _norm2d(error_unnormalized * normalizer)
                norm_normalized = _norm2d(error_normalized)
                norm_angle = error_angular[0]
                if (
                    norm_pixels > RESIDUAL_PIXEL_CUTOFF
                    or not math.isfinite(norm_pixels)
                    or not math.isfinite(norm_normalized)
                    or not math.isfinite(norm_angle)
                ):
                    continue
                average_error_normalized += norm_normalized
                average_error_pixels += norm_pixels
                average_error_angular += norm_angle
                all_errors_normalized.append(norm_normalized)
                all_errors_pixels.append(norm_pixels)
                all_errors_angular.append(norm_angle)

    error_count = len(all_errors_normalized)
    dummy = (np.array([]), np.array([]))
    if error_count == 0:
        return (-1.0, -1.0, -1.0, dummy, dummy, dummy)

    bins = 30
    return (
        average_error_normalized / error_count,
        average_error_pixels / error_count,
        average_error_angular / error_count,
        np.histogram(all_errors_normalized, bins),
        np.histogram(all_errors_pixels, bins),
        np.histogram(all_errors_angular, bins),
    )


def _colmap_reconstruction_statistics(data, tracks_manager, reconstructions):
    from collections import defaultdict

    from opensfm.stats import _length_histogram

    stats = {}
    stats["components"] = len(reconstructions)
    gps_count = 0
    for rec in reconstructions:
        for shot in rec.shots.values():
            gps_count += shot.metadata.gps_position.has_value
    stats["has_gps"] = gps_count > 2
    stats["has_gcp"] = bool(data.load_ground_control_points())

    stats["initial_points_count"] = tracks_manager.num_tracks()
    stats["initial_shots_count"] = len(data.images())
    stats["reconstructed_points_count"] = 0
    stats["reconstructed_shots_count"] = 0
    stats["observations_count"] = 0
    hist_agg = defaultdict(int)

    for rec in reconstructions:
        if len(rec.points) > 0:
            stats["reconstructed_points_count"] += len(rec.points)
        stats["reconstructed_shots_count"] += len(rec.shots)
        hist, values = _length_histogram(tracks_manager, rec.points)
        for length, count_tracks in zip(hist, values):
            hist_agg[length] += count_tracks

    hist_agg = sorted(hist_agg.items(), key=lambda x: x[0])
    lengths = np.array([int(x[0]) for x in hist_agg])
    counts = np.array([x[1] for x in hist_agg])

    points_count = stats["reconstructed_points_count"]
    points_count_over_two = sum(counts[1:]) if len(counts) > 1 else 0
    stats["observations_count"] = int(sum(lengths * counts)) if len(lengths) else 0
    stats["average_track_length"] = (
        stats["observations_count"] / points_count if points_count > 0 else -1
    )
    stats["average_track_length_over_two"] = (
        int(sum(lengths[1:] * counts[1:])) / points_count_over_two
        if points_count_over_two > 0
        else -1
    )
    stats["histogram_track_length"] = {k: v for k, v in hist_agg}

    (
        avg_normalized,
        avg_pixels,
        avg_angular,
        (hist_normalized, bins_normalized),
        (hist_pixels, bins_pixels),
        (hist_angular, bins_angular),
    ) = _safe_projection_error(tracks_manager, reconstructions)

    stats["reprojection_error_normalized"] = avg_normalized
    stats["reprojection_error_pixels"] = avg_pixels
    stats["reprojection_error_angular"] = avg_angular
    stats["reprojection_histogram_normalized"] = (
        list(map(float, hist_normalized)),
        list(map(float, bins_normalized)),
    )
    stats["reprojection_histogram_pixels"] = (
        list(map(float, hist_pixels)),
        list(map(float, bins_pixels)),
    )
    stats["reprojection_histogram_angular"] = (
        list(map(float, hist_angular)),
        list(map(float, bins_angular)),
    )
    return stats


def _colmap_cameras_statistics(data, reconstructions):
    """
    Camera stats for COLMAP export where reconstruction uses colmap_pinhole
    but dataset camera_models.json only has EXIF-derived camera ids.
    """
    from opensfm import io as osfm_io
    from opensfm.stats import _cameras_statistics

    stats = {}
    dataset_cameras = data.load_camera_models()
    zero_bias = {
        "rotation": [0.0, 0.0, 0.0],
        "translation": [0.0, 0.0, 0.0],
        "scale": 1.0,
    }

    for rec in reconstructions:
        for camera in rec.cameras.values():
            if camera.id in stats:
                continue
            initial_camera = dataset_cameras.get(camera.id, camera)
            entry = {
                "initial_values": _cameras_statistics(initial_camera),
                "optimized_values": _cameras_statistics(camera),
            }
            if camera.id in rec.biases:
                entry["bias"] = osfm_io.bias_to_json(rec.biases[camera.id])
            else:
                entry["bias"] = dict(zero_bias)
            stats[camera.id] = entry

    return stats


def _colmap_processing_statistics(data, reconstructions, opensfm_path):
    from opensfm import stats as osfm_stats

    stats = osfm_stats.processing_statistics(data, reconstructions)
    profile = os.path.join(os.path.dirname(opensfm_path), "colmap", "profile.log")
    if not os.path.isfile(profile):
        return stats

    colmap_times = {}
    total = 0.0
    with open(profile, "r") as f:
        for line in f:
            if ":" not in line:
                continue
            name, val = line.strip().split(":", 1)
            try:
                t = float(val.strip())
            except ValueError:
                continue
            colmap_times[name.strip()] = t
            total += t

    if colmap_times:
        stats["steps_times"] = colmap_times
        stats["steps_times"]["Total Time"] = total
    return stats


def export_colmap_compute_statistics(
    opensfm_path, diagram_max_points=100000, rerun=False
):
    """
    OpenSfM compute_statistics for COLMAP exports: stats.json + report diagrams
    without reading opensfm/features/*.npz (COLMAP does not run OpenSfM feature
    extraction).
    """
    if DataSet is None or get_image_metadata is None:
        raise ImportError(
            "OpenSfM Python modules are required for COLMAP statistics export"
        )

    try:
        from opensfm import io as osfm_io
        from opensfm import stats as osfm_stats
    except ImportError as e:
        raise ImportError(
            "OpenSfM stats modules are required for COLMAP statistics export"
        ) from e

    stats_dir = os.path.join(opensfm_path, "stats")
    stats_path = os.path.join(stats_dir, "stats.json")
    required_diagrams = ("topview.png", "matchgraph.png")
    diagrams_ok = all(
        os.path.isfile(os.path.join(stats_dir, name)) for name in required_diagrams
    )

    if os.path.isfile(stats_path) and diagrams_ok and not rerun:
        log.WARNING("Found existing COLMAP stats %s, skipping" % stats_path)
        return stats_path

    data = DataSet(opensfm_path)
    reconstructions = data.load_reconstruction()
    tracks_manager = data.load_tracks_manager()
    _attach_reconstruction_metadata(data, reconstructions)

    stats_dict = {
        "processing_statistics": _colmap_processing_statistics(
            data, reconstructions, opensfm_path
        ),
        "features_statistics": _colmap_features_statistics(
            tracks_manager, reconstructions
        ),
        "reconstruction_statistics": _colmap_reconstruction_statistics(
            data, tracks_manager, reconstructions
        ),
        "camera_errors": _colmap_cameras_statistics(data, reconstructions),
        "rig_errors": osfm_stats.rig_statistics(data, reconstructions),
        "gps_errors": osfm_stats.gps_errors(reconstructions),
        "gcp_errors": osfm_stats.gcp_errors(data, reconstructions),
    }

    output_path = stats_dir
    data.io_handler.mkdir_p(output_path)

    try:
        osfm_stats.save_residual_grids(
            data, tracks_manager, reconstructions, output_path, data.io_handler
        )
    except Exception as e:
        log.WARNING("COLMAP residual grids skipped: %s" % e)

    osfm_stats.save_matchgraph(
        data, tracks_manager, reconstructions, output_path, data.io_handler
    )

    try:
        osfm_stats.save_residual_histogram(
            stats_dict, output_path, data.io_handler
        )
    except Exception as e:
        log.WARNING("COLMAP residual histogram skipped: %s" % e)

    if diagram_max_points > 0:
        osfm_stats.decimate_points(reconstructions, diagram_max_points)

    osfm_stats.save_heatmap(
        data, tracks_manager, reconstructions, output_path, data.io_handler
    )
    osfm_stats.save_topview(
        data, tracks_manager, reconstructions, output_path, data.io_handler
    )

    with data.io_handler.open_wt(os.path.join(output_path, "stats.json")) as fout:
        osfm_io.json_dump(stats_dict, fout)

    log.INFO("Wrote COLMAP compute_statistics to %s" % stats_path)
    return stats_path


def export_colmap_stats(opensfm_path, rerun=False):
    """
    Deprecated: use export_colmap_compute_statistics (octx.export_stats colmap=True).

    Minimal stats.json for odm_report without OpenSfM features/*.npz
    (COLMAP does not run OpenSfM feature extraction).
    """
    stats_dir = os.path.join(opensfm_path, "stats")
    stats_path = os.path.join(stats_dir, "stats.json")
    if os.path.isfile(stats_path) and not rerun:
        log.WARNING("Found existing %s, skipping COLMAP stats export" % stats_path)
        return stats_path

    recon_path = os.path.join(opensfm_path, "reconstruction.json")
    if not os.path.isfile(recon_path):
        raise IOError("Missing %s for COLMAP stats export" % recon_path)

    with open(recon_path, "r") as f:
        recon = json.load(f)[0]

    shots = recon.get("shots", {})
    points = recon.get("points", {})
    obs_count = 0
    track_lengths = {}

    if DataSet is not None and pymap is not None:
        data = DataSet(opensfm_path)
        if data.tracks_exists():
            tracks_manager = data.load_tracks_manager()
            for shot_id in tracks_manager.get_shot_ids():
                for track_id, _obs in tracks_manager.get_shot_observations(
                    shot_id
                ).items():
                    obs_count += 1
                    track_lengths[track_id] = track_lengths.get(track_id, 0) + 1

    hist = {}
    for track_len in track_lengths.values():
        key = str(track_len)
        hist[key] = hist.get(key, 0) + 1

    lengths = list(track_lengths.values())
    avg_tl = (sum(lengths) / len(lengths)) if lengths else 0.0
    over_two = [length for length in lengths if length >= 2]
    avg_over_two = (sum(over_two) / len(over_two)) if over_two else 0.0

    has_gps = any("gps_position" in shot for shot in shots.values())
    now_str = datetime.now().strftime("%d/%m/%Y at %H:%M:%S")

    per_shot_obs = {}
    if DataSet is not None and pymap is not None:
        data = DataSet(opensfm_path)
        if data.tracks_exists():
            tm = data.load_tracks_manager()
            for shot_id in tm.get_shot_ids():
                per_shot_obs[shot_id] = len(tm.get_shot_observations(shot_id))

    obs_counts = list(per_shot_obs.values()) if per_shot_obs else [0]
    feat_median = int(sorted(obs_counts)[len(obs_counts) // 2]) if obs_counts else 0

    cameras = recon.get("cameras", {})
    camera_errors = {}
    for cam_id, cam in cameras.items():
        focal = cam.get("focal", cam.get("focal_x", 0.5))
        camera_errors[cam_id] = {
            "initial_values": {
                "focal": focal,
                "k1": 0.0,
                "k2": 0.0,
                "k3": 0.0,
                "p1": 0.0,
                "p2": 0.0,
                "aspect_ratio": 1.0,
                "cx": cam.get("c_x", 0.0),
                "cy": cam.get("c_y", 0.0),
            },
            "optimized_values": {
                "focal": focal,
                "k1": cam.get("k1", 0.0),
                "k2": cam.get("k2", 0.0),
                "k3": cam.get("k3", 0.0),
                "p1": cam.get("p1", 0.0),
                "p2": cam.get("p2", 0.0),
                "aspect_ratio": 1.0,
                "cx": cam.get("c_x", 0.0),
                "cy": cam.get("c_y", 0.0),
            },
            "bias": {
                "rotation": [0.0, 0.0, 0.0],
                "translation": [0.0, 0.0, 0.0],
                "scale": 1.0,
            },
        }

    zero_err = {
        "mean": {"x": 0.0, "y": 0.0, "z": 0.0},
        "std": {"x": 0.0, "y": 0.0, "z": 0.0},
        "error": {"x": 0.0, "y": 0.0, "z": 0.0},
        "average_error": 0.0,
        "ce90": 0.0,
        "le90": 0.0,
    }

    stats = {
        "processing_statistics": {
            "steps_times": {
                "COLMAP SfM": 0,
                "Total Time": 0,
            },
            "date": now_str,
            "start_date": now_str,
            "end_date": now_str,
            "area": 0,
        },
        "features_statistics": {
            "note": "COLMAP SfM engine; OpenSfM feature files were not generated.",
            "detected_features": {
                "min": min(obs_counts) if obs_counts else 0,
                "max": max(obs_counts) if obs_counts else 0,
                "mean": int(sum(obs_counts) / len(obs_counts)) if obs_counts else 0,
                "median": feat_median,
            },
            "reconstructed_features": {
                "min": min(obs_counts) if obs_counts else 0,
                "max": max(obs_counts) if obs_counts else 0,
                "mean": int(sum(obs_counts) / len(obs_counts)) if obs_counts else 0,
                "median": feat_median,
            },
        },
        "reconstruction_statistics": {
            "components": 1,
            "has_gps": has_gps,
            "has_gcp": False,
            "initial_points_count": len(points),
            "initial_shots_count": len(shots),
            "reconstructed_points_count": len(points),
            "reconstructed_shots_count": len(shots),
            "observations_count": obs_count,
            "average_track_length": avg_tl,
            "average_track_length_over_two": avg_over_two,
            "histogram_track_length": hist,
            "reprojection_error_normalized": 0,
            "reprojection_error_pixels": 0,
            "reprojection_error_angular": 0,
        },
        "camera_errors": camera_errors,
        "rig_errors": {},
        "gps_errors": dict(zero_err) if has_gps else {},
        "gcp_errors": {},
        "3d_errors": dict(zero_err),
    }

    os.makedirs(stats_dir, exist_ok=True)
    with open(stats_path, "w") as f:
        json.dump(stats, f, indent=4)

    log.INFO("Wrote COLMAP stats to %s" % stats_path)
    return stats_path
