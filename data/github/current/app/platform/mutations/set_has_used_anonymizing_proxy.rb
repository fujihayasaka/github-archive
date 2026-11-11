# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetHasUsedAnonymizingProxy < Platform::Mutations::Base
      description "Set whether users have used anonymizing proxies."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :user_ids, [ID], "The global relay id of users to update.", required: true, loads: Objects::User
      argument :value, Boolean, "The boolean value to set it to, defaults to true.", required: false, default_value: true

      field :users, [Objects::User], "The users that were updated.", null: true

      def resolve(users:, value:, **inputs)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to set has_used_anonymizing_proxy."
        end

        users.each do |user|
          user.update_attribute(:has_used_anonymizing_proxy, value)
        end

        { users: users }
      end
    end
  end
end
