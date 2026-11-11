# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class VisibleOrganizationMemberCheck < Platform::Loader
      def self.load(viewer, organization, user_id)
        organization.async_business.then do
          self.for(viewer, organization).load(user_id)
        end
      end

      def initialize(viewer, organization)
        @viewer = viewer
        @organization = organization
      end

      def fetch(user_ids)
        visible_user_ids = ::ActiveRecord::Base.connected_to_many([ApplicationRecord::IamAbilities], role: :reading) do
          @organization.visible_user_ids_for(@viewer, actor_ids: user_ids)
        end

        result = visible_user_ids.map { |user_id| [user_id, true] }.to_h
        result.default = false
        result
      end
    end
  end
end
