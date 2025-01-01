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
      return false unless GitHub.models_enabled?
      true
    end

    def sub_sections
      [{
        display_name: "Development",
        item_id: :github_models_organization_access_policy,
        path: organization_settings_models_access_policy_path(@entity),
      }, {
        display_name: "Custom models",
        item_id: :github_models_organization_custom_models,
        path: org_settings_byok_custom_models_path(@entity),
      }]
    end
  end
end
