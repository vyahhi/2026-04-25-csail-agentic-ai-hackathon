---
name: simple-pdf-generation
description: Generate a simple polished PDF on the Mac mini from drafted text when no Office/Pandoc pipeline is available.
---

# Simple PDF Generation

Use this when the user wants a quick PDF deliverable from text content and there is no existing source document to convert.

## When to use

- The user asks for "PDF" after you already have the text drafted.
- You need a 1-page or short multi-section PDF fast.
- `pandoc`, `libreoffice`, `wkhtmltopdf`, or similar converters may not be installed.

## Workflow

1. Check available conversion tools first:

```bash
python3 - <<'PY'
import shutil
for cmd in ['pandoc','weasyprint','wkhtmltopdf','textutil','cupsfilter','soffice','libreoffice','qlmanage']:
    print(cmd, shutil.which(cmd))
PY
```

2. If common converters are missing, use ReportLab.

3. Install ReportLab in the terminal environment if needed:

```bash
python3 -m pip install --user reportlab
```

4. Generate the PDF with `terminal()` using `python3`, not `execute_code()`.

## Important pitfalls

1. `execute_code()` may run in a different Python environment from `terminal()` and may not see packages installed with `python3 -m pip install --user ...`.

If you install `reportlab` in `terminal()` and then get `ModuleNotFoundError` in `execute_code()`, switch to running the PDF-generation script entirely inside `terminal()`.

2. On this Mac mini, having `/usr/bin/textutil` and `/usr/sbin/cupsfilter` available does **not** mean you can convert HTML or RTF to PDF through them. Empirically:

- `cupsfilter -m application/pdf file.html` can fail with `No filter to convert from text/html to application/pdf.`
- converting HTML to RTF with `textutil` and then trying `cupsfilter` on the RTF can fail the same way

So if `pandoc` / `wkhtmltopdf` / `libreoffice` are missing, do **not** spend more time trying `textutil` + `cupsfilter` as a PDF pipeline; go straight to ReportLab.

## Minimal pattern

```bash
python3 - <<'PY'
from pathlib import Path
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Paragraph
from reportlab.lib import colors

out_path = str(Path.home() / 'Downloads' / 'output.pdf')

doc = SimpleDocTemplate(
    out_path,
    pagesize=letter,
    rightMargin=0.6*inch,
    leftMargin=0.6*inch,
    topMargin=0.55*inch,
    bottomMargin=0.55*inch,
)

styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name='TitleCenter', parent=styles['Title'], alignment=TA_CENTER, fontName='Helvetica-Bold', fontSize=16, leading=19, spaceAfter=8))
styles.add(ParagraphStyle(name='Meta', parent=styles['Normal'], alignment=TA_CENTER, fontName='Helvetica', fontSize=10, leading=12, textColor=colors.HexColor('#444444'), spaceAfter=10))
styles.add(ParagraphStyle(name='SectionHeader', parent=styles['Heading2'], fontName='Helvetica-Bold', fontSize=11, leading=13, spaceBefore=4, spaceAfter=3))
styles.add(ParagraphStyle(name='BodyTight', parent=styles['BodyText'], fontName='Helvetica', fontSize=9.25, leading=11.2, spaceAfter=3.5))

story = [
    Paragraph('Document Title', styles['TitleCenter']),
    Paragraph('Optional subtitle / team line', styles['Meta']),
    Paragraph('Section', styles['SectionHeader']),
    Paragraph('Body text goes here.', styles['BodyTight']),
]

doc.build(story)
print(out_path)
PY
```

## Verification

Always verify the output before delivering it:

```bash
file ~/Downloads/output.pdf
mdls -name kMDItemNumberOfPages -name kMDItemFSSize ~/Downloads/output.pdf
```

Look for:

- `PDF document`
- expected page count
- nontrivial file size

## Notes

- This works well for clean one-page descriptions, summaries, proposals, and hackathon submissions.
- Keep margins tight and font size around 9-10 pt if the user wants a true single-page PDF.
- Save the drafted source text alongside the PDF when useful for later edits.
