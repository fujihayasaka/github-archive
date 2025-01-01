# typed: true
# frozen_string_literal: true

# UserSettings is meant to be a sane first choice for storing preferences
# for a user. A given user will have a single UserSettings record.
# We store settings in a single json column.  This lets us add
# new ones without having to do a database migration. Note that querying the table
# based on the settings column is not recommended.  For settings that need to be
# queryable, consider adding a new column to the `user_settings` table.
#
# ## Working with attributes from the `settings` json column
# ### Adding new attributes to the json column
#
# If we won't need to find a user by the new setting, we should put it into the
# `settings` JSON column. We do that by adding new attributes to the
# `SettingsCollection.configure` block.
#
# ### Retrieving values
#
# If an `attribute tab_size` is configured, you can use the `get` method to
# retrieve the value of that attribute.
# ```
# irb> user_settings = UserSettings.first
# irb> user_settings.get(:tab_size)
# => 4
# ````
#
# ### Updating values
#
# Use the `set!` method to update the value of an attribute.
# This will immediately persist the change to the database, and will
# raise an ActiveRecord::RecordInvalid exception if the value is invalid.
# We'll raise an ArgumentError if the attribute doesn't exist.
# ```
# irb> user_settings = UserSettings.first
# irb> user_settings.set!(:tab_size, 4) # returns the updated user_settings record
# irb> user_settings.set!(:tab_size, -5) # raises ActiveRecord::RecordInvalid
# irb> user_settings.set!(:yar, -5) # raises ArgumentError
# ````
class UserSettings < ApplicationRecord::Domain::Users
  belongs_to :user

  # Set up the :settings column to store validated JSON attributes.
  ::SettingsCollection.configure(self) do
    DEFAULT_TAB_SIZE = 8
    TAB_SIZES = [1, 2, 3, 4, 5, 6, DEFAULT_TAB_SIZE, 10, 12]

    TRUST_TIERS = [-1, TrustTiers::Tier::TRUSTED, TrustTiers::Tier::NEUTRAL, TrustTiers::Tier::UNTRUSTED]

    DEFAULT_KEYBOARD_SHORTCUTS_PREFERENCE = "all"
    KEYBOARD_SHORTCUTS_PREFERENCE = [DEFAULT_KEYBOARD_SHORTCUTS_PREFERENCE, "no_character_key"].freeze

    DEFAULT_ANIMATED_IMAGES = "system"
    ANIMATED_IMAGES_OPTIONS = %w(enabled disabled system).freeze

    CALCULATED_SPONSORS_TRUST_LEVEL = Sponsors::TrustLevel::CALCULATED.to_s
    SPONSORS_TRUST_LEVELS = Sponsors::TrustLevel::TRUST_LEVEL_OPTIONS.map(&:to_s).freeze

    attribute :tab_size, :integer, default: DEFAULT_TAB_SIZE
    attribute :keyboard_shortcuts_preference, :string, default: DEFAULT_KEYBOARD_SHORTCUTS_PREFERENCE
    attribute :command_palette_open_hotkey, :string, default: CommandPalette::Hotkey::DEFAULT_SEARCH_MODE_HOTKEY
    attribute :command_palette_open_command_mode_hotkey, :string, default: CommandPalette::Hotkey::DEFAULT_COMMAND_MODE_HOTKEY
    attribute :animated_images, :string, default: DEFAULT_ANIMATED_IMAGES
    attribute :paste_url_markdown, :boolean, default: true
    attribute :use_fixed_width_font, :boolean, default: false
    attribute :link_underlines, :boolean, default: true
    attribute :hovercards_enabled, :boolean, default: true

    # by default the tier is dynamically calculated in app/models/trust_tiers/tier.rb
    # so we set it to -1 here
    attribute :trust_tier, :integer, default: -1

    attribute :user_profile_lists_sorting_strategy, :string, default: "updated_at.desc"

    attribute :repository_onboarding_enabled, :boolean, default: false
    attribute :pull_request_file_tree_visible, :boolean, default: true
    attribute :discussions_collapsed_view, :boolean, default: false

    attribute :copilot_chat_visible, :boolean, default: true
    attribute :copilot_policy_data, :string, default: "{}"

    attribute :user_feed_filter_setting, :integer, default: 0
    attribute :user_profile_feed_visible, :boolean, default: false

    attribute :trust_level_as_sponsor, :string, default: CALCULATED_SPONSORS_TRUST_LEVEL
    attribute :trust_level_as_sponsorable, :string, default: CALCULATED_SPONSORS_TRUST_LEVEL
    attribute :hide_past_sponsorships_on_sponsor_listing, :boolean, default: false

    # bitmask to store which Sponsors emails the maintainer would like to opt out of receiving
    attribute :sponsors_email_opt_outs, :integer, default: 0

    # bitmask to store the maintainer's settings for displaying featured sponsorships
    attribute :sponsors_featured_sponsorships_settings, :integer, default: 0

    attribute :blackbird_custom_scopes, :string, default: ""
    attribute :forks_view_default_options, :string, default: "{}"

    attribute :tree_view_expanded, :boolean, default: true
    attribute :symbols_view_expanded, :boolean, default: false
    attribute :code_line_wrap_enabled, :boolean, default: false
    attribute :orgs_repos_compact_mode, :boolean, default: false

    attribute :display_orcid_id_on_profile, :boolean, default: true

    validates :tab_size, inclusion: { in: TAB_SIZES }
    validates :keyboard_shortcuts_preference, inclusion: { in: KEYBOARD_SHORTCUTS_PREFERENCE }
    validates :trust_tier, inclusion: { in: TRUST_TIERS }

    validates :command_palette_open_hotkey, inclusion: { in: CommandPalette::Hotkey::VALID_SEARCH_MODE_HOTKEYS }
    validates :command_palette_open_command_mode_hotkey, inclusion: { in: CommandPalette::Hotkey::VALID_COMMAND_MODE_HOTKEYS }

    validates :animated_images, inclusion: { in: ANIMATED_IMAGES_OPTIONS }

    validates :trust_level_as_sponsor, inclusion: { in: SPONSORS_TRUST_LEVELS }
    validates :trust_level_as_sponsorable, inclusion: { in: SPONSORS_TRUST_LEVELS }
  end
end
