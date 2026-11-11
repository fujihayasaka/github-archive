# typed: false
# frozen_string_literal: true

module Settings
  class TabSizeSelectComponent < ApplicationComponent
    attr_reader :user

    def initialize(user:)
      @user = user
    end

    # We need to label the default tab size as such
    def tab_size_options
      UserSettings::TAB_SIZES.map do |size|
        label = if UserSettings.is_default_value?(:tab_size, size)
          "#{size} (Default)"
        else
          size
        end
        [label, size]
      end
    end
  end
end
