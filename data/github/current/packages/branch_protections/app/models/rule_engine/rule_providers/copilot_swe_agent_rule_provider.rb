# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class CopilotSweAgentRuleProvider < RuleProvider
      include GitRuleProvider

      COPILOT_BRANCH_PREFIX = "refs/heads/copilot/".freeze

      def initialize
        super(identifier: "copilot_swe_agent")
      end

      sig { override.params(repository: Repository, ref_updates: T::Array[Git::Ref::Update], actor: T.nilable(Types::Actor)).returns(T::Array[IRuleConfig]) }
      def rules_for_ref_updates(repository, ref_updates, actor)
        # Copilot is not available on GitHub Enterprise
        return [] if GitHub.enterprise?
        # Passing nil for the user parameter since the actor here is a bot
        # And the copilot_swe_agent_enabled? method only needs user for policy/model checks
        return [] unless actor.is_a?(Bot) && repository.copilot_swe_agent_enabled?(actor)
        return [] unless actor.is_a?(Bot) && actor == Apps::Privileged.integration(:copilot_swe_agent)&.bot

        disallowed_refs = if FeatureFlag.vexi.enabled?(:copilot_swe_agent_work_on_current_branch, repository.owner, repository, default: false)
          # New behavior: allow pushes to non-copilot branches if there's an active job on the PR
          default_branch_ref_name = "refs/heads/#{repository.default_branch}"

          disallowed_ref_updates = ref_updates.select do |ref_update|
            refname = ref_update.get_attribute(Targeting::Attribute::RefName)
            # Always block pushes to the default branch
            next true if refname == default_branch_ref_name

            # Allow pushes to copilot/ branches
            next false if refname.starts_with?(COPILOT_BRANCH_PREFIX)

            # For non-copilot branches, block unless there's a running job for the PR
            !has_running_job_for_pull_request?(repository, ref_update)
          end
          disallowed_ref_updates.map { |ref_update| ref_update.get_attribute(Targeting::Attribute::RefName) }
        else
          # Old behavior: block all non-copilot branches
          ref_updates.map { |ref_update| ref_update.get_attribute(Targeting::Attribute::RefName) }.reject { |ref| ref.starts_with?(COPILOT_BRANCH_PREFIX) }
        end

        [RuntimeRuleConfig.new(
          provider: self,
          source: repository,
          rule_type: "creation",
          matching_ref_names: disallowed_refs
        ), RuntimeRuleConfig.new(
          provider: self,
          source: repository,
          rule_type: "update",
          matching_ref_names: disallowed_refs
        ), RuntimeRuleConfig.new(
          provider: self,
          source: repository,
          rule_type: "deletion",
          matching_ref_names: disallowed_refs
        )]
      end

      sig { override.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[IRuleConfig]) }
      def rule_for_branch_evaluators(repository, ref_names)
        []
      end

      sig do
        override.params(
          rule_config: IRuleConfig,
          actor: T.nilable(Types::Actor),
          targetable: Targeting::Targetable,
          rule_run: T.nilable(RuleRun)
        ).returns(T::Boolean)
      end
      def can_bypass?(rule_config, actor, targetable, rule_run = nil)
        false
      end

      private

      # Returns false on any error to fail-safe (deny the push if we can't verify).
      sig { params(repository: Repository, ref_update: Git::Ref::Update).returns(T::Boolean) }
      def has_running_job_for_pull_request?(repository, ref_update)
        branch_name = ref_update.get_attribute(Targeting::Attribute::RefName).delete_prefix("refs/heads/")
        pull_request = repository.pull_requests_as_head.where(base_repository_id: repository.id).open_pulls.find_by(head_ref: branch_name) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        return false unless pull_request

        # Early return if sweagentd URL is not configured (e.g., in test environments)
        return false if GitHub.sweagentd_url.blank?

        jobs_client = GitHub::Sweagentd::Client.jobs
        jobs_response = jobs_client.list_jobs_for_pull_request(
          Sweagentd::JobsAPI::V1::ListJobsForPullRequestRequest.new(
            owner_id: repository.owner_id,
            repo_id: repository.id,
            pull_request_id: pull_request.id
          )
        )

        jobs = jobs_response&.data&.jobs || []
        running_jobs = jobs.select { |job| job.status == :JOB_STATUS_RUNNING }

        running_jobs.size == 1
      rescue StandardError => e
        GitHub.logger.error(
          "CopilotSweAgentRuleProvider: failed to check for copilot job",
          error: e.message,
          error_class: e.class.name,
          "gh.repo.id": repository.id,
          "gh.pull_request.id": pull_request&.id,
          "gh.ref": ref_update.get_attribute(Targeting::Attribute::RefName)
        )

        # Fail-safe: deny the push if we can't verify there's a job
        false
      end
    end
  end
end
