# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class ShouldPullRequestWorkflowsRunForUser
        attr_reader :user, :repo

        def self.call(req)
          new(req).call
        end

        def initialize(request)
          user_id = Platform::Helpers::NodeIdentification.from_global_id(request.user.global_id).last
          @user = User.find_by(id: user_id)

          repository_id = Platform::Helpers::NodeIdentification.from_global_id(request.repository.global_id).last
          @repo = Repository.find_by(id: repository_id)
        end

        def call
          return Twirp::Error.not_found("user does not exist", argument: "user_id") unless user
          return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repo
          return Twirp::Error.not_found("repository owner does not exist") unless repo.owner

          {
            run_workflows: run_workflows_for_user?
          }
        end

        private

        def run_workflows_for_user?
          return run_workflows_for_user_in_public_repo? if repo.public?
          run_workflows_for_user_in_private_repo?
        end

        def run_workflows_for_user_in_public_repo?
          return true if user_is_collaborator?

          case repo.actions_fork_pr_approvals_policy
          when Configurable::ActionsForkPrApprovals::ALL_OUTSIDE_COLLABORATORS
            false
          when Configurable::ActionsForkPrApprovals::FIRST_TIME_CONTRIBUTORS
            user_is_contibutor?
          when Configurable::ActionsForkPrApprovals::FIRST_TIME_CONTRIBUTOR_NEW_USERS
            !user_is_untrusted? || user_is_contibutor?
          end
        end

        def run_workflows_for_user_in_private_repo?
          case repo.actions_private_fork_pr_approvals_policy
          when Configurable::ActionsPrivateForkPrApprovals::NONE
            true
          when Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS
            repo.writable_by?(user)
          end
        end

        def user_is_collaborator?
          return true if repo.owner == user
          return true if repo.member?(user)

          repo.owner.organization? && repo.owner.member?(user)
        end

        def user_is_contibutor?
          # User is a contributor to the repository
          # Note: Commit contributions are not tracked for forked repositories
          return true if repo.contributor?(user)

          # Are there any merged pull request in the repository created by this user?
          repo.pull_requests.where(user: user).where.not(merged_at: nil).any?
        end

        def user_is_untrusted?
          TrustTiers::Tier.for_billable_owner(user).tier == TrustTiers::Tier::UNTRUSTED
        end
      end
    end
  end
end
