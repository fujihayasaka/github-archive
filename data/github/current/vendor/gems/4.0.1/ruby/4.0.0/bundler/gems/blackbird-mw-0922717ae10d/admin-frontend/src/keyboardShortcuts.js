import { useEffect } from "react";

export const HOTKEY_SEARCH = "search";
export const HOTKEY_SHORTCUTS = "shortcuts";
export const HOTKEY_GITHUB_DEV = "github.dev";
export const HOTKEY_GITHUB_COM = "github.com";
export const HOTKEY_UP = "up";
export const HOTKEY_DOWN = "down";
export const HOTKEY_ENTER = "enter";
export const HOTKEY_PAUSE = "pause";

const hotkeys = {
  [HOTKEY_SEARCH]: [{ modifier: "alt", key: "f" }, { key: "/" }],
  [HOTKEY_SHORTCUTS]: [{ key: "?" }],
  [HOTKEY_GITHUB_DEV]: [{ key: "." }],
  [HOTKEY_GITHUB_COM]: [{ key: "," }],
  [HOTKEY_UP]: [{ key: "k" }],
  [HOTKEY_DOWN]: [{ key: "j" }],
  [HOTKEY_ENTER]: [{ key: "Enter" }],
  [HOTKEY_PAUSE]: [{ key: " " }],
};

function modifierIsActive(e, modifier) {
  if (modifier === "alt" && e.altKey) {
    return true;
  }

  if (modifier === "ctrl" && e.ctrlKey) {
    return true;
  }

  return false;
}

export default function useHotkey(name, effect) {
  // let currentUser = useCurrentUser();

  useEffect(() => {
    function handleKeyboard(e) {
      // Don't do anything if we're typing into an input
      if (
        window.document.activeElement.type === "text" ||
        window.document.activeElement.type === "textarea"
      ) {
        return;
      }

      // Don't use hotkeys if the user has disabled character key shortcuts
      // if (
      //   currentUser?.user_settings?.keyboard_shortcuts_preference ===
      //   "no_character_key"
      // ) {
      //   return;
      // }

      for (const shortcut of hotkeys[name]) {
        if (e.key !== shortcut.key) {
          continue;
        }
        if (shortcut.modifier && !modifierIsActive(e, shortcut.modifier)) {
          continue;
        }

        effect();
        e.preventDefault();
        return;
      }
    }

    window.addEventListener("keydown", handleKeyboard);
    return () => {
      window.removeEventListener("keydown", handleKeyboard);
    };
  });
}
