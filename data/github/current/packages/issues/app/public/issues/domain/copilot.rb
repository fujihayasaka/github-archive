# rubocop:disable Metrics/MethodLength
# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class Copilot < GH::Domain::Base
      # Check if the issue is already assigned to the copilot user
      sig { params(issue: Issue, copilot: User, actor: User).returns(T::Boolean) }
      def assigned_to_copilot?(issue, copilot, actor)
        issue.assignees.include?(copilot)
      end

      # Returns true when a non-terminal (pending/active) AgentAssignment already exists
      # for the given issue originating from the given source. Memex auto-assign uses this
      # to avoid spawning a duplicate agent session when one is already in flight for the
      # same issue + workflow action (github/planning-tracking#3129). Terminal assignments
      # (completed/failed/error) are excluded, so a fresh re-trigger proceeds once the prior
      # assignment has finished.
      sig do
        params(
          issue: Issue,
          source_type: Symbol,
          source_id: Integer,
        ).returns(T::Boolean)
      end
      def in_flight_assignment_for_source?(issue:, source_type:, source_id:)
        AgentAssignment.where(
          source_type: source_type,
          source_id: source_id,
          subject_type: :issue,
          subject_id: issue.id,
          subject_repository_id: issue.repository_id,
          status: [:pending, :active],
        ).exists?
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

        # Retry 401 errors by reminting token
        max_retries = 3
        attempt = 0

        begin
          bot = assignment_attributes.resolve_bot
          return unless bot

          Issues.domain.reactions.add_eyes(issue, bot)

          trigger_copilot_job(actor:, issue:, assignment_attributes:, token:)
        rescue CopilotAPI::UnauthorizedError => e
          attempt += 1

          if FeatureFlag.vexi.enabled?(:copilot_assignment_diagnostic_logging, default: false)
            GitHub.logger.info("copilot_job_401_retry_diagnostic",
              "gh.issue.id": issue.id,
              "gh.user.id": actor.id,
              "gh.attempt": attempt,
              "gh.max_retries": max_retries,
              "gh.copilot_api_url": GitHub.copilot_api_internal_url,
              "gh.tenant_slug": GitHub::CurrentTenant.get&.slug,
              "gh.request_id": GitHub.context[:request_id],
            )
          end

          if attempt <= max_retries
            user_session = user_session_id.present? ? UserSession.find_by(id: user_session_id) : nil

            if user_session_id.present? && (user_session.nil? || user_session.user_id != actor.id)
              GitHub.dogstats.increment("issues.copilot.unauthorized_error",
                tags: ["source:ui", "reason:invalid_session"])
              report_failbot(e, issue: issue, context: "copilot_job_retry_failed_invalid_session")
              raise e
            end

            source = user_session_id.present? ? "ui" : "api"
            GitHub.logger.info({
              body: "Retrying Copilot job after 401 error by reminting token",
              issue_id: issue.id,
              actor_id: actor.id,
              user_session_id: user_session_id,
              attempt: attempt,
              max_retries: max_retries,
              source: source
            })

            GitHub.dogstats.increment("issues.copilot.assign",
              tags: ["status:retry", "attempt:#{attempt}", "source:#{source}"])

            token = CopilotSessions::CopilotApiToken.get_encrypted(
              user: actor,
              entry_point: :copilot_job_retry_401,
              user_session: user_session,
              force_cache_miss: true
            )

            retry
          else
            source = user_session_id.present? ? "ui" : "api"
            GitHub.dogstats.increment("issues.copilot.unauthorized_error",
              tags: ["source:#{source}", "reason:max_retries_exceeded"])
            report_failbot(e, issue: issue, context: "copilot_job_retry_failed_max_retries_exceeded")
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

      # Destroys the specific orphaned AgentAssignment record (task_id: nil) that was created
      # for this orchestration before the Copilot job trigger failed.
      # Only targets the exact assignment stored in agent_assignment_ids to avoid destroying
      # assignments from concurrent orchestrations that may still succeed.
      sig do
        params(
          issue: Issue,
          assignment_attributes: Issues::AgentAssignmentNewAttributes,
          actor: User,
          bot: User,
        ).void
      end
      def cleanup_orphaned_agent_assignment(issue:, assignment_attributes:, actor:, bot:)
        return unless FeatureFlag.vexi.enabled?(:issues_cleanup_orphaned_agent_assignments, default: false)

        stored_id = assignment_attributes.agent_assignment_ids[issue.id.to_s]
        unless stored_id
          GitHub.logger.info("cleanup_orphaned_agent_assignment: no stored agent_assignment_id for issue #{issue.id}")
          return
        end

        assignment = AgentAssignment.find_by(id: stored_id, task_id: nil)
        unless assignment
          GitHub.logger.info("cleanup_orphaned_agent_assignment: no orphaned agent_assignment found for id=#{stored_id}, issue=#{issue.id}")
          return
        end

        assignment.destroy
        GitHub.dogstats.increment("issues.copilot.orphaned_agent_assignment_cleaned")
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

        owner = issue_repository.owner
        organization = owner.is_a?(::Organization) ? owner : nil
        use_tasks_api = CopilotFeatureFlagsHelper.issue_cca_visualization_enabled?(actor, organization:)
        staging_env = ::Copilot::User::CopilotApi.resolve_swe_agent_staging_env(user: actor, repository: issue_repository)

        create_pull_request = !assignment_attributes.skip_pull_request

        tags = use_tasks_api ? ["method:mission_control"] : ["method:capi"]
        event_identifiers = ["issue_id::#{issue.id}"]
        omit_issue_number = issue_repository != target_repository &&
          FeatureFlag.vexi.enabled?(:issues_omit_issue_number_event_identifier_for_cross_repo_copilot_assignment, issue_repository, issue_repository.owner, default: false)
        event_identifiers << "issue::#{issue.number}" unless omit_issue_number

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
              staging_env: staging_env,
              async: async,
              num_threads: num_threads,
              request_timeout_s: request_timeout_s,
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

      sig do
        params(
          assignment_attributes: Issues::AgentAssignmentNewAttributes,
          actor: User,
          issues: T::Array[Issue],
        ).void
      end
      def create_agent_assignment_records(assignment_attributes:, actor:, issues:)
        bot = assignment_attributes.resolve_bot
        return unless bot

        target_repository = assignment_attributes.target_repository

        issues.each do |issue|
          owner = issue.repository&.owner
          organization = owner.is_a?(::Organization) ? owner : nil
          next unless CopilotFeatureFlagsHelper.issue_cca_visualization_enabled?(actor, organization:)

          assignment = create_agent_assignment_record(actor:, issue:, bot:, target_repository:, assignment_attributes:)
          if assignment.persisted?
            assignment_attributes.agent_assignment_ids[issue.id.to_s] = assignment.id
          end
        end
      end

      sig do
        params(
          actor: User,
          bot: User,
          issue: Issue,
          target_repository: Repository,
          assignment_attributes: T.nilable(Issues::AgentAssignmentNewAttributes),
        ).returns(AgentAssignment)
      end
      def create_agent_assignment_record(actor:, bot:, issue:, target_repository:, assignment_attributes: nil)
        # Source attribution defaults to the issue itself (source_type: :issue, source_id: issue.id).
        # The default is computed here — rather than required at the caller — because
        # `assignment_attributes` is shared across N issues in the bulk paths
        # (Issues::Domain::Copilot#assign_copilot_to_issues, agent_assignments_controller),
        # so the per-iteration `issue.id` cannot be baked into the struct at construction time.
        # Callers whose source identifier is constant across issues (e.g. a Memex workflow action
        # assigning to a batch of items) set `source_type`/`source_id` on the struct directly;
        # see MemexProjectWorkflowAction::AssignCopilotActionRunner.
        #
        # Guard against partially-set overrides: if exactly one of source_type/source_id is supplied
        # we'd silently fill the other from the issue defaults, producing a logically inconsistent
        # row (e.g. source_type: :workflow_action with source_id pointing at an unrelated issue id).
        if assignment_attributes && assignment_attributes.source_type.nil? != assignment_attributes.source_id.nil?
          raise ArgumentError, "AgentAssignmentNewAttributes#source_type and #source_id must be set together or both left nil"
        end

        source_type = assignment_attributes&.source_type || :issue
        source_id = assignment_attributes&.source_id || issue.id

        assignment = AgentAssignment.create(
          subject_repository: issue.repository,
          source_type: source_type,
          source_id: source_id,
          subject_type: :issue,
          subject_id: issue.id,
          status: :pending,
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

      # Emits the update_agent_assignment_record.count metric with the lookup_path
      # and stored_id_present dimensions so we can tell from prod metrics which
      # branch produced the assignment row. See planning-tracking#2990 for the
      # underlying duplicate-row concern this is observing.
      sig { params(success: T::Boolean, lookup_path: Symbol, stored_id_present: T::Boolean).void }
      def emit_update_agent_assignment_metric(success:, lookup_path:, stored_id_present:)
        GitHub.dogstats.increment(
          "issues.copilot.update_agent_assignment_record.count",
          tags: [
            "success:#{success}",
            "lookup_path:#{lookup_path}",
            "stored_id_present:#{stored_id_present}",
          ],
        )
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
        owner = issue.repository&.owner
        organization = owner.is_a?(::Organization) ? owner : nil
        return unless CopilotFeatureFlagsHelper.issue_cca_visualization_enabled?(actor, organization:)
        return unless response.is_a?(Hash)

        bot = assignment_attributes.resolve_bot
        task_id = response.dig("task", "id") || response.dig("id")
        unless bot && task_id
          emit_update_agent_assignment_metric(success: false, lookup_path: :none, stored_id_present: false)
          report_failbot(
            StandardError.new("Malformed response from job creation API"),
            issue: issue,
            context: "update_agent_assignment_record"
          )
          return
        end

        target_repository = assignment_attributes.target_repository

        stored_id = assignment_attributes.agent_assignment_ids[issue.id.to_s]
        stored_id_present = stored_id.present?

        assignment = AgentAssignment.find_by(id: stored_id, task_id: nil) if stored_id
        lookup_path = assignment ? :stored_id : nil

        type_filter = { subject_type: :issue, subject_id: issue.id }

        assignment ||= AgentAssignment.find_by({
          subject_repository: issue.repository,
          assignee: bot,
          assigner: actor,
          target_repository_id: target_repository.id,
          target_owner_id: target_repository.owner_id,
          task_id: nil,
        }.merge(type_filter))
        lookup_path ||= (:composite_key if assignment)

        assignment ||= create_agent_assignment_record(actor:, bot:, issue:, target_repository:, assignment_attributes:)
        lookup_path ||= :created

        assignment.update(task_id: task_id)

        if assignment.errors.any?
          emit_update_agent_assignment_metric(success: false, lookup_path: lookup_path, stored_id_present: stored_id_present)
          report_failbot(
            StandardError.new("Failed to update AgentAssignment: #{assignment.errors.full_messages.join(', ')}"),
            issue: issue,
            context: "update_agent_assignment_record"
          )
        else
          emit_update_agent_assignment_metric(success: true, lookup_path: lookup_path, stored_id_present: stored_id_present)
        end
      end
    end
  end
end

# rubocop:enable Metrics/MethodLength
