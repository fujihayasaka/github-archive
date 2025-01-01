# typed: true
# frozen_string_literal: true

module Settings
  class GitHubModelsNavComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    delegate_missing_to :@item

    rescue_from ActiveRecord::ActiveRecordError, with: :nothing

    def initialize(entity:, **system_arguments)
      @entity = entity
      @system_arguments = system_arguments
      @item = T.unsafe(Primer::Beta::NavList::Item).new(label: "Models", **@system_arguments)
    end

    private

    def render?
      policies_enabled? || custom_models_enabled?
    end

    def sub_sections
      sections = []

      if policies_enabled?
        sections << {
          display_name: "Development",
          item_id: :github_models_organization_access_policy,
          path: organization_settings_models_access_policy_path(@entity),
        }
      end

      if custom_models_enabled?
        sections << {
          display_name: "Custom models",
          item_id: :github_models_organization_custom_models,
          path: org_settings_byok_custom_models_path(@entity),
        }
      end

      sections
    end

    memoize def policies_enabled?
      user_feature_enabled?(:github_models_org_access_policies) || @entity.feature_enabled?(:github_models_org_access_policies)
    end

    memoize def custom_models_enabled?
      @entity.feature_enabled?(:github_models_byok)
    end
  end
end
