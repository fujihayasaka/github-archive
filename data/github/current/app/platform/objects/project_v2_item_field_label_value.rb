# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2ItemFieldLabelValue < Platform::Objects::Base
      description "The value of the labels field in a Project item."

      class << self
        # Delegate static methods to the ProjectV2 helper.
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2ItemFieldValue
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2ItemFieldValue
      end

      visibility :public, environments: [:dotcom, :enterprise]

      minimum_accepted_scopes ["read:project"]

      field :labels, Connections.define(Objects::Label), description: "Labels value of a field", null: true, scope: true
      def labels
        ArrayWrapper.new(@object.labels)
      end

      field :field, Platform::Unions::ProjectV2FieldConfiguration,  description: "The field that contains this value.", null: false
    end
  end
end
