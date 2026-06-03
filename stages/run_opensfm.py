import sys
import os
import shutil
import glob

from opendm import log
from opendm import io
from opendm import system
from opendm import context
from opendm import gsd
from opendm import point_cloud
from opendm import types
from opendm.utils import get_depthmap_resolution
from opendm.osfm import OSFMContext
from opendm import multispectral
from opendm import thermal
from opendm import nvm
from opendm.colmap import ColmapContext
from opendm.colmap_opensfm_export import export_colmap_stats, colmap_undistort_needed
from opendm.photo import find_largest_photo

from opensfm.undistort import add_image_format_extension

class ODMOpenSfMStage(types.ODM_Stage):
    def process(self, args, outputs):
        tree = outputs['tree']
        reconstruction = outputs['reconstruction']
        photos = reconstruction.photos

        if not photos:
            raise system.ExitException('Not enough photos in photos array to start OpenSfM')

        if args.sfm_engine == "colmap":
            if reconstruction.multi_camera:
                raise system.ExitException("COLMAP SfM engine currently supports single-camera datasets only.")
            if 'split_is_set' in args and args.split < 999999:
                raise system.ExitException("COLMAP SfM engine is not yet supported with split-merge.")

            octx = OSFMContext(tree.opensfm)
            octx.setup(args, tree.dataset_raw, reconstruction=reconstruction, rerun=self.rerun())
            octx.photos_to_metadata(photos, args.rolling_shutter, args.rolling_shutter_readout, self.rerun())
            self.update_progress(20)

            cctx = ColmapContext(tree.root_path, tree.opensfm)
            cctx.setup(self.rerun())
            cctx.run_sparse(args)
            self.update_progress(45)

            cctx.export_opensfm_reconstruction(self.rerun())
            self.update_progress(55)

            # OpenMVS InterfaceCOLMAP must match the images used for COLMAP SfM (pre-undistort).
            cctx.export_openmvs_scene()
            self.update_progress(65)

            if reconstruction.is_georeferenced() and (
                not io.file_exists(tree.opensfm_topocentric_reconstruction) or self.rerun()
            ):
                octx.run(
                    'export_geocoords --reconstruction --proj "%s" --offset-x %s --offset-y %s'
                    % (
                        reconstruction.georef.proj4(),
                        reconstruction.georef.utm_east_offset,
                        reconstruction.georef.utm_north_offset,
                    )
                )
                shutil.move(tree.opensfm_reconstruction, tree.opensfm_topocentric_reconstruction)
                shutil.move(tree.opensfm_geocoords_reconstruction, tree.opensfm_reconstruction)

            outputs['undist_image_max_size'] = max(
                gsd.image_max_size(
                    photos,
                    args.orthophoto_resolution,
                    tree.opensfm_reconstruction,
                    ignore_gsd=args.ignore_gsd,
                    has_gcp=reconstruction.has_gcp(),
                ),
                get_depthmap_resolution(args, photos),
            )

            updated_config_flag_file = octx.path('updated_config.txt')
            if not io.file_exists(updated_config_flag_file) or self.rerun():
                octx.update_config({'undistorted_image_max_size': outputs['undist_image_max_size']})
                octx.touch(updated_config_flag_file)

            need_undistort = self.rerun() or colmap_undistort_needed(tree.opensfm)
            if need_undistort and not self.rerun():
                log.WARNING(
                    "Undistorted .tif images missing (COLMAP symlinks only); re-running undistort"
                )
                nominal_done = octx.path("undistorted", "nominal_done.txt")
                if io.file_exists(nominal_done):
                    os.remove(nominal_done)

            octx.convert_and_undistort(need_undistort)
            self.update_progress(80)

            octx.extract_cameras(tree.path("cameras.json"), self.rerun())

            nvm_rerun = (
                self.rerun()
                or need_undistort
                or not io.file_exists(tree.opensfm_reconstruction_nvm)
            )
            if nvm_rerun:
                octx.run('export_visualsfm --points')
            else:
                log.WARNING(
                    'Found a valid OpenSfM NVM reconstruction file in: %s'
                    % tree.opensfm_reconstruction_nvm
                )

            if not args.skip_report:
                export_colmap_stats(tree.opensfm, self.rerun())

            self.update_progress(95)
            log.INFO(
                "COLMAP sparse + OpenSfM export (reconstruction, undistort, NVM, stats) complete."
            )
            return

        octx = OSFMContext(tree.opensfm)
        octx.setup(args, tree.dataset_raw, reconstruction=reconstruction, rerun=self.rerun())
        octx.photos_to_metadata(photos, args.rolling_shutter, args.rolling_shutter_readout, self.rerun())
        self.update_progress(20)
        octx.feature_matching(self.rerun())
        self.update_progress(30)
        octx.create_tracks(self.rerun())
        octx.reconstruct(args.rolling_shutter, reconstruction.is_georeferenced() and (not args.sfm_no_partial), self.rerun())
        octx.extract_cameras(tree.path("cameras.json"), self.rerun())
        self.update_progress(70)

        def cleanup_disk_space():
            if args.optimize_disk_space:
                for folder in ["features", "matches", "reports"]:
                    folder_path = octx.path(folder)
                    if os.path.exists(folder_path):
                        if os.path.islink(folder_path):
                            os.unlink(folder_path)
                        else:
                            shutil.rmtree(folder_path)

        # If we find a special flag file for split/merge we stop right here
        if os.path.exists(octx.path("split_merge_stop_at_reconstruction.txt")):
            log.INFO("Stopping OpenSfM early because we found: %s" % octx.path("split_merge_stop_at_reconstruction.txt"))
            self.next_stage = None
            cleanup_disk_space()
            return

        # Stats are computed in the local CRS (before geoprojection)
        if not args.skip_report:

            # TODO: this will fail to compute proper statistics if
            # the pipeline is run with --skip-report and is subsequently
            # rerun without --skip-report a --rerun-* parameter (due to the reconstruction.json file)
            # being replaced below. It's an isolated use case.

            octx.export_stats(self.rerun())
        
        self.update_progress(75)

        # We now switch to a geographic CRS
        if reconstruction.is_georeferenced() and (not io.file_exists(tree.opensfm_topocentric_reconstruction) or self.rerun()):
            octx.run('export_geocoords --reconstruction --proj "%s" --offset-x %s --offset-y %s' % 
                (reconstruction.georef.proj4(), reconstruction.georef.utm_east_offset, reconstruction.georef.utm_north_offset))
            shutil.move(tree.opensfm_reconstruction, tree.opensfm_topocentric_reconstruction)
            shutil.move(tree.opensfm_geocoords_reconstruction, tree.opensfm_reconstruction)
        else:
            log.WARNING("Will skip exporting %s" % tree.opensfm_geocoords_reconstruction)
        
        self.update_progress(80)

        updated_config_flag_file = octx.path('updated_config.txt')

        # Make sure it's capped by the depthmap-resolution arg,
        # since the undistorted images are used for MVS
        outputs['undist_image_max_size'] = max(
            gsd.image_max_size(photos, args.orthophoto_resolution, tree.opensfm_reconstruction, ignore_gsd=args.ignore_gsd, has_gcp=reconstruction.has_gcp()),
            get_depthmap_resolution(args, photos)
        )

        if not io.file_exists(updated_config_flag_file) or self.rerun():
            octx.update_config({'undistorted_image_max_size': outputs['undist_image_max_size']})
            octx.touch(updated_config_flag_file)

        # Undistorted images will be used for texturing / MVS

        alignment_info = None
        primary_band_name = None
        largest_photo = None
        undistort_pipeline = []

        def undistort_callback(shot_id, image):
            for func in undistort_pipeline:
                image = func(shot_id, image)
            return image

        def resize_thermal_images(shot_id, image):
            photo = reconstruction.get_photo(shot_id)
            if photo.is_thermal():
                return thermal.resize_to_match(image, largest_photo)
            else:
                return image

        def radiometric_calibrate(shot_id, image):
            photo = reconstruction.get_photo(shot_id)
            if photo.is_thermal():
                return thermal.dn_to_temperature(photo, image, tree.dataset_raw)
            else:
                return multispectral.dn_to_reflectance(photo, image, use_sun_sensor=args.radiometric_calibration=="camera+sun")


        def align_to_primary_band(shot_id, image):
            photo = reconstruction.get_photo(shot_id)

            # No need to align if requested by user
            if args.skip_band_alignment:
                return image

            # No need to align primary
            if photo.band_name == primary_band_name:
                return image

            ainfo = alignment_info.get(photo.band_name)
            if ainfo is not None:
                return multispectral.align_image(image, ainfo['warp_matrix'], ainfo['dimension'])
            else:
                log.WARNING("Cannot align %s, no alignment matrix could be computed. Band alignment quality might be affected." % (shot_id))
                return image

        if reconstruction.multi_camera:
            largest_photo = find_largest_photo([p for p in photos])
            undistort_pipeline.append(resize_thermal_images)

        if args.radiometric_calibration != "none":
            undistort_pipeline.append(radiometric_calibrate)
        
        image_list_override = None

        if reconstruction.multi_camera:
            
            # Undistort only secondary bands
            primary_band_name = multispectral.get_primary_band_name(reconstruction.multi_camera, args.primary_band)
            image_list_override = [os.path.join(tree.dataset_raw, p.filename) for p in photos if p.band_name.lower() != primary_band_name.lower()]

            # We backup the original reconstruction.json, tracks.csv
            # then we augment them by duplicating the primary band
            # camera shots with each band, so that exports, undistortion,
            # etc. include all bands
            # We finally restore the original files later

            added_shots_file = octx.path('added_shots_done.txt')
            s2p, p2s = None, None

            if not io.file_exists(added_shots_file) or self.rerun():
                s2p, p2s = multispectral.compute_band_maps(reconstruction.multi_camera, primary_band_name)
                
                if not args.skip_band_alignment:
                    alignment_info = multispectral.compute_alignment_matrices(reconstruction.multi_camera, primary_band_name, tree.dataset_raw, s2p, p2s, max_concurrency=args.max_concurrency)
                else:
                    log.WARNING("Skipping band alignment")
                    alignment_info = {}
                    
                log.INFO("Adding shots to reconstruction")
                
                octx.backup_reconstruction()
                octx.add_shots_to_reconstruction(p2s)
                octx.touch(added_shots_file)

            undistort_pipeline.append(align_to_primary_band)

        octx.convert_and_undistort(self.rerun(), undistort_callback, image_list_override)

        self.update_progress(95)

        if reconstruction.multi_camera:
            octx.restore_reconstruction_backup()

            # Undistort primary band and write undistorted 
            # reconstruction.json, tracks.csv
            octx.convert_and_undistort(self.rerun(), undistort_callback, runId='primary')

        if not io.file_exists(tree.opensfm_reconstruction_nvm) or self.rerun():
            octx.run('export_visualsfm --points')
        else:
            log.WARNING('Found a valid OpenSfM NVM reconstruction file in: %s' %
                            tree.opensfm_reconstruction_nvm)
        
        if reconstruction.multi_camera:
            log.INFO("Multiple bands found")

            # Write NVM files for the various bands
            for band in reconstruction.multi_camera:
                nvm_file = octx.path("undistorted", "reconstruction_%s.nvm" % band['name'].lower())

                if not io.file_exists(nvm_file) or self.rerun():
                    img_map = {}

                    if primary_band_name is None:
                        primary_band_name = multispectral.get_primary_band_name(reconstruction.multi_camera, args.primary_band)
                    if p2s is None:
                        s2p, p2s = multispectral.compute_band_maps(reconstruction.multi_camera, primary_band_name)
                    
                    for fname in p2s:
                        
                        # Primary band maps to itself
                        if band['name'] == primary_band_name:
                            img_map[add_image_format_extension(fname, 'tif')] = add_image_format_extension(fname, 'tif')
                        else:
                            band_filename = next((p.filename for p in p2s[fname] if p.band_name == band['name']), None)

                            if band_filename is not None:
                                img_map[add_image_format_extension(fname, 'tif')] = add_image_format_extension(band_filename, 'tif')
                            else:
                                log.WARNING("Cannot find %s band equivalent for %s" % (band, fname))

                    nvm.replace_nvm_images(tree.opensfm_reconstruction_nvm, img_map, nvm_file)
                else:
                    log.WARNING("Found existing NVM file %s" % nvm_file)
                    
        # Skip dense reconstruction if necessary and export
        # sparse reconstruction instead
        if args.fast_orthophoto:
            output_file = octx.path('reconstruction.ply')

            if not io.file_exists(output_file) or self.rerun():
                octx.run('export_ply --no-cameras --point-num-views')
            else:
                log.WARNING("Found a valid PLY reconstruction in %s" % output_file)

        cleanup_disk_space()

        if args.optimize_disk_space:
            os.remove(octx.path("tracks.csv"))
            if io.file_exists(octx.recon_backup_file()):
                os.remove(octx.recon_backup_file())

            if io.dir_exists(octx.path("undistorted", "depthmaps")):
                files = glob.glob(octx.path("undistorted", "depthmaps", "*.npz"))
                for f in files:
                    os.remove(f)

            # Keep these if using OpenMVS
            if args.fast_orthophoto:
                files = [octx.path("undistorted", "tracks.csv"),
                         octx.path("undistorted", "reconstruction.json")
                        ]
                for f in files:
                    if os.path.exists(f):
                        os.remove(f)