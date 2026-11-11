# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class AgentNeedsAuthorization < Platform::Loader
      def self.load(viewer_id, integration_id)
        self.for(viewer_id).load(integration_id)
      end

      def initialize(viewer_id)
        @viewer_id = viewer_id
      end

      def fetch(integration_ids)
        user = User.find_by(id: @viewer_id)
        return integration_ids.index_with { false } unless user

        integration_ids_needing_authorization = AgenticApp::NeedsAuthorizationLookup.for_integration_ids(
          user: user,
          integration_ids: integration_ids,
        )

        integration_ids.index_with do |integration_id|
          integration_ids_needing_authorization.include?(integration_id)
        end
      end
    end
  end
end
