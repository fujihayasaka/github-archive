# typed: true
# frozen_string_literal: true

class Api::SemanticDuplicateDetection < Api::App
  include ReceiveSchemaWithOpenApi

  # Detect duplicate issues based on title and body similarity
  #
  # POST /repositories/:repository_id/duplicate/issues
  #
  # Accepts JSON payload:
  # {
  #   "title": "Issue title",
  #   "body": "Issue body content",
  #   "per_page": 30,  # optional, defaults to 30
  #   "page": 1        # optional, defaults to 1
  # }
  #
  # Returns:
  # {
  #   "duplicates": [
  #     {
  #       "issue": {
  #         "id": 456,
  #         "number": 789,
  #         "title": "Similar issue title",
  #         "url": "https://api.github.com/repos/owner/repo/issues/789",
  #         "html_url": "https://github.com/owner/repo/issues/789",
  #         "state": "open",
  #         "user": {...},
  #         "labels": [...],
  #         "created_at": "2023-01-01T00:00:00Z",
  #         "updated_at": "2023-01-02T00:00:00Z",
  #         ... (full issue hash)
  #       },
  #       "score": 0.95,
  #       "confidence": "high",
  #       "likely_duplicate": true
  #     }
  #   ],
  #   "total_count": 1,
  #   "repository": "owner/repo"
  # }
  post "/repositories/:repository_id/duplicate/issues", operation_id: "issues/list-duplicates", read_from_replicas: true do
    @route_owner = "@github/issues"

    repo = find_repo!

    # Feature flag check - return 404 if not enabled for user, repo, or repo owner (org)
    deliver_error!(404) unless FeatureFlag.vexi.enabled?(:semantic_duplicate_detection_api, current_user, repo, repo.owner, default: false)

    # Require read access to the repository
    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    title = data["title"]
    body = data["body"]
    per_page = data["per_page"] || 30
    page = data["page"] || 1
    threshold = if allow_custom_confidence_threshold?
      data["confidence_threshold"] || Search::Queries::SemanticDuplicateIssueQuery::HIGH_CONFIDENCE_THRESHOLD
    else
      Search::Queries::SemanticDuplicateIssueQuery::HIGH_CONFIDENCE_THRESHOLD
    end

    query_results = Search::Queries::SemanticDuplicateIssueQuery.find_potential_duplicates_with_context(
      title:,
      body:,
      repository_id: repo.id,
      current_user:,
      threshold:,
      per_page:,
      page:,
      context: "api_duplicate_issue_detection"
    )

    duplicates = query_results.map do |result|
      {
        issue: Api::Serializer.serialize(:issue_hash, result.issue, { current_user:, repo: }),
        score: result.score,
        confidence: result.confidence,
        likely_duplicate: result.likely_duplicate?
      }
    end

    log_search_success(repo:, title:, body:, per_page:, page:)

    deliver_raw({
      duplicates: duplicates,
      total_count: duplicates.length,
      repository: repo.name_with_owner_for_api
    }, status: 200)
  rescue Search::Queries::SemanticDuplicateIssueQuery::DuplicateDetectionError => e
    # Handle validation errors (invalid content, missing required fields, etc.)
    log_validation_error(e, repo:)
    deliver_error!(422, message: "Duplicate detection validation error: #{e.message}")
  rescue StandardError => e
    # Handle unexpected errors during query execution
    log_search_error(e, repo:)
    deliver_error!(500, message: "Unable to perform duplicate detection search")
  end

  private

  def allow_custom_confidence_threshold?
    FeatureFlag.vexi.enabled?(:allow_custom_confidence_threshold, current_user, current_repo, current_repo.owner, default: false)
  end

  # Log successful duplicate detection search
  sig do
    params(
      repo: Repository,
      title: T.nilable(String),
      body: T.nilable(String),
      per_page: Integer,
      page: Integer
    ).void
  end
  def log_search_success(repo:, title:, body:, per_page:, page:)
    GitHub.dogstats.increment("duplicate_detection.issues.search")
    GitHub.logger.info(
      "api.duplicate_detection.search.performed",
      "code.namespace": "Api::SemanticDuplicateDetection",
      "code.function": "semantic_duplicate_detection.issues.search",
      "gh.repo.name": repo.name_with_owner_for_api,
      "title.length": title&.length,
      "body.length": body&.length,
      "per_page": per_page,
      "page": page
    )
  end

  # Log validation errors (invalid content, missing required fields, etc.)
  sig { params(error: Exception, repo: Repository).void }
  def log_validation_error(error, repo:)
    Failbot.report(error)

    GitHub.dogstats.increment(
      "duplicate_detection.issues.search.validation_error",
      tags: ["error_class:#{error.class.name}"]
    )

    GitHub.logger.warn(
      "api.duplicate_detection.validation_error",
      "code.namespace": "Api::SemanticDuplicateDetection",
      "code.function": "semantic_duplicate_detection.issues.search",
      "gh.repo.name": repo.name_with_owner_for_api,
      "error.message": error.message,
      "error.class": error.class.name
    )
  end

  # Log unexpected errors during query execution
  sig { params(error: Exception, repo: Repository).void }
  def log_search_error(error, repo:)
    Failbot.report(error)

    GitHub.dogstats.increment(
      "duplicate_detection.issues.search.error",
      tags: ["error_class:#{error.class.name}"]
    )

    GitHub.logger.error(
      "api.duplicate_detection.search.error",
      "code.namespace": "Api::SemanticDuplicateDetection",
      "code.function": "semantic_duplicate_detection.issues.search",
      "gh.repo.name": repo.name_with_owner_for_api,
      "error.message": error.message,
      "error.class": error.class.name
    )
  end
end
