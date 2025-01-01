# typed: false
# frozen_string_literal: true

# We store a user's settings in a single record with a json column.
# This gives us a way to add new values that doesn't require a database migration
# every time.
module User::SettingsDependency
  extend ActiveSupport::Concern

  included do
    # We don't intend to interact with user_settings_record directly.
    # We'll alway use `settings`, defined below.
    has_one :user_settings_record, class_name: "UserSettings"
    validates_associated :user_settings_record

    # Lazily instantiate a UserSettings record for the user
    # if we try to access it.
    # ````
    # irb> user.settings.get(:tab_size)
    # ```
    # Will create a UserSettings record for the user if one doesn't exist.
    # This will also mark the user as dirty.  Saving the user will insert
    # the new settings record into the database as well.
    def settings
      user_settings_record || build_user_settings_record
    end

    def use_fixed_width_font?
      return @use_fixed_width_font if defined?(@use_fixed_width_font)
      @use_fixed_width_font = settings.get(:use_fixed_width_font)
    end

    def paste_url_link_as_plain_text?
      return @paste_url_link_as_plain_text if defined?(@paste_url_link_as_plain_text)
      @paste_url_link_as_plain_text = !settings.get(:paste_url_markdown)
    end
  end
end
