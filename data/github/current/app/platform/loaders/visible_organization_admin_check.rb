# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class VisibleOrganizationAdminCheck < Platform::Loader
      def self.load(viewer, organization, user_id)
        self.for(viewer, organization).load(user_id)
      end

      def initialize(viewer, organization)
        @viewer = viewer
        @organization = organization
      end

      def fetch(user_ids)
        visible_admin_ids = @organization.visible_user_ids_for(@viewer, type: :admin, actor_ids: user_ids)

        result = visible_admin_ids.map { |admin_id| [admin_id, true] }.to_h
        result.default = false
        result
      end
    end
  end
end
