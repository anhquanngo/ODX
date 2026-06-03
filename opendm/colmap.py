import os
import shutil

from opendm import context
from opendm import io
from opendm import log
from opendm import system


class ColmapContext:
    def __init__(self, project_root, opensfm_path):
        self.project_root = project_root
        self.opensfm_path = opensfm_path
        self.colmap_path = self._resolve_colmap_path()

        self.colmap_root = os.path.join(project_root, "colmap")
        self.colmap_db = os.path.join(self.colmap_root, "database.db")
        self.images_list = os.path.join(self.opensfm_path, "image_list.txt")
        # OpenMVS DensifyPointCloud loads ../images relative to undistorted/openmvs.
        self.images_dir = os.path.join(self.opensfm_path, "undistorted", "images")
        self.sparse_dir = os.path.join(self.colmap_root, "sparse")
        self.sparse_model_dir = os.path.join(self.sparse_dir, "0")
        self.openmvs_dir = os.path.join(self.opensfm_path, "undistorted", "openmvs")
        self.openmvs_scene = os.path.join(self.openmvs_dir, "scene.mvs")

    def _resolve_colmap_path(self):
        if os.path.isfile(context.colmap_path):
            return context.colmap_path

        colmap_in_path = shutil.which("colmap")
        if colmap_in_path is not None:
            return colmap_in_path

        raise system.ExitException("Cannot find COLMAP binary. Install COLMAP or add it to ODX SuperBuild install/bin.")

    def _run_colmap(self, args):
        system.run('"%s" %s' % (self.colmap_path, args))

    def setup(self, rerun=False):
        if rerun and io.dir_exists(self.colmap_root):
            shutil.rmtree(self.colmap_root)

        os.makedirs(self.colmap_root, exist_ok=True)
        os.makedirs(self.sparse_dir, exist_ok=True)

        if io.dir_exists(self.images_dir):
            shutil.rmtree(self.images_dir)
        os.makedirs(self.images_dir, exist_ok=True)

        if not io.file_exists(self.images_list):
            raise system.ExitException("Missing image list. OpenSfM setup must run before COLMAP.")

        with open(self.images_list, "r") as f:
            for line in f:
                src = line.strip()
                if not src:
                    continue
                if not os.path.isfile(src):
                    continue
                dst = os.path.join(self.images_dir, os.path.basename(src))
                if not os.path.exists(dst):
                    os.symlink(src, dst)

    def run_sparse(self, args):
        use_gpu = 0 if args.no_gpu else 1

        if os.path.exists(self.colmap_db):
            os.remove(self.colmap_db)

        # OpenMVS InterfaceCOLMAP only imports PINHOLE / SIMPLE_PINHOLE from cameras.bin.
        self._run_colmap(
            'feature_extractor --database_path "%s" --image_path "%s" '
            "--ImageReader.single_camera 1 "
            "--ImageReader.camera_model PINHOLE "
            "--SiftExtraction.use_gpu %s "
            # 2000px matches ODX OpenSfM feature_process_size; lowers SiftGPU VRAM vs 3200.
            "--SiftExtraction.max_image_size 2000 "
            "--SiftExtraction.max_num_features %s" % (
                self.colmap_db,
                self.images_dir,
                use_gpu,
                args.min_num_features,
            )
        )

        self._run_colmap(
            'exhaustive_matcher --database_path "%s" --SiftMatching.use_gpu %s' % (
                self.colmap_db,
                use_gpu,
            )
        )

        self._run_colmap(
            'mapper --database_path "%s" --image_path "%s" --output_path "%s"' % (
                self.colmap_db,
                self.images_dir,
                self.sparse_dir,
            )
        )

        if not io.dir_exists(self.sparse_model_dir):
            raise system.ExitException("COLMAP did not generate a sparse model (sparse/0).")

    def _prepare_colmap_interface_sparse(self):
        """
        InterfaceCOLMAP reads {input}/sparse/cameras.bin, but COLMAP mapper writes
        sparse/0/cameras.bin. Expose model 0 at sparse/ via symlinks.
        """
        model_files = [
            "cameras.bin",
            "images.bin",
            "points3D.bin",
            "cameras.txt",
            "images.txt",
            "points3D.txt",
        ]
        for name in model_files:
            src = os.path.join(self.sparse_model_dir, name)
            if not os.path.isfile(src):
                continue
            dst = os.path.join(self.sparse_dir, name)
            if os.path.lexists(dst):
                os.remove(dst)
            os.symlink(os.path.relpath(src, self.sparse_dir), dst)

    def export_openmvs_scene(self):
        if io.dir_exists(self.openmvs_dir):
            shutil.rmtree(self.openmvs_dir)
        os.makedirs(self.openmvs_dir, exist_ok=True)

        if not os.path.isfile(context.omvs_interface_colmap_path):
            raise system.ExitException("Cannot find OpenMVS InterfaceCOLMAP binary.")

        self._prepare_colmap_interface_sparse()
        # ../images from openmvs/ -> opensfm/undistorted/images (OpenMVS layout).
        image_folder = os.path.relpath(self.images_dir, self.openmvs_dir)

        system.run(
            '"%s" --working-folder "%s" --input-file "%s" --output-file "%s" '
            '--image-folder "%s"' % (
                context.omvs_interface_colmap_path,
                self.openmvs_dir,
                self.colmap_root,
                self.openmvs_scene,
                image_folder,
            )
        )

        if not os.path.isfile(self.openmvs_scene):
            raise system.ExitException("Could not generate OpenMVS scene.mvs from COLMAP output.")

    def path(self, *paths):
        return os.path.join(self.opensfm_path, *paths)
