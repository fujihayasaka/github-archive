# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module AssigneesHelper
      MAX_LOGIN_NAMES_LENGTH = 10

      def extract_logins_from_string(logins)
        logins.split(/\s*,\s*/).take(MAX_LOGIN_NAMES_LENGTH)
      end

      def get_valid_assignees_from_logins(repository, logins)
        users = User.where(login: logins).to_a

        # Follows the logic inside `available_assignee_ids` except is performant as we only look at the users we care about
        valid_ids = repository.user_ids_with_privileged_access(actor_ids_filter: users.map(&:id))
        valid_users = users.select { |user| valid_ids.include?(user.id) }
        ArrayWrapper.new(valid_users)
      end
    end
  end
end
