# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class ShouldPullRequestWorkflowsRunForUser
        include GitHub::Memoizer

        attr_reader :actor, :author, :repo, :pull_request_id, :head_ref

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

          @pull_request_id = extract_pull_request_id(request)
          @head_ref = extract_head_ref(request)
        end

        def call
          return Twirp::Error.not_found("user does not exist", argument: "user_id") unless actor
          return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repo
          return Twirp::Error.not_found("repository owner does not exist") unless repo.owner

          return { run_workflows: false } if block_for_automation_pr?

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

        # Whether CI should be blocked because this PR's head branch was produced
        # by a CCA automation. Returns false unless the FF is on for the repo,
        # the request carries PR id + head ref, AND a matching is_triggered
        # session exists for the same PR + branch. Telemetry fires only on the
        # actual block.
        #
        # We match on head_ref (branch name) rather than head_sha because the
        # CCA session record only tracks the branch, not the commit SHA. This is
        # branch-level rather than commit-level, but it's scoped to a specific
        # PR (resource_id) so reused branch names on later unrelated PRs won't
        # cause false blocks.
        sig { returns(T::Boolean) }
        memoize def block_for_automation_pr?
          return false unless repo.present? && head_ref.present? && pull_request_id.present?
          return false unless FeatureFlag.vexi.enabled?(:agent_automations_block_ci_policy, repo, default: false)

          blocked = Copilot::AgentSession.triggered_for_pr(
            repository_id: repo.id,
            pull_request_id: pull_request_id,
            head_ref: head_ref,
          ).exists?
          if blocked
            GitHub.dogstats.increment(
              "actions.pr_workflows.blocked_for_copilot_automation",
              tags: ["repo_visibility:#{repo.public? ? 'public' : 'private'}"],
            )
          end
          blocked
        end

        sig { params(request: T.untyped).returns(T.nilable(Integer)) }
        def extract_pull_request_id(request)
          return nil unless request.respond_to?(:pull_request_id)

          identity = request.pull_request_id
          return nil if identity.nil?

          global_id = identity.respond_to?(:global_id) ? identity.global_id.presence : nil
          return nil if global_id.nil?

          Platform::Helpers::NodeIdentification.from_global_id(global_id).last.to_i
        end

        # Returns the PR's head branch name, normalized to match how
        # sweagentd persists it on `copilot_agent_sessions.head_ref`:
        # plain branch name without the `refs/heads/` prefix. We strip the
        # prefix defensively in case Launch ever sends the fully qualified form.
        sig { params(request: T.untyped).returns(T.nilable(String)) }
        def extract_head_ref(request)
          return nil unless request.respond_to?(:head_ref)

          raw = request.head_ref.presence
          return nil if raw.nil?

          raw.sub(%r{\Arefs/heads/}, "")
        end

        sig { params(user: User).returns(T.nilable(T::Boolean)) }
        def run_workflows_for_user?(user)
          # SWE agent users use the configured setting
          if CopilotSweAgent::Helpers.is_user_swe_agent?(user) && repo.present?
            return !Copilot::SweAgentConfiguration.require_workflow_approval_for_copilot_prs?(repo)
          end

          if user.is_a?(Bot) && bot_requires_workflow_approval?(user)
            GitHub.dogstats.increment(
              "actions.pr_workflows.bot_requires_workflow_approval",
              tags: [
                "role:#{user_role(user)}",
                "repo_visibility:#{repo.public? ? 'public' : 'private'}"
              ]
            )
            return false
          end

          # Bots from GitHub Apps that don't have the actions_require_workflow_approval capability
          # and have their app installed on the repository's owner should be trusted to run workflows
          # without approval. This fixes an issue where GitHub App bots (like copybara-service) with
          # installations on the repo were incorrectly being subjected to fork PR approval policies.
          # Bots without an installation on the repo owner (external app scenario) fall through to
          # the fork PR policy checks.
          if user.is_a?(Bot) && repo.present? && user.integration&.installed_on?(repo.owner)
            GitHub.dogstats.increment(
              "actions.pr_workflows.non_privileged_bot_trusted",
              tags: [
                "role:#{user_role(user)}",
                "repo_visibility:#{repo.public? ? 'public' : 'private'}"
              ]
            )
            return true
          end

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
          else
            GitHub.dogstats.increment(
              "actions.pr_workflows.unknown_fork_pr_approvals_policy",
              tags: [
                "policy:#{repo.actions_fork_pr_approvals_policy}",
                "repo_visibility:public",
                "role:#{user_role(user)}"
              ]
            )
            false
          end
        end

        sig { params(user: User).returns(T::Boolean) }
        def run_workflows_for_user_in_private_repo?(user)
          case repo.actions_private_fork_pr_approvals_policy
          when Configurable::ActionsPrivateForkPrApprovals::NONE
            true
          when Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS
            repo.writable_by?(user)
          else
            GitHub.dogstats.increment(
              "actions.pr_workflows.unknown_fork_pr_approvals_policy",
              tags: [
                "policy:#{repo.actions_private_fork_pr_approvals_policy}",
                "repo_visibility:private",
                "role:#{user_role(user)}"
              ]
            )
            false
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

        sig { params(bot: Bot).returns(T::Boolean) }
        def bot_requires_workflow_approval?(bot)
          if FeatureFlag.vexi.enabled?(:actions_use_agentic_app_registry_for_workflow_approval, bot.integration, default: false)
            agent = AgenticApp.agent_for_bot_id(bot.id)
            return agent.require_workflow_approval_for_prs? if agent

            false
          else
            Apps::Privileged.capable?(:actions_require_workflow_approval, app: bot.integration)
          end
        end

        sig { params(user: User).returns(String) }
        def user_role(user)
          if user == actor
            "actor"
          elsif user == author
            "author"
          else
            "unknown"
          end
        end
      end
    end
  end
end
