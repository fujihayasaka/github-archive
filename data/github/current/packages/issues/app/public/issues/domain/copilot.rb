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

      # Update the assignees for an issue, called inside Platform::Mutations::ReplaceActorsForAssignable
      sig do
        params(
          actor: User,
          issue: Issue,
          assignees: T::Array[Users::IUser],
          token: ::Copilot::Token,
          remote_ip: T.nilable(String)
        ).returns(GH::Result[IIssue])
      end
      def update_assignees_with_copilot_support(actor:, issue:, assignees:, token:, remote_ip: nil)
        update_attributes = Issues::UpdateIssueAttributes.new(
          assignees: Issues::UpdateIssueAttribute::Set.new(assignees),
        )

        repository = T.must(issue.repository)

        copilot = get_copilot
        previously_assigned_to_copilot = copilot.present? && assigned_to_copilot?(issue, copilot, actor)
        kick_off_copilot_job = copilot.present? && !previously_assigned_to_copilot && assignees.include?(copilot)
        can_set_assignees = Issues.domain.set_assignees?(issue, actor)
        new_agent_entries = T.let([], T::Array[T::Hash[Symbol, T.untyped]])

        if repository.feature_flag_enabled?(:agents_platform_id, default: false)
          enabled_agents = AgenticApp.enabled_for_repository(repository, actor)
          enabled_agent_entries = T.let({}, T::Hash[Integer, T::Hash[Symbol, T.untyped]])
          enabled_agents.each do |agent|
            integration = agent.integration
            next unless integration
            bot = integration.bot
            next unless bot

            enabled_agent_entries[bot.id] = { agent: agent, bot: bot, integration: integration }
          end

          current_assignee_ids = T.let(issue.assignees.map(&:id).compact, T::Array[Integer])
          incoming_assignee_ids = T.let(assignees.map(&:id).compact, T::Array[Integer])
          new_assignee_ids = T.let((incoming_assignee_ids - current_assignee_ids).uniq, T::Array[Integer])
          removed_assignee_ids = T.let((current_assignee_ids - incoming_assignee_ids).uniq, T::Array[Integer])

          new_assignee_ids.each do |assignee_id|
            entry = enabled_agent_entries[assignee_id]
            new_agent_entries << entry if entry
          end
          kick_off_copilot_job = new_agent_entries.any?
          remove_eyes_emoji_reaction(issue: issue, removed_assignee_ids: removed_assignee_ids, actor: actor)
        else
          removing_copilot = copilot.present? && previously_assigned_to_copilot && !assignees.include?(copilot)
          if removing_copilot
            remove_eyes_emoji_reaction(issue: issue, removed_assignee_ids: [copilot.id])
          end
        end

        if kick_off_copilot_job
          unless can_set_assignees
            return GH::Result::Ok.new(issue)
          end

          if !repository.feature_flag_enabled?(:agents_platform_id, default: false)
            # Default case, without the feature flag
            copilot = T.must(copilot)
            assignment_attributes = Issues::AgentAssignmentNewAttributes.new(
              target_repository: repository,
              base_ref: repository.default_branch,
              # No custom instructions are provided when assigning Copilot via the ReplaceActorsForAssignable mutation
              custom_instructions: "",
              remote_ip: remote_ip
            )

            begin
              trigger_copilot_job(actor:, issue:, assignment_attributes:, token:)
              add_eyes_emoji_reaction([issue], copilot)
            rescue StandardError => e
              # If job creation fails, still assign non-Copilot assignees
              non_copilot_assignees = assignees.reject { |a| a == copilot }
              if non_copilot_assignees.any?
                update_attributes = Issues::UpdateIssueAttributes.new(
                  assignees: Issues::UpdateIssueAttribute::Set.new(non_copilot_assignees),
                )
                Issues.domain.update(issue, update_attributes, actor)
              end
              # Re-raise the error for the mutation to handle
              raise e
            end
          else
            triggered_agent_jobs = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
            begin
              new_agent_entries.each do |entry|
                bot = T.cast(entry[:bot], User)
                integration = T.cast(entry[:integration], Integration)
                integration_id = integration.id

                attrs = Issues::AgentAssignmentNewAttributes.new(
                  target_repository: repository,
                  base_ref: repository.default_branch,
                  # No custom instructions are provided when assigning Copilot via the ReplaceActorsForAssignable mutation
                  custom_instructions: "",
                  agent_id: integration_id,
                  remote_ip: remote_ip
                )

                trigger_copilot_job(actor:, issue:, assignment_attributes: attrs, token:)
                add_eyes_emoji_reaction([issue], T.cast(entry[:bot], User))
                triggered_agent_jobs << { bot: bot, assignment_attributes: attrs }
              end
            rescue StandardError => job_error
              non_agent_assignees = assignees.reject do |assignee|
                assignee_id = assignee.id
                assignee_id && new_agent_entries.any? { |entry| T.cast(entry[:bot], User).id == assignee_id }
              end

              if non_agent_assignees.any?
                fallback_update_attributes = Issues::UpdateIssueAttributes.new(
                  assignees: Issues::UpdateIssueAttribute::Set.new(non_agent_assignees),
                )
                Issues.domain.update(issue, fallback_update_attributes, actor)
              end

              raise job_error
            end
          end
          # Persist assignee changes after successful job call
          Issues.domain.update(issue, update_attributes, actor)
        else
          # Default path: persist updates (either no job needed, or no session)
          Issues.domain.update(issue, update_attributes, actor)
        end
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
          # When agents_platform_id is enabled and agent_id is provided, use the agent's bot for the eyes reaction
          # Falls back to Copilot behavior if agent lookup fails
          if repository.feature_flag_enabled?(:agents_platform_id, default: false) && assignment_attributes.agent_id.present?
            agent = AgenticApp.agent_for_integration_id(assignment_attributes.agent_id)
            agent_bot = agent&.integration&.bot
            if agent_bot
              add_eyes_emoji_reaction([issue], agent_bot)
              trigger_copilot_job(actor:, issue:, assignment_attributes:, token:)
              return
            end
            # Fall through to Copilot behavior if agent lookup fails
          end
          # Default Copilot-only behavior (or fallback when agent lookup fails)
          copilot = get_copilot
          if copilot.present?
            add_eyes_emoji_reaction([issue], copilot)
            trigger_copilot_job(actor:, issue:, assignment_attributes:, token:)
          end
        rescue CopilotAPI::UnauthorizedError => e
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
      # copilot assignments via add_copilot_to_assignees or bulk_async_add_copilot_to_assignees.
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
        use_orchestration = FeatureFlag.vexi.enabled?(:issues_use_orchestration_for_copilot, actor, default: false)

        if use_orchestration
          assignment_results = queue_agent_orchestration(
            actor: actor,
            issues: issues,
            assignment_attributes: assignment_attributes,
            token: token,
            user_session_id: user_session_id
          )
        else
          assignment_results = if use_async && issues.size > 1
            bulk_async_add_copilot_to_assignees(actor:, issues:, assignment_attributes:, token:)
          else
            results = {
              successful_issues: T.let([], T::Array[Issue]),
              exceptions: T.let([], T::Array[StandardError])
            }
            issues.each do |issue|
              begin
                assignment = add_copilot_to_assignees(
                  actor: actor,
                  issue: issue,
                  assignment_attributes: assignment_attributes,
                  token: token
                )
                results[:successful_issues] << issue if assignment.ok?
              rescue StandardError => e
                results[:exceptions] << e
              end
            end
            results
          end
        end

        unless use_orchestration # Orchestration handles the metrics for all mutations, no need to double count
          cross_repo = issues.any? do |issue|
            repo = issue.repository
            repo && repo.name_with_display_owner != assignment_attributes.target_repository.name_with_display_owner
          end
          custom_instructions_present = assignment_attributes.custom_instructions.to_s.strip.present?
          non_default_branch = assignment_attributes.base_ref != assignment_attributes.target_repository.default_branch
          custom_agent_used = assignment_attributes.custom_agent.to_s.strip.present?

          record_assignment_metrics(
            assignment_results: assignment_results,
            async: use_async && issues.size > 1,
            cross_repo: cross_repo,
            custom_instructions: custom_instructions_present,
            non_default_branch: non_default_branch,
            custom_agent: custom_agent_used
          )
        end

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
        bot_to_assign = if repository.feature_flag_enabled?(:agents_platform_id, default: false) && assignment_attributes.agent_id.present?
          agent = AgenticApp.agent_for_integration_id(assignment_attributes.agent_id)
          agent&.integration&.bot
        else
          get_copilot
        end

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

            Issues.domain.update(issue_with_assignees, update_attributes, actor, copilot_context: copilot_context)

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

        if T.must(issue.repository).feature_flag_enabled?(:agents_platform_id, default: false)
          agent_bot_ids_to_remove = T.let([], T::Array[Integer])
          removed_assignee_ids.each do |assignee_id|
            agent = AgenticApp.agent_for_bot_id(assignee_id)
            agent_bot_ids_to_remove << assignee_id if agent
          end
          reactions = IssueReaction.where(issue_id: issue.id, user_id: agent_bot_ids_to_remove, content: "eyes")
          return if reactions.empty?
        else
          copilot_bot = get_copilot
          return unless copilot_bot && removed_assignee_ids.include?(copilot_bot.id)
          reactions = IssueReaction.where(issue_id: issue.id, user_id: copilot_bot.id, content: "eyes")
          return if reactions.empty?
        end
        deleted = reactions.delete_all

        if deleted > 0
          IssueReaction.notify_subject_subscribers(issue)
          GitHub.dogstats.increment("reaction", tags: ["action:destroy", "type:eyes"], by: deleted)
        end
      rescue StandardError => e
        report_failbot(e, issue: issue, context: "copilot_reaction_removal")
      end

      private

      # Uses CAPI's async parameter to make concurrent requests.
      sig do
        params(
          actor: User,
          issues: T::Array[Issue],
          assignment_attributes: Issues::AgentAssignmentNewAttributes,
          token: ::Copilot::Token,
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def bulk_async_add_copilot_to_assignees(actor:, issues:, assignment_attributes:, token:)
        assignment_results = {
          successful_issues: T.let([], T::Array[Issue]),
          exceptions: T.let([], T::Array[StandardError])
        }

        copilot = get_copilot
        unless copilot
          assignment_results[:exceptions] << CopilotAPI::NotFoundError.new("Copilot not found for user #{actor.id}")
          return assignment_results
        end

        eligible_issues = []
        issues.each do |issue|
          next if issue.assigned_to?(copilot)
          if Issues.domain.set_assignees?(issue, actor)
            eligible_issues << issue
          else
            assignment_results[:exceptions] << CopilotAPI::UnauthorizedError.new("Failed to assign copilot to issue ##{issue.number}: Assignees validation failed")
          end
        end

        futures = eligible_issues.map do |issue|
          begin
            fut = Promise.resolve(trigger_copilot_job(
              actor: actor,
              issue: issue,
              assignment_attributes: assignment_attributes,
              token: token,
              async: true,
              num_threads: CopilotAPI::MAX_CONCURRENCY
            ))
            { issue: issue, future: fut }
          rescue StandardError => e
            report_failbot(e, issue: issue, context: "async_future_creation")
            { issue: issue, future: Promise.resolve(e) }
          end
        end

        futures.each do |entry|
          issue = entry[:issue]
          result = begin
            entry[:future].respond_to?(:sync) ? entry[:future].sync : entry[:future]
          rescue StandardError => e
            report_failbot(e, issue: issue, context: "async_future_sync")
            e
          end

          if result.is_a?(Exception)
            assignment_results[:exceptions] << result
            next
          end

          unless result.is_a?(ActiveSupport::HashWithIndifferentAccess) || result.is_a?(Hash)
            assignment_results[:exceptions] << ArgumentError.new("Failed to create job for issue ##{issue.number}: unexpected response (got #{result.class})")
            next
          end

          update_attributes = Issues::UpdateIssueAttributes.new(
            assignees: Issues::UpdateIssueAttribute::Set.new((issue.assignees + [copilot]).uniq),
          )
          assignment = Issues.domain.update(issue, update_attributes, actor)

          if assignment.is_a?(GH::Result::Ok)
            assignment_results[:successful_issues] << issue
          else
            assignment_results[:exceptions] << StandardError.new("Failed to update assignees for issue ##{issue.number}: #{assignment.error&.message}")
          end
        end

        if assignment_results[:successful_issues].any?
          add_eyes_emoji_reaction(assignment_results[:successful_issues], copilot)
        end

        assignment_results
      end

      # Add copilot to the assigned users
      sig do params(
        actor: User,
        issue: Issue,
        assignment_attributes: Issues::AgentAssignmentNewAttributes,
        token: ::Copilot::Token
      ).returns(GH::Result[IIssue])
      end
      def add_copilot_to_assignees(actor:, issue:, assignment_attributes:, token:)
        copilot = get_copilot
        unless copilot
          raise CopilotAPI::NotFoundError, "Copilot not found for user #{actor.id}"
        end
        if assigned_to_copilot?(issue, copilot, actor)
          return GH::Result::Error::Argument.new("Issue is already assigned to copilot")
        end

        update_attributes = Issues::UpdateIssueAttributes.new(
          assignees: Issues::UpdateIssueAttribute::Set.new((issue.assignees + [copilot]).uniq),
        )

        # First validate whether domain would set assignees - if not, skip job creation
        can_set_assignees = Issues.domain.set_assignees?(issue, actor)
        unless can_set_assignees
          raise CopilotAPI::UnauthorizedError, "Assignees update failed"
        end

        # Call the Jobs API first; if it fails, do not change assignees
        # Choose between capi (old CopilotAPI) and twirp-api (new Sweagentd client) based on feature flag
        issue_repository = T.must(issue.repository)
        if FeatureFlag.vexi.enabled?(:issues_copilot_use_twirp_api, actor, issue_repository, issue_repository.owner, default: false)
          response = trigger_copilot_job_twirp_api(actor: actor, issue: issue, assignment_attributes: assignment_attributes)
          # Convert twirp-api response to hash format for cross-reference compatibility
          response_hash = convert_twirp_api_response_to_hash(response) if response
        else
          response = trigger_copilot_job(actor:, issue:, assignment_attributes:, token:)
        end
        add_eyes_emoji_reaction([issue], copilot)

        # Persist assignee change only after job creation succeeds
        assignment = Issues.domain.update(issue, update_attributes, actor)

        unless assignment.is_a?(GH::Result::Ok)
          raise StandardError, "Failed to update assignees: #{assignment.error&.message}"
        end

        assignment
      end

      # Adds an eyes emoji reaction (👀) from the provided actor to all given issues.
      sig { params(issues: T::Array[Issue], actor: User).void }
      def add_eyes_emoji_reaction(issues, actor)
        return if issues.empty?

        eyes_emotion = Emotion.find_by_label("eyes")
        return unless eyes_emotion

        current_time = Time.current
        reaction_attributes = issues.map do |issue|
          {
            "content" => eyes_emotion.content,
            "issue_id" => issue.id,
            "user_id" => actor.id,
            "repository_id" => issue.repository_id,
            "user_hidden" => false,
            "created_at" => current_time,
            "updated_at" => current_time
          }
        end

        result = IssueReaction.insert_all(reaction_attributes) unless reaction_attributes.empty?
        rows_inserted = result&.length || 0

        issues.each do |issue|
          IssueReaction.notify_subject_subscribers(issue)
        end

        if rows_inserted > 0
          GitHub.dogstats.increment("reaction", tags: ["action:create", "type:#{eyes_emotion.content}"], by: rows_inserted)
        end
      end

      # Emits minimal success/failure metrics.
      sig do
        params(
          assignment_results: T::Hash[Symbol, T.untyped],
          async: T::Boolean,
          cross_repo: T::Boolean,
          custom_instructions: T::Boolean,
          non_default_branch: T::Boolean,
          custom_agent: T::Boolean,
        ).void
      end
      def record_assignment_metrics(assignment_results:, async:, cross_repo:, custom_instructions:, non_default_branch:, custom_agent:)
        base_tags = [
          "async:#{async}",
          "cross_repo:#{cross_repo}",
          "custom_instructions:#{custom_instructions}",
          "non_default_branch:#{non_default_branch}",
          "custom_agent:#{custom_agent}"
        ]

        success_count = assignment_results[:successful_issues].length
        GitHub.dogstats.increment("issues.copilot.assign", by: success_count, tags: base_tags + ["status:success"]) if success_count > 0

        exceptions = assignment_results[:exceptions] || []
        failures = Hash.new(0)

        exceptions.each do |exception|
          reason = case exception
          when CopilotAPI::RAIError, CopilotAPI::EntityTooLargeError, CopilotAPI::RequestError
            "unprocessable"
          when CopilotAPI::RateLimitError
            "rate_limit"
          when CopilotAPI::UnauthorizedError, GitHub::Sweagentd::Client::Jobs::UnauthorizedError
            "unauthorized"
          when CopilotAPI::NotFoundError
            "not_found"
          when CopilotAPI::NetworkError, GitHub::Sweagentd::Client::Jobs::NetworkError
            "network"
          when ArgumentError
            "argument"
          else
            if CopilotSweAgentJobHelper.timeout_error?(exception)
              "timeout"
            else
              "internal"
            end
          end
          failures[reason] += 1
        end

        failures.each do |reason, count|
          next if count.zero?
          GitHub.dogstats.increment(
            "issues.copilot.assign",
            by: count,
            tags: base_tags + ["status:failure", "reason:#{reason}"]
          )
        end
      rescue StandardError => e
        GitHub.logger.error(
          "[Copilot-Assign] Metrics emission failed",
          error: e.message,
          backtrace: e.backtrace
        )
      end
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
          target_repository: effective_target_repository
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

        response = Instrumentation.track_time("issues.copilot.create_job_api_call.duration_ms", tags: ["method:capi"]) do
          api.create_swe_agent_job(
            nwo: target_repository.name_with_display_owner,
            problem_statement: problem_statement,
            content_filter_mode: ::Copilot::User::CopilotApi::ContentFilterMode::Markdown,
            pull_request_data: pull_request_data,
            base_ref: assignment_attributes.base_ref,
            creation_id: creation_id,
            event_type: event_type,
            event_identifiers: ["issue::#{issue.number}"],
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
            model: model_param
          )
        end

        GitHub.dogstats.increment("issues.copilot.create_job_api_call.count", tags: ["method:capi", "success:true"])

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
    end
  end
end

# rubocop:enable Metrics/MethodLength
