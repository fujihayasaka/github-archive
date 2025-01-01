# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueDependenciesSummary < Platform::Objects::Base
      description "Summary of the state of an issue's dependencies"

      # Access to dependency summary is dependent on access to the parent object
      def self.async_api_can_access?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Access to dependency summary is dependent on access to the parent object
      def self.async_viewer_can_see?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      field :blocked_by, Integer, description: "Count of issues this issue is blocked by", null: false
      field :blocking, Integer, description: "Count of issues this issue is blocking", null: false
    end
  end
end
