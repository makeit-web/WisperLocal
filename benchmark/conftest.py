import os
import sys

# Make the harness modules (normalize.py, score.py) importable from tests.
sys.path.insert(0, os.path.dirname(__file__))
