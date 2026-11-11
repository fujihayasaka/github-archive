# rubocop:disable Metrics/MethodLength
# typed: strict
# frozen_string_literal: true

require "sweagentd"

module Issues
  class Domain
    class Copilot < GH::Domain::Base

      # Check if the issue is already assigned to the copilot user
      sig { params(issue: Issue, copilot: User, actor: User).returns(T::Boolean) }
      def assigned_to_copilot?(issue, copilot, actor)
        issue.assignees.include?(copilot)
      end

      # Triggers Copilot job from GraphQL mutations with custom assignment attributes
      sig { params(actor: User, issue: Issue, assignment_attributes: Issues::AgentAssignmentNewAttributes, token: ::Copilot::Token, user_session_id: T.nilable(Integer)).void }
      def trigger_copilot_job_from_mutation(actor:, issue:, assignment_attributes:, token:, user_session_id: nil)
        repository = T.must(issue.repository)

        # Log trigger_copilot_job_from_mutation calls when feature flag is enabled
        if FeatureFlag.vexi.enabled?(:issues_copilot_log_capi_request, actor, default: false)
          log_copilot_job_call(
            method_name: "trigger_copilot_job_from_mutation",
            actor: actor,
            issue: issue,
            repository: repository,
            assignment_attributes: assignment_attributes,
            token: token
          )
        end

        # Retry 401 errors by reminting token if user_session_id is provided
        max_retries = 3
        attempt = 0

        begin
          bot = assignment_attributes.resolve_bot
          return unless bot

          Issues.domain.reactions.add_eyes(issue, bot)

          if FeatureFlag.vexi.enabled?(:issues_copilot_use_twirp_api, actor, repository, repository.owner, default: false)
            trigger_copilot_job_twirp_api(actor:, issue:, assignment_attributes:)
          else
            trigger_copilot_job(actor:, issue:, assignment_attributes:, token:)
          end
        rescue CopilotAPI::UnauthorizedError, GitHub::Sweagentd::Client::Jobs::UnauthorizedError => e
          attempt += 1
          if user_session_id.present? && attempt <= max_retries
            GitHub.logger.info({
              body: "Retrying Copilot job after 401 error by reminting token",
              issue_id: issue.id,
              actor_id: actor.id,
              user_session_id: user_session_id,
              attempt: attempt,
              max_retries: max_retries
            })

            GitHub.dogstats.increment("issues.copilot.assign",
              tags: ["status:retry", "attempt:#{attempt}"])

            user_session = UserSession.find_by(id: user_session_id)
            if user_session && user_session.user_id == actor.id
              token = CopilotSessions::CopilotApiToken.get_encrypted(
                user: actor,
                entry_point: :copilot_job_retry_401,
                user_session: user_session,
                force_cache_miss: true
              )

              retry
            else
              # User session not found or doesn't match actor, re-raise
              GitHub.dogstats.increment("issues.copilot.unauthorized_error",
                tags: ["source:ui", "reason:invalid_session"])
              report_failbot(e, issue: issue, context: "copilot_job_retry_failed_invalid_session")
              raise e
            end
          else
            # No user_session_id or max retries exceeded, re-raise
            source = user_session_id.present? ? "ui" : "api"
            reason = user_session_id.present? ? "max_retries_exceeded" : "api_mutation"
            GitHub.dogstats.increment("issues.copilot.unauthorized_error",
              tags: ["source:#{source}", "reason:#{reason}"])
            report_failbot(e, issue: issue, context: "copilot_job_retry_failed_#{reason}")
            raise e
          end
        end
      end

      # High-level domain entrypoint used by the controller to perform one or many
      # copilot assignments via agent orchestration.
      # Returns the full assignment_results hash plus a :jobs entry consumed by the controller.
      sig do
        params(
          actor: User,
          issues: T::Array[Issue],
          assignment_attributes: Issues::AgentAssignmentNewAttributes,
          token: ::Copilot::Token,
          use_async: T::Boolean,
          user_session_id: T.nilable(Integer)
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def assign_copilot_to_issues(actor:, issues:, assignment_attributes:, token:, use_async:, user_session_id: nil)
        create_agent_assignment_records(assignment_attributes:, actor:, issues:)

        assignment_results = queue_agent_orchestration(
          actor: actor,
          issues: issues,
          assignment_attributes: assignment_attributes,
          token: token,
          user_session_id: user_session_id
        )

        jobs = assignment_results[:successful_issues].map { |issue| { issue_number: issue.number } }
        assignment_results.merge(jobs: jobs)
      end

      # Queues agent orchestration for issues (async).
      # Returns immediately after enqueuing orchestrations, without waiting for job API responses.
      sig do
        params(
          actor: User,
          issues: T::Array[Issue],
          assignment_attributes: Issues::AgentAssignmentNewAttributes,
          token: ::Copilot::Token,
          user_session_id: T.nilable(Integer)
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def queue_agent_orchestration(actor:, issues:, assignment_attributes:, token:, user_session_id: nil)
        assignment_results = {
          successful_issues: T.let([], T::Array[Issue]),
          exceptions: T.let([], T::Array[StandardError])
        }

        request_token = if token.is_a?(::Copilot::EncryptedToken)
          token
        else
          GitHub.encrypt_and_encode_capi_token(token.to_s)
        end

        copilot_context = {
          request_token: request_token.to_s,
          attributes: assignment_attributes,
          user_session_id: user_session_id
        }

        # All issues share the same assignment_attributes (target_repository, agent_id, etc.),
        # so we determine the bot once and preload assignees in bulk to avoid N+1 queries.
        repository = assignment_attributes.target_repository
        bot_to_assign = assignment_attributes.resolve_bot

        unless bot_to_assign
          assignment_results[:exceptions] << CopilotAPI::NotFoundError.new("No assignable agent found")
          return assignment_results
        end

        # Preload assignees for all issues to avoid N+1 queries
        issues_with_assignees = Issue.where(id: issues.map(&:id)).includes(:assignees).index_by(&:id)

        issues.each do |issue|
          begin
            issue_with_assignees = issues_with_assignees[issue.id] || issue

            unless Issues.domain.set_assignees?(issue_with_assignees, actor)
              assignment_results[:exceptions] << CopilotAPI::UnauthorizedError.new("Failed to assign agent to issue ##{issue.number}: Assignees validation failed")
              next
            end

            current_assignees = issue_with_assignees.assignees.to_a

            if current_assignees.any? { |a| a.id == bot_to_assign.id }
              GitHub.logger.info({
                body: "Skipping orchestration for issue ##{issue.number} as it is already assigned to agent #{bot_to_assign.display_login}",
              })
              next
            end

            new_assignees = (current_assignees + [bot_to_assign]).uniq

            update_attributes = Issues::UpdateIssueAttributes.new(
              assignees: Issues::UpdateIssueAttribute::Set.new(new_assignees),
            )

            result = Issues.domain.update(issue_with_assignees, update_attributes, actor, copilot_context: copilot_context)

            unless result.ok?
              error_message = result.error&.message || "Unknown error"
              assignment_results[:exceptions] << StandardError.new("Failed to assign agent to issue ##{issue.number}: #{error_message}")
              next
            end

            assignment_results[:successful_issues] << issue
          rescue StandardError => e
            report_failbot(e, issue: issue, context: "orchestration_issue_update")
            assignment_results[:exceptions] << e
          end
        end

        assignment_results
      end

      # Removes Copilot 👀 reactions for an issue when Copilot is among removed_assignee_ids.
      sig do
        params(
          issue: Issue,
          removed_assignee_ids: T.nilable(T::Array[Integer]),
          actor: T.nilable(User)
        ).void
      end
      def remove_eyes_emoji_reaction(issue:, removed_assignee_ids:, actor: nil)
        return if removed_assignee_ids.nil? || removed_assignee_ids.empty?

        agent_bot_ids_to_remove = T.let([], T::Array[Integer])
        removed_assignee_ids.each do |assignee_id|
          agent = AgenticApp.agent_for_bot_id(assignee_id)
          agent_bot_ids_to_remove << assignee_id if agent
        end

        # call report_failbot in case of error
        result = Issues.domain.reactions.remove_eyes(subject: issue, user_ids: agent_bot_ids_to_remove)
        error = result.error
        if error
          report_failbot(error.exception, issue: issue, context: "remove_eyes_reaction_failed")
        end
      end

      private

      # If a token is supplied then a new token will _not_ be minted, instead the provided token will be used.
      # If a token is not supplied then a new token will be minted using the active and user_session (if provided).
      sig do
        params(
          actor: User,
          token: ::Copilot::Token,
          real_ip: T.nilable(String)
        ).returns(::Copilot::User::CopilotApi)
      end
      def get_copilot_api(actor, token, real_ip: nil)
        ::Copilot::User.copilot_api(user: actor, integration_id: CopilotAPI::COPILOT_SWE_AGENT, token: token, real_ip: real_ip)
      end

      sig { returns(T.nilable(Bot)) }
      def get_copilot
        app = T.let(Apps::Privileged.integration(:copilot_swe_agent), T.nilable(Integration))
        app&.bot
      end

      sig do
        params(
          actor: User,
          issue: Issue,
          assignment_attributes: Issues::AgentAssignmentNewAttributes,
          token: ::Copilot::Token,
          async: T::Boolean,
          num_threads: Integer,
          request_timeout_s: T.nilable(Float),
        ).returns(T.untyped)
      end
      def trigger_copilot_job(actor:, issue:, assignment_attributes:, token:, async: false, num_threads: 1, request_timeout_s: nil)
        api = get_copilot_api(actor, token, real_ip: assignment_attributes.remote_ip)

        agent = AgenticApp.agent_for_integration_id(assignment_attributes.agent_id) || AgenticApp::CopilotAgent.instance
        agent_mention_slug = AgenticApp.mention_token(agent)

        creation_id = SecureRandom.uuid
        event_type = "issues_agent_assignment"

        # Only pass target_repository to the helper if it's different from the issue's repository
        target_repository = assignment_attributes.target_repository
        issue_repository = T.must(issue.repository)
        effective_target_repository = nil
        if target_repository != issue_repository
          effective_target_repository = target_repository
        end

        custom_instructions = assignment_attributes.custom_instructions
        result = CopilotSweAgentJobHelper.generate_issue_problem_statement(
          issue: issue,
          agent_instructions: custom_instructions,
          target_repository: effective_target_repository,
          agent_mention_slug: agent_mention_slug,
        )
        problem_statement = result[:statement]
        truncation_info = result[:truncation_info]

        emit_truncation_metrics(truncation_info: truncation_info, issue: issue)

        pr_body_placeholder, pr_body_suffix = CopilotSweAgentJobHelper.generate_pr_body(issue: issue)
        # Same as in sweagentd
        # See https://github.com/github/sweagentd/blob/73c9ba380646ac27b94c21b07073fee64fbeb0ff/internal/events/on_issue_assigned.go#L195
        pr_title = issue.title

        # Always use API version v1
        api_version = "v1"

        pull_request_data = {
            title: pr_title,
            body_placeholder: pr_body_placeholder,
            body_suffix: pr_body_suffix
          }

        if FeatureFlag.vexi.enabled?(:issues_copilot_labels, actor, issue_repository, issue_repository.owner, default: false)
          labels = issue.labels.pluck(:name)
          pull_request_data[:labels] = labels if labels.any?
        end

        clean_custom_agent = nil
        if FeatureFlag.vexi.enabled?(:copilot_swe_agent_use_subagents, actor, default: false)
          custom_agent = assignment_attributes.custom_agent
          if custom_agent
            custom_agent = custom_agent.strip
            custom_agent = nil if custom_agent.empty?
          end
          clean_custom_agent = custom_agent
        end

        # Log create_swe_agent_job calls when feature flag is enabled
        if FeatureFlag.vexi.enabled?(:issues_copilot_log_capi_request, actor, default: false)
          log_copilot_job_call(
            method_name: "trigger_copilot_job",
            actor: actor,
            issue: issue,
            repository: target_repository,
            assignment_attributes: assignment_attributes,
            token: token
          )
        end

        # Only send model parameter if feature flag is enabled
        model_param = if FeatureFlag.vexi.enabled?(:coding_agent_model_selection, actor, default: false)
          assignment_attributes.model
        else
          nil
        end

        decoupled_mode = CopilotFeatureFlagsHelper.decoupled_mode_enabled?(actor)
        use_tasks_api = CopilotFeatureFlagsHelper.issue_cca_visualization_enabled?(actor)

        create_pull_request = if decoupled_mode
          false
        else
          !assignment_attributes.skip_pull_request
        end

        tags = use_tasks_api ? ["method:mission_control"] : ["method:capi"]
        event_identifiers = ["issue::#{issue.number}", "issue_id::#{issue.id}"]

        response = Instrumentation.track_time("issues.copilot.create_job_api_call.duration_ms", tags:) do
          if use_tasks_api
            api.create_task(
              nwo: target_repository.name_with_display_owner,
              agent_id: assignment_attributes.agent_id,
              base_ref: assignment_attributes.base_ref,
              create_pull_request: create_pull_request,
              custom_agent: clean_custom_agent,
              event_type:,
              event_url: issue.url,
              model: model_param,
              problem_statement:,
              event_identifiers:,
            )
          else
            api.create_swe_agent_job(
              nwo: target_repository.name_with_display_owner,
              problem_statement: problem_statement,
              content_filter_mode: ::Copilot::User::CopilotApi::ContentFilterMode::Markdown,
              pull_request_data: pull_request_data,
              base_ref: assignment_attributes.base_ref,
              creation_id: creation_id,
              event_type: event_type,
              event_identifiers:,
              event_url: issue.url,
              api_version: api_version,
              use_staging: FeatureFlag.vexi.enabled?(:sweagentd_route_user_or_repo_to_staging, actor, issue_repository, issue_repository.owner, default: false),
              async: async,
              num_threads: num_threads,
              request_timeout_s: request_timeout_s,
              use_staging_sith_lord: FeatureFlag.vexi.enabled?(:sweagentd_route_user_or_repo_to_staging_sith_lord, actor, issue_repository, issue_repository.owner, default: false),
              use_staging_jedi_knight: FeatureFlag.vexi.enabled?(:sweagentd_route_user_or_repo_to_staging_jedi_knight, actor, issue_repository, issue_repository.owner, default: false),
              custom_agent: clean_custom_agent,
              agent_id: assignment_attributes.agent_id,
              model: model_param,
              skip_pull_request: assignment_attributes.skip_pull_request,
            )
          end
        end

        GitHub.dogstats.increment("issues.copilot.create_job_api_call.count", tags: tags + ["success:true"])

        update_agent_assignment_record(assignment_attributes:, actor:, issue:, response:) if use_tasks_api

        response
      end

      # Emit truncation metrics
      sig { params(truncation_info: T::Hash[Symbol, T.untyped], issue: Issue).void }
      def emit_truncation_metrics(truncation_info:, issue:)
        tags = [
          "comments_truncated:#{truncation_info[:comments_truncated] || false}",
          "comments_removed:#{truncation_info[:comments_removed] || 0}",
          "issue_body_truncated:#{truncation_info[:issue_body_truncated] || false}"
        ]

        GitHub.dogstats.increment("issues.copilot.problem_statement.generated", tags: tags)
      rescue StandardError => e
        report_failbot(e, issue: issue, context: "truncation_metrics_emission")
      end

      sig { params(exception: Exception, issue: T.nilable(Issue), context: String).void }
      def report_failbot(exception, issue:, context:)
        Failbot.report(exception, {
          app: "github",
          feature: "issues_copilot_assign",
          context: context,
          issue_id: issue&.id
        })
      rescue StandardError
        GitHub.logger.error(
          "[Copilot-Assign] Failbot reporting failed",
          error: exception.message,
          backtrace: exception.backtrace
        )
      end

      sig do
        params(
          method_name: String,
          actor: User,
          issue: Issue,
          repository: Repository,
          assignment_attributes: Issues::AgentAssignmentNewAttributes,
          token: T.nilable(::Copilot::Token)
        ).void
      end
      def log_copilot_job_call(method_name:, actor:, issue:, repository:, assignment_attributes:, token:)
        GitHub.logger.info("#{method_name} called",
          "gh.copilot.#{method_name}.hashed_token": token.present? ? Digest::SHA256.base64digest(token.to_s) : nil,
          "gh.copilot.#{method_name}.token_fingerprint": token.present? ? token.to_s.last(8) : nil,
          "gh.copilot.#{method_name}.actor_id": actor.id,
          "gh.copilot.#{method_name}.actor_login": actor.display_login,
          "gh.copilot.#{method_name}.issue_id": issue.id,
          "gh.copilot.#{method_name}.issue_number": issue.number,
          "gh.copilot.#{method_name}.repository_id": repository.id,
          "gh.copilot.#{method_name}.repository_nwo": repository.name_with_display_owner,
          "gh.copilot.#{method_name}.base_ref": assignment_attributes.base_ref,
          "gh.copilot.#{method_name}.request_id": GitHub.context[:request_id],
          "gh.copilot.#{method_name}.agent_id": assignment_attributes.agent_id
        )
      end

      sig { params(actor: User, issue: Issue, assignment_attributes: Issues::AgentAssignmentNewAttributes).returns(T.nilable(Sweagentd::JobsAPI::V1::CreateJobForIssueResponse)) }
      def trigger_copilot_job_twirp_api(actor:, issue:, assignment_attributes:)
        issue_repository = T.must(issue.repository)

        # Use owner_id method which returns T.nilable(Integer) and handle the nil case
        owner_id = issue_repository.owner_id
        if owner_id.nil?
          raise ArgumentError, "Failed to create copilot job: repository owner is nil"
        end

        # Clean custom_agent name if custom agents feature is enabled
        clean_custom_agent = nil
        if FeatureFlag.vexi.enabled?(:copilot_swe_agent_use_subagents, actor, default: false)
          custom_agent = assignment_attributes.custom_agent
          if custom_agent
            custom_agent = custom_agent.strip
            custom_agent = nil if custom_agent.empty?
          end
          clean_custom_agent = custom_agent
        end

        jobs_client = GitHub::Sweagentd::Client.jobs

        create_job_request = Sweagentd::JobsAPI::V1::CreateJobForIssueRequest.new(
          actor_id: actor.id,
          base_branch_name: assignment_attributes.base_ref,
          owner_id: owner_id,
          additional_instructions: assignment_attributes.custom_instructions.to_s,
          repo_id: assignment_attributes.target_repository.id,
          issue_id: issue.id,
          custom_agent: clean_custom_agent.to_s
        )

        # Log if feature flag is enabled
        if FeatureFlag.vexi.enabled?(:issues_copilot_log_capi_request, actor, default: false)
          log_copilot_job_call(
            method_name: "trigger_copilot_job_twirp_api",
            actor: actor,
            issue: issue,
            repository: issue_repository,
            assignment_attributes: assignment_attributes,
            token: nil
          )
        end

        response = Instrumentation.track_time("issues.copilot.create_job_api_call.duration_ms", tags: ["method:twirp_api"]) do
          jobs_client.create_job_for_issue(create_job_request, remote_ip: assignment_attributes.remote_ip)
        end

        GitHub.dogstats.increment("issues.copilot.create_job_api_call.count", tags: ["method:twirp_api", "success:true"])

        response.data
      end

      # Convert twirp-api (Sweagentd) response to hash format compatible with cross-reference creation
      sig do
        params(
          response: T.nilable(
            Sweagentd::JobsAPI::V1::CreateJobForIssueResponse
          )
        ).returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def convert_twirp_api_response_to_hash(response)
        return nil unless response

        result = {
          "id" => response.job_id
        }

        # Add pull_request data if present (for cross-reference creation)
        if response.pull_request_id.present? && response.pull_request_id > 0
          result["pull_request"] = {
            "id" => response.pull_request_id
          }
        end

        result.with_indifferent_access
      end

      sig do
        params(
          assignment_attributes: Issues::AgentAssignmentNewAttributes,
          actor: User,
          issues: T::Array[Issue],
        ).void
      end
      def create_agent_assignment_records(assignment_attributes:, actor:, issues:)
        return unless CopilotFeatureFlagsHelper.issue_cca_visualization_enabled?(actor)

        bot = assignment_attributes.resolve_bot
        return unless bot

        target_repository = assignment_attributes.target_repository

        issues.each do |issue|
          create_agent_assignment_record(actor:, issue:, bot:, target_repository:)
        end
      end

      sig do
        params(
          actor: User,
          bot: User,
          issue: Issue,
          target_repository: Repository,
        ).returns(AgentAssignment)
      end
      def create_agent_assignment_record(actor:, bot:, issue:, target_repository:)
        assignment = AgentAssignment.create(
          source_repository: issue.repository,
          source_type: :issue,
          source_id: issue.id,
          assignee: bot,
          assigner: actor,
          target_repository_id: target_repository.id,
          target_owner_id: target_repository.owner_id,
        )

        unless assignment.persisted?
          report_failbot(
            StandardError.new("Failed to create AgentAssignment: #{assignment.errors.full_messages.join(', ')}"),
            issue: issue,
            context: "create_agent_assignment_record"
          )
        end

        assignment
      end

      sig do
        params(
          assignment_attributes: Issues::AgentAssignmentNewAttributes,
          actor: User,
          issue: Issue,
          response: T.untyped,
        ).void
      end
      def update_agent_assignment_record(assignment_attributes:, actor:, issue:, response:)
        return unless CopilotFeatureFlagsHelper.issue_cca_visualization_enabled?(actor)
        return unless response.is_a?(Hash)

        bot = assignment_attributes.resolve_bot
        task_id = response.dig("task", "id") || response.dig("id")
        unless bot && task_id
          GitHub.dogstats.increment("issues.copilot.update_agent_assignment_record.count", tags: ["success:false"])
          report_failbot(
            StandardError.new("Malformed response from job creation API"),
            issue: issue,
            context: "update_agent_assignment_record"
          )
          return
        end

        target_repository = assignment_attributes.target_repository

        assignment = AgentAssignment.find_by(
          source_repository: issue.repository,
          source_type: :issue,
          source_id: issue.id,
          assignee: bot,
          assigner: actor,
          target_repository_id: target_repository.id,
          target_owner_id: target_repository.owner_id,
          task_id: nil # Only update if task_id is not already set,
        )

        assignment ||= create_agent_assignment_record(actor:, bot:, issue:, target_repository:)

        assignment.update(task_id: task_id)

        if assignment.errors.any?
          GitHub.dogstats.increment("issues.copilot.update_agent_assignment_record.count", tags: ["success:false"])
          report_failbot(
            StandardError.new("Failed to update AgentAssignment: #{assignment.errors.full_messages.join(', ')}"),
            issue: issue,
            context: "update_agent_assignment_record"
          )
        else
          GitHub.dogstats.increment("issues.copilot.update_agent_assignment_record.count", tags: ["success:true"])
        end
      end
    end
  end
end

# rubocop:enable Metrics/MethodLength
