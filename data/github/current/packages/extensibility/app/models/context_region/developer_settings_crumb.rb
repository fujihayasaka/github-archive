# typed: true
# frozen_string_literal: true

module ContextRegion
  class DeveloperSettingsCrumb < Crumb
    def label
      "Developer Settings"
    end

    def parent
      BasicCrumb.new(nil, label: "Settings", path_name: :settings_user_profile_path)
    end

    def path_name
      :settings_user_apps_path
    end
  end
end
