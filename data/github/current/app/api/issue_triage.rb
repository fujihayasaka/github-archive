# typed: true
# frozen_string_literal: true

class Api::IssueTriage < Api::App
  include Api::Issues::EnsureIssuesEnabled
  include Api::App::DatabaseConnectionHelper
  include ReceiveSchemaWithOpenApi
  include Api::Issues::HandleIssueNotFound

  # Endpoint for creating triage comments on issues.
  #
  # Only users and integrations with triage_issue permission on a triage-agent-enabled repository can
  # access this endpoint
  post "/repositories/:repository_id/issues/:issue_number/triage", operation_id: "issues/triage", read_from_replicas: true do
    @route_owner = "@github/issues"

    # Don't reveal the endpoint exists until we verify access
    @documentation_url = :internal

    # Declare variables outside the replica block so they're accessible for the write operation
    issue_record = T.let(nil, T.nilable(Issue))
    allowlist = T.let(TriageAgent::Allowlist.new, TriageAgent::Allowlist)
    allowlist_enabled = T.let(false, T::Boolean)
    triage_rationale = T.let(nil, T.nilable(String))
    labels = T.let([], T::Array[String])
    issue_type = T.let(nil, T.nilable(String))
    fields = T.let([], T::Array[T::Hash[Symbol, T.nilable(T.any(String, Integer, Float))]])

    replica_clusters = T.let([ApplicationRecord::Repositories, ApplicationRecord::IamAbilities, ApplicationRecord::Collab, ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      # Get parameters from URL path
      repo_id = int_id_param!(key: :repository_id)
      issue_number = int_id_param!(key: :issue_number)

      repo = record_or_404 Repository.find_by(id: repo_id)

      # Check if the triage agent feature is enabled for this repository.
      deliver_error! 404, message: "Not Found" if !IssuesTriageAgentFeature.enrolled?(repo)

      issue = record_or_404 Issues.domain.by_number(issue_number, repo_id: repo.id).ok
      issue_record = T.cast(issue, Issue)

      set_context_controller_action(issue_record, "triage")

      # Require at least triage access for users; integrations need issues:write
      control_access :triage_issue,
        repo: repo,
        resource: issue_record,
        challenge: false,
        forbid: false,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: repo.private?,
        # Disallow issues authors from bypassing the triage access requirement with only read access.
        prevent_author: true

      # Access verified, restore normal documentation URL from operation
      @documentation_url = build_documentation_url(@operation)

      validate_triage_target_header!(repo, issue_number)

      # Parse request body AFTER auth checks to avoid leaking endpoint existence via 400 errors.
      data = receive(Hash)

      # This endpoint only works for issues, not pull requests
      deliver_error! 400, message: "This endpoint only supports issues, not pull requests" if issue_record.pull_request?

      # Get triage rationale from request body (required)
      triage_rationale = data["triage_rationale"]
      deliver_error! 422, message: "Missing required parameter: triage_rationale is required" if triage_rationale.blank?

      # Get optional parameters from request body
      labels = Array(data["labels"]).map(&:to_s)
      issue_type = data["type"]
      fields = parse_fields(data["fields"])

      # Read the triage agent config while we have access to the repo
      allowlist_enabled = IssuesTriageAgentFeature.new_config_enabled?(repo)
      if allowlist_enabled
        raw_config = TriageAgent::Configuration.read_triage_agent_configuration(repo)
        allowlist = TriageAgent::Frontmatter::AllowlistParser.parse(raw_config)
      end
    end

    # Build the suggestions struct and call the domain API
    result = with_write(clusters: [ApplicationRecord::IssuesPullRequests, ApplicationRecord::Mysql1]) do
      # Apply allowlist filtering (server-side enforcement) only when the feature flag is enabled
      suggestions = Issues::Domain::Suggestions::TriageSuggestions.new(
        body: T.must(triage_rationale),
        labels: allowlist_enabled ? allowlist.filter_labels(labels) : labels,
        type: allowlist_enabled ? allowlist.filter_type(issue_type) : issue_type,
        fields: allowlist_enabled ? allowlist.filter_fields(fields) : fields
      )

      if allowlist_enabled
        log_allowlist_filtering(
          issue: T.must(issue_record),
          allowlist_configured: allowlist.any_restrictions?,
          original_labels: labels,
          original_type: issue_type,
          original_fields: fields,
          filtered_suggestions: suggestions,
          comment_suppressed: !allowlist.comment_enabled
        )
      end

      # Determine if this is a retriage operation
      is_retriage = Issues.domain.triage.retriage_operation?(T.must(issue_record))

      Issues.domain.suggestions.suggest(
        issue: T.must(issue_record),
        suggestions: suggestions,
        retriage: is_retriage,
        skip_comment: allowlist_enabled && !allowlist.comment_enabled
      )
    end

    # Handle the result
    case result
    when GH::Result::Ok
      comment = result.value
      issue = T.must(issue_record)

      # Build response with comment and applied suggestions
      response = {
        "comment" => comment ? build_comment_response(comment) : nil,
        "labels" => issue.labels.map(&:name),
        "type" => issue.issue_type&.name,
        "fields" => build_fields_response(issue)
      }

      deliver_raw response, status: 201
    when GH::Result::Error
      deliver_error! 422, message: result.message
    end
  end

  private

  # Logs allowlist filtering results.
  # When restrictions are configured but nothing was filtered, logs that
  # the model's suggestions were already compliant with the allowlist.
  sig do
    params(
      issue: Issue,
      allowlist_configured: T::Boolean,
      original_labels: T::Array[String],
      original_type: T.nilable(String),
      original_fields: T::Array[T::Hash[Symbol, T.nilable(T.any(String, Integer, Float))]],
      filtered_suggestions: Issues::Domain::Suggestions::TriageSuggestions,
      comment_suppressed: T::Boolean
    ).void
  end
  def log_allowlist_filtering(issue:, allowlist_configured:, original_labels:, original_type:, original_fields:, filtered_suggestions:, comment_suppressed: false) # rubocop:disable Metrics/ParameterLists
    return unless allowlist_configured || comment_suppressed

    removed_labels = original_labels - filtered_suggestions.labels
    removed_type = (original_type && filtered_suggestions.type.nil?) ? original_type : nil
    removed_fields = original_fields.filter_map { |f| f[:name]&.to_s } - filtered_suggestions.fields.filter_map { |f| f[:name]&.to_s }

    dimensions = []
    dimensions << "labels" if removed_labels.any?
    dimensions << "type" if removed_type
    dimensions << "fields" if removed_fields.any?
    dimensions << "comment" if comment_suppressed

    if dimensions.empty?
      # Allowlist is configured but model suggestions were already compliant
      GitHub.dogstats.increment("triage_agent.allowlist_filtered", tags: ["result:compliant"])
      GitHub.logger.info("triage_agent.allowlist_filtered", {
        "code.namespace" => "Api::IssueTriage",
        "repository_id" => issue.repository_id,
        "issue_id" => issue.id,
        "result" => "compliant"
      })
      return
    end

    dimensions.each { |d| GitHub.dogstats.increment("triage_agent.allowlist_filtered", tags: ["result:filtered", "dimension:#{d}"]) }

    log_data = {
      "code.namespace" => "Api::IssueTriage",
      "repository_id" => issue.repository_id,
      "issue_id" => issue.id,
      "dimensions" => dimensions.join(", "),
    }
    log_data["removed_labels"] = removed_labels.join(", ") if removed_labels.any?
    log_data["removed_type"] = removed_type if removed_type
    log_data["removed_fields"] = removed_fields.join(", ") if removed_fields.any?

    GitHub.logger.info("triage_agent.allowlist_filtered", log_data)
  end

  # Builds a simplified comment response hash
  sig { params(comment: IssueComment).returns(T::Hash[String, T.untyped]) }
  def build_comment_response(comment)
    {
      "id" => comment.id,
      "node_id" => comment.global_relay_id,
      "html_url" => comment.permalink,
      "body" => comment.body,
      "user" => {
        "login" => comment.user&.display_login,
        "id" => comment.user&.id,
        "type" => comment.user&.type
      },
      "created_at" => comment.created_at&.iso8601,
      "updated_at" => comment.updated_at&.iso8601
    }
  end

  # Builds the fields response array for the issue
  sig { params(issue: Issue).returns(T::Array[T::Hash[String, T.untyped]]) }
  def build_fields_response(issue)
    issue.issue_field_values.filter_map do |field_value|
      issue_field = field_value.issue_field
      next if issue_field.nil?

      {
        "name" => issue_field.name,
        "value" => field_value.value
      }
    end
  end

  # Validates the X-Triage-Issue-Target header on every request (no-op when the header is absent).
  # This prevents prompt-injection attacks from triaging the wrong issue.
  # Emits a Datadog metric with tag result:empty, result:match, or result:mismatch.
  sig { params(repo: Repository, issue_number: Integer).void }
  def validate_triage_target_header!(repo, issue_number)
    triage_target_header = request.env["HTTP_X_TRIAGE_ISSUE_TARGET"]

    unless triage_target_header.present?
      GitHub.dogstats.increment("triage_agent.target_header_check", tags: ["result:empty"])
      return
    end

    expected_target = "#{repo.owner_display_login}/#{repo.name}##{issue_number}"
    header_matches = triage_target_header.downcase == expected_target.downcase
    if header_matches
      GitHub.dogstats.increment("triage_agent.target_header_check", tags: ["result:match"])
    else
      GitHub.dogstats.increment("triage_agent.target_header_check", tags: ["result:mismatch"])
      GitHub.dogstats.increment("triage_agent.target_header_mismatch")
      deliver_error! 403, message: "Triage target mismatch: expected target #{expected_target}"
    end
  end

  # Parses the fields array from the request body, converting string keys to symbols
  sig { params(fields_data: T.untyped).returns(T::Array[T::Hash[Symbol, T.nilable(T.any(String, Integer, Float))]]) }
  def parse_fields(fields_data)
    return [] unless fields_data.is_a?(Array)

    fields_data.filter_map do |field|
      next unless field.is_a?(Hash)

      name = field["name"]
      value = field["value"]
      next if name.blank?

      { name: name.to_s, value: value }
    end
  end
end
