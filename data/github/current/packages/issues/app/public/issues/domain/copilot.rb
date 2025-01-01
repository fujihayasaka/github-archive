# rubocop:disable Metrics/MethodLength
# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class Copilot < GH::Domain::Base
      # added this because the default read timeout is 60s in concurrent calls, we expect around 4s
      # per assignment so 8s should be enough
      PER_REQUEST_TIMEOUT_S = 8.0

      # Check if the issue is already assigned to the copilot user
      sig { params(issue: Issue, copilot: User, actor: User).returns(T::Boolean) }
      def assigned_to_copilot?(issue, copilot, actor)
        if FeatureFlag.vexi.enabled?(:issues_copilot_assignees_check_fix, actor, default: false)
          @_assigned_to_copilot ||= T.let(Hash.new do |hash, key|
            hash[key] = issue.assignees.include?(key)
          end, T.nilable(T::Hash[User, T::Boolean]))
          @_assigned_to_copilot[copilot]
        else
          issue.assigned_to?(copilot)
        end
      end

      # Update the assignees for an issue, called inside Platform::Mutations::ReplaceActorsForAssignable
      sig do
        params(
          actor: User,
          issue: Issue,
          assignees: T::Array[Users::IUser],
          token: ::Copilot::DecryptedToken
        ).returns(GH::Result[IIssue])
      end
      def update_assignees_with_copilot_support(actor:, issue:, assignees:, token:)
        update_attributes = Issues::UpdateIssueAttributes.new(
          assignees: assignees,
        )

        copilot = get_copilot(actor, nil)
        previously_assigned_to_copilot = copilot.present? && assigned_to_copilot?(issue, copilot, actor)
        kick_off_copilot_job = copilot.present? && !previously_assigned_to_copilot && assignees.include?(copilot)
        can_set_assignees = Issues.domain.set_assignees?(issue, actor)

        if kick_off_copilot_job
          unless can_set_assignees
            return GH::Result::Ok.new(issue)
          end

          # Trigger the job first and only then persist
          repository = T.must(issue.repository)
          assignment_attributes = Issues::AgentAssignmentNewAttributes.new(
            issue_ids: [issue.id],
            repo_name_with_owner: repository.name_with_display_owner,
            base_ref: repository.default_branch,
            # No custom instructions are provided when assigning Copilot via the ReplaceActorsForAssignable mutation
            custom_instructions: ""
          )

          begin
            response = trigger_copilot_job(actor:, issue:, assignment_attributes:, token:)
            add_eyes_emoji_reaction([issue], copilot)
            create_cross_reference_if_needed(actor: actor, issue: issue, response: response, copilot: copilot)
          rescue CopilotAPI::NetworkError => e
            return GH::Result::Error::ServiceUnreachable.new("Failed to trigger Copilot job: #{e.message}")
          end

          # Persist assignee changes after successful job call
          return Issues.domain.update(issue, update_attributes, actor)
        end

        # Default path: persist updates (either no job needed, or no session)
        Issues.domain.update(issue, update_attributes, actor)
      end

      # Triggers Copilot after an issue is created
      sig { params(actor: User, issue: Issue, repository: Repository, user_session: T.nilable(UserSession)).returns(GH::Result[T::Boolean]) }
      def trigger_copilot_job_for_new_issue(actor:, issue:, repository:, user_session:)
        copilot = get_copilot(actor, user_session)

        if copilot.present?
          assignment_attributes = Issues::AgentAssignmentNewAttributes.new(
            issue_ids: [issue.id],
            repo_name_with_owner: repository.name_with_display_owner,
            base_ref: repository.default_branch,
            # No custom instructions are provided when assigning Copilot in this case
            # because we don't show the cross-repo assignment modal during issue creation
            custom_instructions: ""
          )

          begin
            response = trigger_copilot_job(actor: actor, issue: issue, assignment_attributes: assignment_attributes, user_session: user_session)
            add_eyes_emoji_reaction([issue], copilot)
            create_cross_reference_if_needed(actor: actor, issue: issue, response: response, copilot: copilot)
          rescue CopilotAPI::NetworkError => e
            return GH::Result::Error::ServiceUnreachable.new("Failed to trigger copilot job: #{e.message}")
          end
        end

        GH::Result::Ok.new(true)
      end

      # Domain method: Asynchronously trigger a Copilot SWE agent job for an issue.
      # Wraps the synchronous trigger in a Promise so callers can compose / batch
      # without blocking.
      #
      # Params:
      # - actor: User initiating the assignment
      # - issue: Issue to create the Copilot job for
      # - assignment_attributes: Cross-repo assignment attributes (repository, base ref, custom instructions)
      # - user_session: Optional session used to obtain scoped API credentials
      # - request_timeout_s: Optional per-request timeout (seconds) passed to downstream API
      # - num_threads: Optional number of threads to use for the async calls (defaults to 10)
      # Returns: Promise resolving to the API response hash (with indifferent access) OR an Exception instance.
      sig { params(actor: User, issue: Issue, assignment_attributes: Issues::AgentAssignmentNewAttributes, user_session: T.nilable(UserSession), request_timeout_s: T.nilable(Float)).returns(T.untyped) }
      def async_trigger_copilot_job(actor:, issue:, assignment_attributes:, user_session:, request_timeout_s: nil)
        Promise.resolve(
          trigger_copilot_job(
            actor: actor,
            issue: issue,
            assignment_attributes: assignment_attributes,
            user_session: user_session,
            async: true,
            request_timeout_s: request_timeout_s,
            num_threads: CopilotAPI::MAX_CONCURRENCY
          )
        )
      rescue StandardError => e
        Promise.resolve(e)
      end

      # High-level domain entrypoint used by the controller to perform one or many
      # copilot assignments via add_copilot_to_assignees or bulk_async_add_copilot_to_assignees.
      # Returns the full assignment_results hash plus a :jobs entry consumed by the controller.
      sig do
        params(
          actor: User,
          issues: T::Array[Issue],
          assignment_attributes: Issues::AgentAssignmentNewAttributes,
          user_session: T.nilable(UserSession),
          use_async: T::Boolean
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def assign_copilot_to_issues(actor:, issues:, assignment_attributes:, user_session:, use_async:)
        assignment_results = if use_async && issues.size > 1
          bulk_async_add_copilot_to_assignees(
            actor: actor,
            issues: issues,
            assignment_attributes: assignment_attributes,
            user_session: user_session
          )
        else
          results = {
            successful_issues: T.let([], T::Array[Issue]),
            save_assignees_errors: T.let([], T::Array[String]),
            job_creation_errors: T.let([], T::Array[String]),
            any_request_timed_out: T.let(false, T::Boolean),
            internal_errors: T.let([], T::Array[String])
          }
          issues.each do |issue|
            assignment = add_copilot_to_assignees(
              actor: actor,
              issue: issue,
              assignment_attributes: assignment_attributes,
              user_session: T.cast(user_session, UserSession)
            )
            apply_assignment_outcome!(assignment_results: results, assignment: assignment, issue: issue)
          end
          results
        end

        jobs = assignment_results[:successful_issues].map { |issue| { issue_number: issue.number } }
        assignment_results.merge(jobs: jobs)
      end

      private

      # Uses CAPI's async parameter to make concurrent requests.
      sig do
        params(
          actor: User,
          issues: T::Array[Issue],
          assignment_attributes: Issues::AgentAssignmentNewAttributes,
          user_session: T.nilable(UserSession)
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def bulk_async_add_copilot_to_assignees(actor:, issues:, assignment_attributes:, user_session:)
        assignment_results = {
          successful_issues: T.let([], T::Array[Issue]),
          save_assignees_errors: T.let([], T::Array[String]),
          job_creation_errors: T.let([], T::Array[String]),
          any_request_timed_out: T.let(false, T::Boolean),
          internal_errors: T.let([], T::Array[String])
        }

        copilot = get_copilot(actor, user_session)
        unless copilot
          assignment_results[:internal_errors] << "Copilot not found for user #{actor.id}"
          return assignment_results
        end

        eligible_issues = []
        issues.each do |issue|
          next if issue.assigned_to?(copilot)
          if Issues.domain.set_assignees?(issue, actor)
            eligible_issues << issue
          else
            assignment_results[:save_assignees_errors] << "Failed to assign copilot to issue ##{issue.number}: Assignees update failed"
          end
        end

        futures = eligible_issues.map do |issue|
          begin
            fut = async_trigger_copilot_job(
              actor: actor,
              issue: issue,
              assignment_attributes: assignment_attributes,
              user_session: user_session,
              request_timeout_s: PER_REQUEST_TIMEOUT_S
            )
            { issue: issue, future: fut }
          rescue StandardError => e
            { issue: issue, future: Promise.resolve(e) }
          end
        end

        futures.each do |entry|
          issue = entry[:issue]
          result = begin
            entry[:future].respond_to?(:sync) ? entry[:future].sync : entry[:future]
          rescue StandardError => e
            e
          end

          if result.is_a?(Exception)
            assignment_results[:any_request_timed_out] = true if CopilotSweAgentJobHelper.timeout_error?(result)
            if CopilotSweAgentJobHelper.timeout_error?(result)
              assignment_results[:any_request_timed_out] = true
            elsif result.is_a?(CopilotAPI::RequestError) || result.is_a?(CopilotAPI::RAIError) || result.is_a?(CopilotAPI::EntityTooLargeError)
              assignment_results[:job_creation_errors] << "Failed to create job for issue ##{issue.number}: #{result.message}"
            else
              assignment_results[:internal_errors] << "Failed to create job for issue ##{issue.number}: #{result.message}"
            end
            next
          end

          if result.is_a?(ActiveSupport::HashWithIndifferentAccess) || result.is_a?(Hash)
            result = result.with_indifferent_access if result.is_a?(Hash)
            begin
              create_cross_reference_if_needed(actor: actor, issue: issue, response: result, copilot: copilot)
            rescue StandardError => e
              GitHub.logger.error(
                "[Copilot-Assign] Async cross-reference attempt failed",
                issue_id: issue.id,
                error: e.message
              )
            end
          else
            assignment_results[:internal_errors] << "Failed to create job for issue ##{issue.number}: unexpected response"
            next
          end

          update_attributes = Issues::UpdateIssueAttributes.new(
            assignees: (issue.assignees + [copilot]).uniq,
          )
          assignment = Issues.domain.update(issue, update_attributes, actor)
          apply_assignment_outcome!(assignment_results: assignment_results, assignment: assignment, issue: issue)
        end

        if assignment_results[:successful_issues].any?
          add_eyes_emoji_reaction(assignment_results[:successful_issues], copilot)
        end

        assignment_results
      end

      # Add copilot to the assigned users
      sig { params(actor: User, issue: Issue, assignment_attributes: Issues::AgentAssignmentNewAttributes, user_session: UserSession).returns(GH::Result[IIssue]) }
      def add_copilot_to_assignees(actor:, issue:, assignment_attributes:, user_session:)
        copilot = get_copilot(actor, user_session)
        unless copilot
          return GH::Result::Error::NotFound.new("Copilot not found for user #{actor.id}")
        end
        if assigned_to_copilot?(issue, copilot, actor)
          return GH::Result::Error::Argument.new("Issue is already assigned to copilot")
        end

        update_attributes = Issues::UpdateIssueAttributes.new(
          assignees: (issue.assignees + [copilot]).uniq,
        )

        # First validate whether domain would set assignees - if not, skip job creation
        can_set_assignees = Issues.domain.set_assignees?(issue, actor)
        unless can_set_assignees
          return GH::Result::Error::NotSaved.new("Assignees update failed")
        end

        # Call the Jobs API first; if it fails, do not change assignees
        begin
          response = trigger_copilot_job(actor: actor, issue: issue, assignment_attributes: assignment_attributes, user_session: user_session)
          add_eyes_emoji_reaction([issue], copilot)
          create_cross_reference_if_needed(actor: actor, issue: issue, response: response, copilot: copilot)
        rescue CopilotAPI::NetworkError => e
          return GH::Result::Error::ServiceUnreachable.new("Failed to trigger copilot job: #{e.message}")
        end

        # Persist assignee change only after job creation succeeds
        Issues.domain.update(issue, update_attributes, actor)
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

      # Side-effect helper used by both the bulk async path and the controller's synchronous loop.
      sig do
        params(
          assignment_results: T::Hash[Symbol, T.untyped],
          assignment: GH::Result[IIssue],
          issue: Issue
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def apply_assignment_outcome!(assignment_results:, assignment:, issue:)
        case assignment
        when GH::Result::Ok
          assignment_results[:successful_issues] << issue
        when GH::Result::Error::Argument
          # already assigned – ignore
        when GH::Result::Error::ServiceUnreachable
          assignment_results[:internal_errors] << "Failed to create job for issue ##{issue.number}: #{assignment.message}"
        when GH::Result::Error::Unprocessable
          assignment_results[:job_creation_errors] << "Failed to create job for issue ##{issue.number}: #{assignment.message}"
        when GH::Result::Error::NotSaved
          assignment_results[:save_assignees_errors] << "Failed to assign copilot to issue ##{issue.number}: #{assignment.message}"
        end
        assignment_results
      end

      # If a token is supplied then a new token will _not_ be minted, instead the provided token will be used.
      # If a token is not supplied then a new token will be minted using the active and user_session (if provided).
      sig do
        params(
          actor: User,
          user_session: T.nilable(UserSession),
          token: T.nilable(::Copilot::DecryptedToken)
        ).returns(::Copilot::User::CopilotApi)
      end
      def get_copilot_api(actor, user_session, token = nil)
        if token.nil?
          token = CopilotSweAgent::CopilotApiToken.get_encrypted(
            user: actor,
            entry_point: :agent_assignments_controller_create,
            user_session:
          )
        end

        actor.copilot_api(integration_id: CopilotAPI::COPILOT_SWE_AGENT, token:)
      end

      sig { params(actor: User, user_session: T.nilable(UserSession)).returns(T.nilable(Bot)) }
      def get_copilot(actor, user_session)
        app = T.let(Apps::Privileged.integration(:copilot_swe_agent), T.nilable(Integration))
        app&.bot
      end

      sig do
        params(
          actor: User,
          issue: Issue,
          assignment_attributes: Issues::AgentAssignmentNewAttributes,
          user_session: T.nilable(UserSession),
          async: T::Boolean,
          num_threads: Integer,
          request_timeout_s: T.nilable(Float),
          token: T.nilable(::Copilot::DecryptedToken)
        ).returns(T.untyped)
      end
      def trigger_copilot_job(actor:, issue:, assignment_attributes:, user_session: nil, async: false, num_threads: 1, request_timeout_s: nil, token: nil)
        api = get_copilot_api(actor, user_session, token)

        creation_id = SecureRandom.uuid
        event_type = "issues_agent_assignment"

        # Parse target repository from assignment attributes for cross-repo assignments
        repo_parts = assignment_attributes.repo_name_with_owner.split("/", 2)
        if repo_parts.length != 2 || repo_parts.any?(&:empty?)
          raise ArgumentError, "Invalid repo_name_with_owner format: '#{assignment_attributes.repo_name_with_owner}'"
        end
        owner_login, repo_name = repo_parts
        target_owner = User.find_by_login(owner_login)
        target_repository = target_owner&.find_repo_by_name(repo_name)

        # Only pass target_repository to the helper if it's different from the issue's repository
        issue_repository = T.must(issue.repository)
        effective_target_repository = nil
        if target_repository && target_repository != issue_repository
          effective_target_repository = target_repository
        end

        problem_statement = CopilotSweAgentJobHelper.generate_issue_problem_statement(
          issue: issue,
          agent_instructions: assignment_attributes.custom_instructions,
          target_repository: effective_target_repository
        )
        pr_body_placeholder, pr_body_suffix = CopilotSweAgentJobHelper.generate_pr_body(issue: issue, agent_instructions: assignment_attributes.custom_instructions)
        # Same as in sweagentd
        # See https://github.com/github/sweagentd/blob/73c9ba380646ac27b94c21b07073fee64fbeb0ff/internal/events/on_issue_assigned.go#L195
        pr_title = issue.title

        # Determine API version - use v0 for cross-repository assignments when cross-reference FF enabled
        cross_ref_enabled = FeatureFlag.vexi.enabled?(:issues_copilot_create_cross_references, actor, default: false)
        is_cross_repo = issue_repository.name_with_display_owner != assignment_attributes.repo_name_with_owner
        use_v0_api = cross_ref_enabled && is_cross_repo
        api_version = if use_v0_api
          "v0"
        else
          FeatureFlag.vexi.enabled?(:issues_copilot_sweagent_jobs_v1, actor, issue_repository, issue_repository.owner, default: false) ? "v1" : nil
        end

        response = api.create_swe_agent_job(
          nwo: assignment_attributes.repo_name_with_owner,
          problem_statement: problem_statement,
          content_filter_mode: ::Copilot::User::CopilotApi::ContentFilterMode::Markdown,
          pull_request_data: {
            title: pr_title,
            body_placeholder: pr_body_placeholder,
            body_suffix: pr_body_suffix
          },
          base_ref: assignment_attributes.base_ref,
          creation_id: creation_id,
          event_type: event_type,
          api_version: api_version,
          use_staging: FeatureFlag.vexi.enabled?(:sweagentd_route_user_or_repo_to_staging, actor, issue_repository, issue_repository.owner, default: false),
          async: async,
          num_threads: num_threads,
          request_timeout_s: request_timeout_s,
          use_staging_sith_lord: FeatureFlag.vexi.enabled?(:sweagentd_route_user_or_repo_to_staging_sith_lord, actor, issue_repository, issue_repository.owner, default: false),
          use_staging_jedi_knight: FeatureFlag.vexi.enabled?(:sweagentd_route_user_or_repo_to_staging_jedi_knight, actor, issue_repository, issue_repository.owner, default: false),
        )
        response
      end

      # Handles cross-reference creation if enabled and response contains PR data.
      # Guard: response may be a FutureResponse (async path) – only proceed if it's a Hash.
      sig { params(actor: User, issue: Issue, response: T.untyped, copilot: User).void }
      def create_cross_reference_if_needed(actor:, issue:, response:, copilot:)
        unless response.nil? || response.is_a?(Hash)
          return
        end

        response_hash = T.let(response, T.nilable(T::Hash[String, T.untyped]))
        should_create_cross_ref = FeatureFlag.vexi.enabled?(:issues_copilot_create_cross_references, actor, default: false)

        if should_create_cross_ref && response_hash && response_hash["pull_request"].present?
          GitHub.logger.info(
            "[Copilot-Assign] Creating cross reference from PR data",
            issue_id: issue.id,
            pr_data: response_hash["pull_request"].inspect,
            actor_id: actor.id
          )
          create_cross_reference_from_pr_data(
            issue: issue,
            pr_data: response_hash["pull_request"],
            actor: actor,
            copilot: copilot
          )
        else
          GitHub.logger.info(
            "[Copilot-Assign] Skipping cross-reference creation - feature flag disabled or no PR data",
            issue_id: issue.id,
            actor_id: actor.id,
            should_create_cross_ref: should_create_cross_ref,
            has_pr_data: !!(response_hash && response_hash["pull_request"].present?)
          )
        end
      end

      sig { params(issue: IIssue, pr_data: T::Hash[String, T.untyped], actor: User, copilot: User).void }
      def create_cross_reference_from_pr_data(issue:, pr_data:, actor:, copilot:)
        pr_id = pr_data["id"]
        unless pr_id
          GitHub.logger.warn("[Copilot-Assign] PR data missing id", pr_data: pr_data)
          return
        end

        # Always fetch the PR from the DB to get repository_id without depending on PullRequests package
        pr_issue = Issue.find_by(pull_request_id: pr_id)
        unless pr_issue
          GitHub.logger.warn("[Copilot-Assign] Could not find PR issue", pr_id: pr_id)
          return
        end

        issue.record_reference_from(pr_issue, copilot, Time.current)
      rescue => error
        GitHub.logger.error(
          "[Copilot-Assign] Failed to create cross-reference",
          issue_id: issue.id,
          error: error.message
        )
      end
    end
  end
end

# rubocop:enable Metrics/MethodLength
