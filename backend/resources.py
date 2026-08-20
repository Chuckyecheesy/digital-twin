from pathlib import Path
import json

from pypdf import PdfReader

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"


def _read_optional_text(*candidates):
    for candidate in candidates:
        if candidate.exists():
            with candidate.open("r", encoding="utf-8") as f:
                return f.read()
    return ""


# Read LinkedIn PDF
linkedin_path = DATA_DIR / "linkedin.pdf"
if not linkedin_path.exists():
    linkedin_path = BASE_DIR / "linkedin.pdf"

try:
    reader = PdfReader(str(linkedin_path))
    linkedin = ""
    for page in reader.pages:
        text = page.extract_text()
        if text:
            linkedin += text
except FileNotFoundError:
    linkedin = "LinkedIn profile not available"

# Read other data files
summary = _read_optional_text(
    BASE_DIR / "summary.txt",
    DATA_DIR / "summary.txt",
)
style = _read_optional_text(
    BASE_DIR / "style.txt",
    DATA_DIR / "style.txt",
)

facts_path = BASE_DIR / "facts.json"
if not facts_path.exists():
    facts_path = DATA_DIR / "facts.json"

if facts_path.exists():
    with facts_path.open("r", encoding="utf-8") as f:
        facts = json.load(f)
else:
    facts = {}