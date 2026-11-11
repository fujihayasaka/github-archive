# typed: strict
# frozen_string_literal: true

# Helper methods for creating Copilot SWE Agent job
# Based on https://github.com/github/sweagentd/blob/main/internal/problemstatement/issue.go
# Used by Issues::Domain::Copilot#trigger_copilot_job for assigning Copilot across different repos
#
# This helper filters comments in the problem statement to exclude:
# - Minimized/hidden comments
# - Comments from users without write access to the target repository
# This matches the filtering behavior implemented in sweagentd for security and content quality.
module CopilotSweAgentJobHelper
  # Constants for limits and formatting
  MAX_TRUNCATED_COMMENT_BODY_LENGTH = 2000
  MAX_PROBLEM_STATEMENT_BASE64_LENGTH = 40_000 # ~30,000 characters
  SECTION_SEPARATOR = "----\n"
  ISSUE_SECTION_HEADER = "*This section details on the original issue you should resolve*"
  ISSUE_COMMENTS_HEADING = "## Comments on the Issue (you are @%{agent_mention_slug} in this section)\n"
  TIMEOUT_ERROR_CLASSES = [::Timeout::Error, Faraday::TimeoutError, GitHub::TimeoutMiddleware::RequestTimeout, GitHub::RequestDurationManager::TimeBudgetIsOverError].freeze
  TIMEOUT_ERROR_PATTERNS = /execution expired|Net::ReadTimeout|Faraday::Timeout/i
  GENERIC_ERROR_COMMENT = "Please try again later, or contact support if the problem persists."

  # Main entry point
  #
  # Params:
  # - issue:   an Issue object
  # - agent_instructions: optional instruction for the agent/subagent
  # - target_repository: optional target repository for checking write access (defaults to issue's repository)
  #
  # Returns: Hash with :statement (String) and :truncation_info (Hash)
  sig do
    params(
      issue: Issue,
      agent_instructions: T.nilable(String),
      target_repository: T.nilable(Repository),
      agent_mention_slug: T.nilable(String)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.generate_issue_problem_statement(issue:, agent_instructions: nil, target_repository: nil, agent_mention_slug: nil)
    # Filter comments to exclude minimized comments and comments from users without write access
    all_comments = issue.comments.sort_by(&:created_at)
    repository = target_repository || T.must(issue.repository)
    comments = filter_comments_for_problem_statement(all_comments, repository)

    # Track truncation for metrics
    truncation_info = {
      comments_truncated: T.let(false, T::Boolean),
      comments_removed: 0,
      issue_body_truncated: T.let(false, T::Boolean)
    }

    # Try with full content first
    statement = build_statement(issue, comments, agent_instructions, 0, 0, agent_mention_slug)
    if base64_length(statement) <= MAX_PROBLEM_STATEMENT_BASE64_LENGTH
      return { statement: statement, truncation_info: truncation_info }
    end

    # Truncate comments, if needed
    truncation_info[:comments_truncated] = true if comments.any?
    statement = build_statement(issue, comments, agent_instructions, 0, MAX_TRUNCATED_COMMENT_BODY_LENGTH, agent_mention_slug)
    if base64_length(statement) <= MAX_PROBLEM_STATEMENT_BASE64_LENGTH
      return { statement: statement, truncation_info: truncation_info }
    end

    # Remove oldest comments one by one if still too large
    truncated_comments = comments.dup
    while truncated_comments.any?
      truncated_comments.shift
      truncation_info[:comments_removed] += 1
      statement = build_statement(issue, truncated_comments, agent_instructions, 0, MAX_TRUNCATED_COMMENT_BODY_LENGTH, agent_mention_slug)
      if base64_length(statement) <= MAX_PROBLEM_STATEMENT_BASE64_LENGTH
        return { statement: statement, truncation_info: truncation_info }
      end
    end

    # Truncate issue body as a last resort
    max_body_length = approximate_max_truncated_issue_body_length(issue, agent_instructions, agent_mention_slug)
    while max_body_length > 0
      statement = build_statement(issue, [], agent_instructions, max_body_length, MAX_TRUNCATED_COMMENT_BODY_LENGTH, agent_mention_slug)
      if base64_length(statement) <= MAX_PROBLEM_STATEMENT_BASE64_LENGTH
        truncation_info[:issue_body_truncated] = true
        return { statement: statement, truncation_info: truncation_info }
      end
      max_body_length -= 20
    end

    raise "Failed to generate problem statement within size limits"
  end

  # Generate PR body for issue assignment
  # See https://github.com/github/sweagentd/blob/main/internal/events/on_issue_assigned.go#L384
  #
  # Params:
  # - issue: an Issue object
  # - is_experiment: boolean indicating if this is an experiment PR
  #
  # Returns: formatted PR body string
  sig { params(issue: Issue, is_experiment: T::Boolean).returns(T::Array[String]) }
  def self.generate_pr_body(issue:, is_experiment: false)
    body_placeholder = "Thanks for assigning this issue to me. I'm starting to work on it and will keep this PR's description up to date as I form a plan and make progress."

    body_suffix = "- Fixes #{issue.name_with_display_owner_reference}"
    if is_experiment
      body_suffix += "\n\n---\n\n_This PR is part of an experiment to improve CCA performance with semantic context from related issues and PRs._"
    end

    [body_placeholder, body_suffix]
  end

  # Filter comments to exclude:
  # 1. Minimized comments
  # 2. Comments from users without write access to the repository
  # 3. Comments from bots (except github-copilot[bot])
  # This matches the filtering logic used in sweagentd
  sig { params(comments: T::Array[T.any(IssueComment, T.untyped)], repository: Repository).returns(T::Array[T.any(IssueComment, T.untyped)]) }
  def self.filter_comments_for_problem_statement(comments, repository)
    comments.filter do |comment|
      # Skip minimized comments
      next false if comment.minimized?

      # Skip comments from users without write access
      # For issue comments, we check issues write permission
      if comment.user.present?
        next false unless repository.resources.issues.writable_by?(comment.user)

        # Skip comments from bots, except for github-copilot[bot]
        if comment.user.type == "Bot" && comment.user.display_login != "github-copilot[bot]"
          next false
        end
      end

      true
    end
  end

  # Helpers

  # Replaces bare issue references `#1` in issue or comment body with
  # global repo issue reference `owner/repo#num`
  # Inspired by IssueTransfer#replace_bare_issue_mentions
  #
  # @param body [String, nil] - the body text to process
  # @param repository [Repository] - the repository context for the issue
  #
  # @return [String, nil]
  sig { params(body: T.nilable(String), repository: Repository).returns(T.nilable(String)) }
  def self.replace_bare_issue_mentions(body, repository)
    return body if body.nil?

    issue_reference_text = /(?<=\s|^)(gh-|#)(\d+)\b/i

    body.gsub(issue_reference_text) do
      _pound, number = $1, $2.to_i
      "#{repository.name_with_display_owner}##{number}"
    end
  end

  sig { params(issue: Issue, comments: T::Array[T.untyped], agent_instructions: T.nilable(String), max_body_length: Integer, max_comment_length: Integer, agent_mention_slug: T.nilable(String)).returns(String) }
  def self.build_statement(issue, comments, agent_instructions, max_body_length, max_comment_length, agent_mention_slug = nil)
    repository = T.must(issue.repository)

    xml = []
    xml << ""
    xml << SECTION_SEPARATOR
    xml << ISSUE_SECTION_HEADER
    xml << ""
    xml << xml_tag("issue_title", issue.title)
    processed_body = replace_bare_issue_mentions(issue.body, repository)
    xml << xml_tag("issue_description", truncate(processed_body, max_body_length))
    xml << "- Closes #{issue.name_with_display_owner_reference}"
    xml << ""
    # The <agent_instructions> XML tag is explicitly used to gather context for events in mission-control
    # (see https://github.com/github/copilot-mission-control/pull/2380). Before changing or removing this tag,
    # verify which external services consume or rely on it.
    if agent_instructions && !agent_instructions.empty?
      xml << xml_tag("agent_instructions", agent_instructions)
      xml << ""
    end
    xml << ISSUE_COMMENTS_HEADING % { agent_mention_slug: agent_mention_slug || "copilot" }
    xml << "<comments>"
    comments.each do |comment|
      xml << build_comment_xml(comment, max_comment_length, repository)
    end
    xml << "</comments>"
    xml << ""

    xml.join("\n")
  end

  sig { params(comment: T.untyped, max_length: Integer, repository: T.nilable(Repository)).returns(String) }
  def self.build_comment_xml(comment, max_length, repository = nil)
    author = if comment.user&.display_login == "github-copilot[bot]"
      "@copilot"
    elsif comment.user&.type == "Bot"
      "#{comment.user.display_login}[bot]"
    else
      "@#{comment.user&.display_login}"
    end

    comment_body = comment.body || ""
    if repository
      comment_body = replace_bare_issue_mentions(comment_body, repository)
    end
    body = truncate(comment_body, max_length)

    # Use comment_new for non-copilot comments, comment_old for copilot
    tag = (author == "@copilot") ? "comment_old" : "comment_new"
    "<#{tag}><author>#{author}</author><body>\n#{body}</body></#{tag}>"
  end

  sig { params(tag: String, content: T.nilable(String)).returns(String) }
  def self.xml_tag(tag, content)
    "<#{tag}>#{content}</#{tag}>"
  end

  sig { params(str: T.nilable(String), max_length: T.nilable(Integer)).returns(T.nilable(String)) }
  def self.truncate(str, max_length)
    return str if max_length.nil? || max_length <= 0 || str.nil? || str.length <= max_length
    (max_length > 3) ? "#{str[0...(max_length - 3)]}..." : str[0...max_length]
  end

  sig { params(str: String).returns(Integer) }
  def self.base64_length(str)
    [str].pack("m0").length
  end

  sig { params(issue: Issue, agent_instructions: T.nilable(String), agent_mention_slug: T.nilable(String)).returns(Integer) }
  def self.approximate_max_truncated_issue_body_length(issue, agent_instructions, agent_mention_slug = nil)
    # Estimate header/comments size (without body)
    xml = []
    xml << ""
    xml << SECTION_SEPARATOR
    xml << ISSUE_SECTION_HEADER
    xml << ""
    xml << xml_tag("issue_title", issue.title)
    xml << xml_tag("issue_description", "")
    xml << "- Closes #{issue.name_with_display_owner_reference}"
    xml << ""
    if agent_instructions && !agent_instructions.empty?
      xml << xml_tag("agent_instructions", agent_instructions)
      xml << ""
    end
    xml << ISSUE_COMMENTS_HEADING % { agent_mention_slug: agent_mention_slug || "copilot" }
    xml << "<comments>"
    xml << "</comments>"
    xml << ""
    base = xml.join("\n").length
    [(MAX_PROBLEM_STATEMENT_BASE64_LENGTH * 0.75).to_i - base, 0].max
  end

  sig { params(error: Exception).returns(T::Boolean) }
  def self.timeout_error?(error)
    TIMEOUT_ERROR_CLASSES.any? { |cls| error.is_a?(cls) } || error.message.match?(TIMEOUT_ERROR_PATTERNS)
  end

  sig { params(repository: Repository, assignment_attributes: Issues::AgentAssignmentNewAttributes, source: String).returns(T::Array[String]) }
  def self.build_metric_tags(repository:, assignment_attributes:, source:)
    cross_repo = repository.name_with_display_owner != assignment_attributes.target_repository.name_with_display_owner
    custom_instructions_present = assignment_attributes.custom_instructions.to_s.strip.present?
    non_default_branch = assignment_attributes.base_ref != assignment_attributes.target_repository.default_branch
    custom_agent_used = assignment_attributes.custom_agent.to_s.strip.present?
    model = assignment_attributes.model.to_s.strip

    [
      "cross_repo:#{cross_repo}",
      "custom_instructions:#{custom_instructions_present}",
      "non_default_branch:#{non_default_branch}",
      "custom_agent:#{custom_agent_used}",
      "model:#{model.empty? ? 'default' : model}",
      "source:#{source}"
    ]
  end

  # Build related context section with similar issues and their closing PRs
  # Parse error message from Jobs API error responses
  # The Jobs API returns errors as JSON strings like:
  # '{"message":"job cannot be created due to...","errors":null}'
  # This method extracts and returns the human-readable message field.
  sig { params(error_message: String).returns(String) }
  def self.parse_jobs_api_error(error_message)
    parsed = JSON.parse(error_message)
    parsed["message"] || error_message
  rescue JSON::ParserError
    error_message
  end

  sig do
    params(
      issue: Issue,
      actor: User,
      orchestration_type: String,
      error: CopilotAPI::Error,
    ).returns(T::Hash[T.any(Symbol, String), String])
  end
  def self.build_failbot_context(issue:, actor:, orchestration_type:, error:)
    {
      app: "github",
      feature: "issues_copilot_assign",
      context: orchestration_type,
      "gh.issue.id": issue.id.to_s,
      "gh.user.id": actor.id.to_s,
      "copilot_api.error_type": error.class.name,
    }
  end

  sig { params(message: String).returns(String) }
  def self.append_request_id(message)
    "#{message} (Request id: #{GitHub.context[:request_id] || 'unknown' })"
  end

  # Triggers a Copilot job from mutation with error handling.
  # This wrapper calls trigger_copilot_job_from_mutation with the attributes from copilot_context
  # and handles CopilotAPI errors gracefully.
  sig { params(issue: Issue, actor: User, copilot_context: T::Hash[Symbol, T.untyped], orchestration_type: String).void }
  def self.trigger_job_with_error_handling(issue:, actor:, copilot_context:, orchestration_type: "IssueOrchestration")
    # Handle legacy orchestrations that may have nil attributes
    unless copilot_context[:attributes]
      GitHub.logger.warn("Skipping Copilot job trigger: copilot_context missing attributes for issue #{issue.id}")
      GitHub.dogstats.increment("issue_orchestration.copilot_job_trigger_skipped",
        tags: ["type:#{orchestration_type}", "step:trigger_copilot_job", "reason:missing_attributes"])
      return
    end

    # Token is now always encrypted in copilot_context
    token = Copilot::EncryptedToken.from(copilot_context[:request_token])

    assignment_attributes = copilot_context[:attributes]
    repository = T.must(issue.repository)

    if FeatureFlag.vexi.enabled?(:copilot_assignment_diagnostic_logging, default: false)
      GitHub.logger.info("copilot_job_trigger_diagnostic",
        "gh.issue.id": issue.id,
        "gh.user.id": actor.id,
        "gh.token_present": copilot_context[:request_token].present?,
        "gh.token_length": copilot_context[:request_token]&.length,
        "gh.copilot_api_url": GitHub.copilot_api_internal_url,
        "gh.tenant_slug": GitHub::CurrentTenant.get&.slug,
        "gh.hostname": Socket.gethostname,
        "gh.orchestration_type": orchestration_type,
        "gh.request_id": GitHub.context[:request_id],
      )
    end

    metric_tags = build_metric_tags(
      repository: repository,
      assignment_attributes: assignment_attributes,
      source: orchestration_type.underscore
    ) + ["async:true"]

    # Trigger Copilot job directly since orchestration is already async
    begin
      Issues.domain.copilot.trigger_copilot_job_from_mutation(
        actor: actor,
        issue: issue,
        assignment_attributes: copilot_context[:attributes],
        token: token,
        user_session_id: copilot_context[:user_session_id]
      )

      GitHub.dogstats.increment("issue_orchestration.copilot_job_trigger_success",
        tags: ["type:#{orchestration_type}", "step:trigger_copilot_job"])
      GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:success"])
    rescue CopilotAPI::Error => e
      # Log errors but don't propagate them since issue operation already succeeded
      GitHub.logger.error("Failed to trigger Copilot job in orchestration: #{e.message}")

      if FeatureFlag.vexi.enabled?(:copilot_assignment_diagnostic_logging, default: false)
        GitHub.logger.info("copilot_job_trigger_error_diagnostic",
          "gh.issue.id": issue.id,
          "gh.user.id": actor.id,
          "gh.error_class": e.class.name,
          "gh.error_message": e.message.truncate(500),
          "gh.copilot_api_url": GitHub.copilot_api_internal_url,
          "gh.tenant_slug": GitHub::CurrentTenant.get&.slug,
          "gh.hostname": Socket.gethostname,
          "gh.orchestration_type": orchestration_type,
          "gh.request_id": GitHub.context[:request_id],
        )
      end
      GitHub.dogstats.increment("issue_orchestration.copilot_job_trigger_failed",
        tags: ["type:#{orchestration_type}", "step:trigger_copilot_job"])

      bot = assignment_attributes.resolve_bot

      raise unless bot

      # CAPI's job-creation endpoint reports the "a job is already queued or running for this
      # assignment" 4xx for two distinct situations:
      #
      #   1. A genuine duplicate of OUR earlier attempt: another AgentAssignment row for the same
      #      (subject, target_repository, bot) tuple already exists with task_id stamped (the prior
      #      attempt is the one CAPI is referring to). The user-visible work is succeeding via the
      #      prior row, so the row from this losing attempt is a true orphan and is safe to remove.
      #
      #   2. A foreign duplicate: CAPI's "already queued" refers to a different active job on the
      #      same target_repository (e.g. a still-running session from an earlier, unrelated
      #      assignment). In this case our newly-created row is the *only* record of this user's
      #      assignment intent; destroying it would silently swallow the request. Better to leave
      #      the row in place with task_id: nil so the user-facing state still reflects "Copilot
      #      was asked to take this on, but the API was busy".
      #
      # In both cases we suppress the misleading "ruleset violation" comment and the Failbot that
      # the generic RequestError arm below would emit.
      if e.is_a?(CopilotAPI::RequestError) && parse_jobs_api_error(e.message).include?("already queued or running")
        target_repository = assignment_attributes.target_repository
        prior_assignment_exists = AgentAssignment.where(
          subject_type: :issue,
          subject_id: issue.id,
          assignee_id: bot.id,
          target_repository_id: target_repository.id,
        ).where.not(task_id: nil).exists?

        GitHub.dogstats.increment("issues.copilot.assign",
          tags: metric_tags + ["status:duplicate", "reason:already_queued", "prior_assignment:#{prior_assignment_exists}"])
        GitHub.logger.info(
          "[Copilot-Assign] CAPI reported job already queued or running for this assignment; treating as no-op",
          "gh.issue.id" => issue.id,
          "gh.user.id" => actor.id,
          "gh.orchestration_type" => orchestration_type,
          "gh.prior_assignment_exists" => prior_assignment_exists,
        )

        if prior_assignment_exists
          Issues.domain.copilot.cleanup_orphaned_agent_assignment(issue:, assignment_attributes:, actor:, bot:)
        end

        return
      end

      # Clean up the orphaned AgentAssignment record (created with task_id: nil)
      # since the task was never created due to the Copilot API error.
      Issues.domain.copilot.cleanup_orphaned_agent_assignment(issue:, assignment_attributes:, actor:, bot:)

      base_comment = "The agent encountered an error and was unable to start working on this issue:"
      comment_body =
        case e
        when CopilotAPI::UnauthorizedError
          GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:unauthorized"])
          "#{base_comment} The token used to assign the agent doesn't have the necessary permissions. Please make sure your token has read and write access to actions, contents, issues, and pull requests, and has permission to assign issues to the target repository. Learn more: https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/create-a-pr"
        when CopilotAPI::RAIError
          GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:unprocessable"])
          "#{base_comment} The request was filtered due to content policy. Please review the issue description and try again."
        when CopilotAPI::EntityTooLargeError
          GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:unprocessable"])
          "#{base_comment} The request was too large. Please try reducing the size of the issue description and try again."
        when CopilotAPI::RateLimitError
          GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:rate_limit"])
          "#{base_comment} The rate limit was exceeded. Please try again in a few minutes."
        when CopilotAPI::NetworkError
          GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:network"])
          Failbot.report(e, context: build_failbot_context(issue:, actor:, orchestration_type:, error: e))
          "#{base_comment} The service is temporarily unavailable. Please try again later."
        when CopilotAPI::PreconditionFailedError
          parsed_message = parse_jobs_api_error(e.message)
          if parsed_message.include?("customer selection")
            GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:customer_selection_required"])
            "#{base_comment} Before you can use Copilot cloud agent, you need to pick a \"Usage billed to\" option in your [Copilot settings](#{GitHub.url}/settings/copilot/features). Update your settings, then try again."
          elsif parsed_message.include?("insufficient premium quota")
            GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:insufficient_quota"])
            settings_link = "[Copilot settings](#{GitHub.url}/settings/copilot/features)"
            if Copilot::User.new(actor).use_token_based_billing?
              "#{base_comment} You don't have sufficient GitHub AI Credits to start a session. Review your usage and budgets in your #{settings_link}, then try again."
            else
              "#{base_comment} You don't have sufficient GitHub AI Credits to start a session. Review your usage in your #{settings_link}, then try again."
            end
          else
            GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:precondition_failed"])
            Failbot.report(e, context: build_failbot_context(issue:, actor:, orchestration_type:, error: e))
            "#{base_comment} #{GENERIC_ERROR_COMMENT}"
          end
        when CopilotAPI::RequestError
          GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:unprocessable"])
          Failbot.report(e, context: build_failbot_context(issue:, actor:, orchestration_type:, error: e))
          "#{base_comment} This may be caused by a repository ruleset violation. See [granting bypass permissions for the agent](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository#granting-bypass-permissions-for-your-branch-or-tag-ruleset), or please contact support if the issue persists."
        else
          reason = timeout_error?(e) ? "timeout" : "internal"
          GitHub.dogstats.increment("issues.copilot.assign", tags: metric_tags + ["status:failure", "reason:#{reason}"])
          Failbot.report(e, context: build_failbot_context(issue:, actor:, orchestration_type:, error: e))
          "#{base_comment} #{GENERIC_ERROR_COMMENT}"
        end
      issue.create_comment(bot, append_request_id(comment_body))
    end
  end
end
