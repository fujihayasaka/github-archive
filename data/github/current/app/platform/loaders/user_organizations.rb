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
      sig { params(user_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[Integer]]) }
      def fetch(user_ids)
        ::Ability.organization_memberships_for_users(user_ids:)
      end
    end
  end
end
