# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class ShouldPullRequestWorkflowsRunForUser
        include GitHub::Memoizer

        attr_reader :actor, :author, :repo

        def self.call(req)
          new(req).call
        end

        def initialize(request)
          user_id = Platform::Helpers::NodeIdentification.from_global_id(request.user.global_id).last
          @actor = User.find_by(id: user_id)

          repository_id = Platform::Helpers::NodeIdentification.from_global_id(request.repository.global_id).last
          @repo = Repositories.domain.by_id(repository_id.to_i)

          @author = T.let(nil, T.nilable(User))
          if request.author
            if request.author.global_id == request.user.global_id
              @author = @actor
            else
              author_id = Platform::Helpers::NodeIdentification.from_global_id(request.author.global_id).last
              @author = User.find_by(id: author_id)
            end
          end
        end

        def call
          return Twirp::Error.not_found("user does not exist", argument: "user_id") unless actor
          return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repo
          return Twirp::Error.not_found("repository owner does not exist") unless repo.owner

          if require_author?
            return Twirp::Error.not_found("author does not exist", argument: "author_id") unless author
          end

          if author.present? && author != actor
            {
              run_workflows: run_workflows_for_user?(actor) && run_workflows_for_user?(author)
            }
          else
            {
              run_workflows: run_workflows_for_user?(actor)
            }
          end
        end

        private

        memoize def require_author?
          return false unless repo.present?

          repo.feature_flag_enabled_or_raise?(:actions_workflow_approvals_require_author) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        end

        sig { params(user: User).returns(T.nilable(T::Boolean)) }
        def run_workflows_for_user?(user)
          return run_workflows_for_user_in_public_repo?(user) if repo.public?
          run_workflows_for_user_in_private_repo?(user)
        end

        sig { params(user: User).returns(T.nilable(T::Boolean)) }
        def run_workflows_for_user_in_public_repo?(user)
          return true if user_is_collaborator?(user)

          case repo.actions_fork_pr_approvals_policy
          when Configurable::ActionsForkPrApprovals::ALL_OUTSIDE_COLLABORATORS
            false
          when Configurable::ActionsForkPrApprovals::FIRST_TIME_CONTRIBUTORS
            user_is_contibutor?(user)
          when Configurable::ActionsForkPrApprovals::FIRST_TIME_CONTRIBUTOR_NEW_USERS
            !user_is_untrusted?(user) || user_is_contibutor?(user)
          end
        end

        sig { params(user: User).returns(T::Boolean) }
        def run_workflows_for_user_in_private_repo?(user)
          case repo.actions_private_fork_pr_approvals_policy
          when Configurable::ActionsPrivateForkPrApprovals::NONE
            true
          when Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS
            repo.writable_by?(user)
          end
        end

        sig { params(user: User).returns(T::Boolean) }
        def user_is_collaborator?(user)
          return true if repo.owner == user
          return true if repo.member?(user)

          repo.owner.organization? && repo.owner.member?(user)
        end

        sig { params(user: User).returns(T::Boolean) }
        def user_is_contibutor?(user)
          # User is a contributor to the repository
          # Note: Commit contributions are not tracked for forked repositories
          return true if repo.contributor?(user)

          # Are there any merged pull request in the repository created by this user?
          repo.pull_requests.where(user: user).where.not(merged_at: nil).any?
        end

        sig { params(user: User).returns(T::Boolean) }
        def user_is_untrusted?(user)
          TrustTiers::Tier.for_billable_owner(user).tier == TrustTiers::Tier::UNTRUSTED
        end
      end
    end
  end
end
