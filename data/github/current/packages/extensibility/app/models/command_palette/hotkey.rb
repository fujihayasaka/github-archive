# typed: true
# frozen_string_literal: true

module CommandPalette
  class Hotkey
    # This class is primarily used to build the settings form in AccessibilityPreferencesController#show,
    # as well as provide validations to User::SettingsCollection.

    # Change these hotkey strings with caution!

    # There are validators in User::SettingsCollection that can fail
    # if a user has stored a hotkey preference that isn't contained
    # in the list of valid hotkey strings.

    # It may be necessary to transition old stored user settings if any of these need to be changed.

    DEFAULT_SEARCH_MODE_HOTKEY = KeyboardShortcutsHelper::DEFAULT_COMMAND_PALETTE_HOTKEY
    DEFAULT_COMMAND_MODE_HOTKEY = KeyboardShortcutsHelper::DEFAULT_COMMAND_PALETTE_COMMAND_HOTKEY
    DISABLED_HOTKEY = "none"

    # Map of hotkeys stored in database using pre-`hotkey@3` syntax to their `hotkey@3` equivalents for use in the UI,
    # allowing us to avoid a database transition by mapping when we render them
    LEGACY_HOTKEYS = {
      "Mod+Shift+p" => "Mod+Shift+P",
      "Mod+Shift+k" => "Mod+Shift+K",
    }.freeze

    SEARCH_MODE_HOTKEYS = [
      DEFAULT_SEARCH_MODE_HOTKEY,
      "Mod+k",
      "Mod+Alt+k",
      DEFAULT_COMMAND_MODE_HOTKEY,
      "Mod+p",
      "Mod+Shift+P",
      DISABLED_HOTKEY,
    ].freeze

    VALID_SEARCH_MODE_HOTKEYS = SEARCH_MODE_HOTKEYS + LEGACY_HOTKEYS.keys

    COMMAND_MODE_HOTKEYS = [
      DEFAULT_COMMAND_MODE_HOTKEY,
      "Mod+k",
      "Mod+Alt+k",
      "Mod+p",
      "Mod+Shift+P",
      DISABLED_HOTKEY,
    ].freeze

    VALID_COMMAND_MODE_HOTKEYS = COMMAND_MODE_HOTKEYS + LEGACY_HOTKEYS.keys

    def self.search_mode_form_options(is_mac: false)
      self.form_options(mode: :search, is_mac: is_mac)
    end

    def self.command_mode_form_options(is_mac: false)
      self.form_options(mode: :command, is_mac: is_mac)
    end

    def self.form_options(mode: :search, is_mac: false)
      mode_name = mode.to_s.upcase
      hotkeys = const_get("#{mode_name}_MODE_HOTKEYS")
      default_hotkey = const_get("DEFAULT_#{mode_name}_MODE_HOTKEY")

      hotkeys.map do |hotkey_string|
        hotkey = new(hotkey_string, is_mac: is_mac)

        label = hotkey.to_label
        label += " (default)" if hotkey_string == default_hotkey

        [label, hotkey_string]
      end
    end

    attr_reader :hotkey

    def initialize(hotkey, is_mac: false)
      @hotkey = hotkey
      @is_mac = is_mac
    end

    def to_label
      return "Disabled" if hotkey == DISABLED_HOTKEY

      hotkey_combos = hotkey.split(",")

      hotkey_combos.map do |hotkey_string|
        hotkey_string.split("+").map do |key|
          key.sub("Mod", platform_modifier_key).downcase
        end.join(" + ")
      end.join(" or ")
    end

    def is_mac_platform?
      @is_mac
    end

    def platform_modifier_key
      is_mac_platform? ? "Command" : "Control"
    end
  end
end
