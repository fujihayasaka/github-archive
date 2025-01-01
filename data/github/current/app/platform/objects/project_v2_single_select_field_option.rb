# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2SingleSelectFieldOption < Platform::Objects::Base
      description "Single select field option for a configuration for a project."

      class << self
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2
      end

      visibility :public, environments: [:dotcom, :enterprise]

      minimum_accepted_scopes ["read:project"]

      field :name, String, "The option's name.", null: false
      field :id, String, "The option's ID.", null: false
      field :option_id, String, "The option's internal identifier.  Note: not a global relay id, not globally unique",
        null: false, visibility: :internal
      field :name_html, String, "The option's html name.", null: false
      field :color, Enums::ProjectV2SingleSelectFieldOptionColor, "The option's display color.", null: false
      field :description, String, "The option's plain-text description.", null: false
      field :description_html, String, "The option's description, possibly containing HTML.", null: false
    end
  end
end
