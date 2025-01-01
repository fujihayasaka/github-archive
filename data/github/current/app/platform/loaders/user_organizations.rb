# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class UserOrganizations < Platform::Loader
      def self.load(user)
        return ::Promise.resolve([]) unless user.present?

        self.for.load(user.id).then do |organization_ids|
          # load the Organization records
          Loaders::ActiveRecord.load_all(::Organization, organization_ids).then do |orgs|
            orgs.compact.map(&:id).sort
          end
        end
      end

      # Internal: fetch the Organization IDs for the list of User IDs.
      #
      # Returns a Hash{user_id Integer => Array[organization_id Integer...]}.
      def fetch(user_ids)
        results = Hash.new { |h, k| h[k] = [] }

        # Fetch organization memberships for all users in a single query
        memberships = ::Ability.organization_memberships_for_user(actor_id: user_ids).pluck(:actor_id, :subject_id)

        # Group the memberships by user ID
        memberships.each do |user_id, organization_id|
          results[user_id] << organization_id
        end

        results
      end
    end
  end
end
