import importlib
import unittest

import resources


class ContextFallbackTests(unittest.TestCase):
    def test_missing_required_facts_uses_safe_defaults(self):
        original = resources.facts.copy()
        resources.facts = {}
        try:
            import context

            importlib.reload(context)
            self.assertEqual(context.full_name, "Digital Twin")
            self.assertEqual(context.name, "Guest")
        finally:
            resources.facts = original
            importlib.reload(context)


if __name__ == "__main__":
    unittest.main()
