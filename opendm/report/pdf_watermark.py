"""
Apply a centered diagonal VNPT logo watermark to report PDFs.
"""

import io
import os
import tempfile

from PIL import Image
from fpdf import FPDF
from pypdf import PdfReader, PdfWriter

from opendm import log

_DEFAULT_LOGO = os.path.join(os.path.dirname(__file__), "vnpt_watermark.png")
_WATERMARK_OPACITY = 0.15
_ROTATION_DEGREES = 45
_LOGO_WIDTH_MM = 160


def _prepare_watermark_image(logo_path: str) -> Image.Image:
    img = Image.open(logo_path).convert("RGBA")
    r, g, b, a = img.split()
    a = a.point(lambda x: int(x * _WATERMARK_OPACITY))
    return Image.merge("RGBA", (r, g, b, a)).rotate(
        _ROTATION_DEGREES, expand=True, resample=Image.Resampling.BICUBIC
    )


def _build_watermark_pdf(logo_path: str) -> bytes:
    rotated = _prepare_watermark_image(logo_path)

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = tmp.name
        rotated.save(tmp_path, "PNG")

    try:
        page_w, page_h = 210, 297
        aspect = rotated.width / rotated.height
        w_mm = _LOGO_WIDTH_MM
        h_mm = w_mm / aspect
        x = (page_w - w_mm) / 2
        y = (page_h - h_mm) / 2

        pdf = FPDF("P", "mm", "A4")
        pdf.set_auto_page_break(False)
        pdf.add_page()
        pdf.image(tmp_path, x=x, y=y, w=w_mm)

        out = pdf.output()
        if isinstance(out, str):
            out = out.encode("latin-1")
        return bytes(out)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


def apply_vnpt_watermark(pdf_path: str, logo_path: str = _DEFAULT_LOGO) -> bool:
    """
    Overlay a faded diagonal VNPT logo on every page of the given PDF (in place).
    Returns True on success, False if skipped or failed.
    """
    if not os.path.isfile(pdf_path):
        log.WARNING("Cannot watermark report: %s does not exist" % pdf_path)
        return False

    if not os.path.isfile(logo_path):
        log.WARNING("Cannot watermark report: logo not found at %s" % logo_path)
        return False

    try:
        watermark_bytes = _build_watermark_pdf(logo_path)
        watermark_page = PdfReader(io.BytesIO(watermark_bytes)).pages[0]

        reader = PdfReader(pdf_path)
        writer = PdfWriter()
        for page in reader.pages:
            page.merge_page(watermark_page)
            writer.add_page(page)

        with open(pdf_path, "wb") as fout:
            writer.write(fout)

        log.INFO("Applied VNPT watermark to %s" % pdf_path)
        return True
    except Exception as e:
        log.WARNING("Failed to apply VNPT watermark to %s: %s" % (pdf_path, str(e)))
        return False
