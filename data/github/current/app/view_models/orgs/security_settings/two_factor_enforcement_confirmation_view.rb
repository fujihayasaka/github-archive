# typed: true
# frozen_string_literal: true

module Orgs
  module SecuritySettings
    class TwoFactorEnforcementConfirmationView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include GitHub::Memoizer

      attr_reader :organization

      delegate :affiliated_users_with_two_factor_disabled_scopes,
        :affiliated_user_ids_with_two_factor_disabled_counts,
        :outside_collaborators_with_two_factor_disabled,
        :prevent_removal_of_scim_managed_user?,
        to: :organization

      def users_with_two_factor_disabled_count
        affiliated_user_ids_with_two_factor_disabled_counts
      end

      def users_with_two_factor_disabled(limit: 100)
        return @users_with_two_factor_disabled if defined?(@users_with_two_factor_disabled)
        users_with_two_factor_disabled = Set.new
        remainder = limit

        affiliated_users_with_two_factor_disabled_scopes(limit: limit).each do |scope|
          users = scope.limit(remainder)
          users_with_two_factor_disabled.merge users
          remainder = remainder - users.size
          break if remainder <= 0
        end

        @users_with_two_factor_disabled = users_with_two_factor_disabled.to_a
      end

      # no need to distinguish OCs after https://github.com/github/authorization/issues/4526
      memoize def tmp_collaborators_with_two_factor_disabled_count
        outside_collaborators_with_two_factor_disabled.count
      end

      # no need to distinguish OCs after https://github.com/github/authorization/issues/4526
      # intentional imperfect memoization - memoization performance more valuable than correctness if called w/ different limit
      def tmp_collaborators_with_two_factor_disabled(limit: 100)
        return @tmp_collaborators_with_two_factor_disabled if defined?(@tmp_collaborators_with_two_factor_disabled)

        @tmp_collaborators_with_two_factor_disabled = outside_collaborators_with_two_factor_disabled(limit: limit)
      end

      def private_forks_count_for(user)
        @private_fork_counts ||= Repository.organization_member_private_forks(
          organization, users_with_two_factor_disabled).group(:owner_id).count

        @private_fork_counts[user.id] || 0
      end

      def show_private_forks_count_for?(user)
        private_forks_count_for(user) > 0
      end

      def prevented_from_removal_due_to_enterprise_team?(user)
        organization.prevent_removal_of_scim_managed_user?(user: user, reason: :enterprise_team)
      end
    end
  end
end
