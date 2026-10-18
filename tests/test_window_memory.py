import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("window_memory", Path(__file__).resolve().parents[1] / "niri/window-memory.py")
memory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(memory)


class WindowMemoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, {"XDG_CONFIG_HOME": self.temp.name})
        env.start()
        self.addCleanup(env.stop)
        self.rule = {"app_id": "google-chrome", "title": "^Extension settings$", "mode": "floating"}
        self.window = {"id": 42, "app_id": "google-chrome", "title": "Extension settings"}

    def test_app_and_title_both_required(self):
        self.assertEqual(memory.matching_rule(self.window, [self.rule]), self.rule)
        self.assertIsNone(memory.matching_rule(dict(self.window, title="Regular tab"), [self.rule]))
        self.assertIsNone(memory.matching_rule(dict(self.window, app_id="firefox"), [self.rule]))

    def test_late_title_applies_once_and_reopen_applies_again(self):
        watcher = memory.Watcher()
        watcher.rules = [self.rule]
        with patch.object(memory, "action") as act:
            watcher.event({"WindowOpenedOrChanged": {"window": dict(self.window, title="")}})
            act.assert_not_called()
            watcher.event({"WindowOpenedOrChanged": {"window": self.window}})
            watcher.event({"WindowOpenedOrChanged": {"window": dict(self.window, is_floating=False)}})
            act.assert_called_once_with("MoveWindowToFloating", id=42)
            watcher.event({"WindowClosed": {"id": 42}})
            watcher.event({"WindowOpenedOrChanged": {"window": self.window}})
            self.assertEqual(act.call_count, 2)

    def test_saved_rule_loaded_and_removal_stops_future_actions(self):
        memory.save_rules([self.rule])
        self.assertEqual(memory.load_rules(), [self.rule])
        watcher = memory.Watcher()
        watcher.known = {42: self.window}
        with patch.object(memory, "action") as act:
            watcher.reload()
            act.assert_called_once()
            memory.save_rules([])
            watcher.reload()
            watcher.event({"WindowOpenedOrChanged": {"window": dict(self.window, id=43)}})
            self.assertEqual(act.call_count, 1)

    def test_maximize_targets_original_window_without_focusing(self):
        watcher = memory.Watcher()
        watcher.rules = [dict(self.rule, mode="maximized")]
        with patch.object(memory, "action") as act:
            watcher.apply(self.window)
            self.assertEqual([call.args[0] for call in act.call_args_list], ["MoveWindowToTiling", "SetWindowWidth"])
            self.assertTrue(all(call.kwargs["id"] == 42 for call in act.call_args_list))

    def test_pattern_escapes_punctuation_and_rejects_app_wide_match(self):
        with patch.object(memory.subprocess, "run") as run:
            run.return_value.returncode = 0
            run.return_value.stdout = "Select [file] *\n"
            pattern = memory.pattern_prompt("Select [file] document")
            self.assertIsNotNone(memory.re.search(pattern, "Select [file] document"))
            self.assertIsNone(memory.re.search(pattern, "Select f document"))
            run.return_value.stdout = "*\n"
            with self.assertRaises(ValueError):
                memory.pattern_prompt("anything")

    def test_cancel_picker_does_not_write(self):
        with patch.object(memory, "request", return_value={"FocusedWindow": self.window}), patch.object(memory, "menu", return_value=None):
            memory.remember("floating")
        self.assertFalse((memory.state_dir() / "rules.json").exists())


if __name__ == "__main__":
    unittest.main()
