# typed: strict
# frozen_string_literal: true

module ContextRegion
  class DeveloperSettingsCrumb < Crumb
    sig { override.returns(String) }
    def label
      "Developer Settings"
    end

    sig { override.returns(Crumb) }
    def parent
      BasicCrumb.new(nil, label: "Settings", path_name: :settings_user_profile_path)
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :settings_user_apps_path
    end
  end
end
