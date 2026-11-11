# typed: true
# frozen_string_literal: true

class Issues::SemanticsController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ControllerMethods::Issues
  include Issues::SemanticsHelper
  include ApplicationController::VerifiedFetchDependency
  include Issues::DuplicateDetectionLlmDependency

  before_action :semantic_similarity_feature_flag_required
  before_action :parse_json_params, only: [:create_similar_to_new_search, :feedback]

  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  allow_verified_fetch only: [:similar_to_existing, :similar_to_new, :create_similar_to_new_search, :feedback]

  depends_on_clusters \
    ApplicationRecord::IssuesPullRequests,  # For issue lookups
    ApplicationRecord::Mysql1,              # For basic repository/user data
    ApplicationRecord::Repositories,        # For current_repository access
    ApplicationRecord::Collab,              # For user authentication and authorization
    ApplicationRecord::IamAbilities,        # For ability checks and permissions
    ApplicationRecord::Iam,                 # For user role management
    optional: false

  depends_on_clusters \
    ApplicationRecord::Spokes,              # For repository metadata (optional)
    optional: true

  # Allow POST requests to be validated by the cluster dependency validator
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Issues::SemanticsController#create_similar_to_new_search",
    "Issues::SemanticsController#feedback"
  ]

  DEFAULT_SEMANTIC_SIMILAR_ISSUE_LIMIT = 3

  class SemanticResponse < T::Struct
    const :error, T.nilable(String)
    const :result, T.nilable(T::Array[Search::Queries::SimilarIssueResult])
  end

  # Find issues semantically similar to an existing issue.
  # Returns 404 if issue not found, issues disabled, or feature flag disabled.
  def similar_to_existing # rubocop:disable GitHub/UseRestfulActions
    return render_404 unless current_repository.has_issues?

    issue = current_repository.issues.find_by(number: params[:id].to_i)
    return render_404 if render_not_found?(issue)

    issue = T.must(issue) # Safe after render_not_found? check
    context = params[:context] || "issues/semantics_controller#similar_to_existing"

    # Track usage by context
    GitHub.dogstats.increment("issues.semantics_controller.request",
      tags: ["context:#{context}", "endpoint:existing_issue"])

    similar_issues = Search::Queries::SemanticSimilarIssueQuery.find_similar_to(
      issue:,
      current_user:,
      page: (params.fetch(:page, 1)).to_i,
      per_page: (params.fetch(:per_page, DEFAULT_SEMANTIC_SIMILAR_ISSUE_LIMIT)).to_i,
      threshold: (params.fetch(:threshold, Search::Queries::SemanticSimilarIssueQuery::DEFAULT_SEMANTIC_SIMILAR_ISSUE_THRESHOLD)).to_f,
      context:
    )

    GitHub.dogstats.histogram("issues.semantics_controller.results_count",
      similar_issues.length, tags: ["context:#{context}", "endpoint:existing_issue"])

    respond_to do |format|
      format.json do
        render json: {
          issue_number: issue.number,
          similar_issues: serialize_similar_issues(similar_issues, current_user:, current_repository:)
        }
      end
    end
  end

  # Find issues semantically similar to provided title/body text.
  # Returns 400 if no title/body provided or search phrase empty after sanitization.
  # Returns 500 if search service fails.
  def similar_to_new # rubocop:disable GitHub/UseRestfulActions
    filtered_params = semantic_similarity_params_get
    result = perform_semantic_search(
      filtered_params,
      default_context: "issues/semantics_controller#similar_to_new",
      endpoint_tag: "new_issue"
    )

    return if performed?
    respond_to do |format|
      format.json { render json: result }
    end
  end

  # POST endpoint for finding issues semantically similar to provided title/body text.
  # Same functionality as similar_to_new but accepts POST requests for longer inputs.
  # Returns 400 if no title/body provided or search phrase empty after sanitization.
  # Returns 500 if search service fails.
  def create_similar_to_new_search # rubocop:disable GitHub/UseRestfulActions
    filtered_params = semantic_similarity_params_post
    result = perform_semantic_search(
      filtered_params,
      default_context: "issues/semantics_controller#create_similar_to_new_search",
      endpoint_tag: "new_issue_post"
    )

    return if performed?
    respond_to do |format|
      format.json { render json: result }
    end
  end

  # POST endpoint to collect user feedback on similar issues results.
  # Returns 400 if invalid rating or session_id is provided.
  def feedback # rubocop:disable GitHub/UseRestfulActions
    context = feedback_params[:context] || "issues/semantics_controller#feedback"

    unless valid_feedback_rating?(feedback_params[:rating])
      GitHub.dogstats.increment("issues.semantics_controller.error", tags: ["context:#{context}", "endpoint:feedback", "error:invalid_rating"])
      return render json: { error: "Invalid rating. Must be 'positive' or 'negative'" }, status: :bad_request
    end

    unless valid_session_id?(feedback_params[:session_id])
      GitHub.dogstats.increment("issues.semantics_controller.error", tags: ["context:#{context}", "endpoint:feedback", "error:invalid_session_id"])
      return render json: { error: "Invalid session_id." }, status: :bad_request
    end

    # Track feedback by context
    GitHub.dogstats.increment("issues.semantics_controller.request",
      tags: ["context:#{context}", "endpoint:feedback"])

    GlobalInstrumenter.instrument("similar_issues_issues_create_feedback", {
      rating: feedback_params[:rating],
      repository: current_repository,
      repository_owner: current_repository.owner,
      request_context: GitHub.context.to_hash,
      session_id: feedback_params[:session_id]
    })

    respond_to do |format|
      format.json { render json: { success: true } }
    end
  end

  private

  def feedback_params
    params.slice(:rating, :session_id, :context).permit(:rating, :session_id, :context)
  end

  def valid_feedback_rating?(rating)
    %w[positive negative].include?(rating)
  end

  # Matches UUID-like session IDs (8-4-4-4-12 hex format).
  # Intentionally does not enforce UUID version/variant to keep validation
  # lightweight and avoid dropping valid session IDs in logs or metrics.
  def valid_session_id?(session_id)
    return false if session_id.blank?
    /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i.match?(session_id)
  end

  def semantic_similarity_feature_flag_required
    render_404 unless semantic_similarity_endpoints_for_client_enabled?
  end

  # Performs semantic search for issues using either duplicate detection or similarity search.
  # Returns a hash with search_phrase and similar_issues, or renders an error response
  sig do
    params(
      filtered_params: ActionController::Parameters,
      default_context: T.nilable(String),
      endpoint_tag: String
    ).returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  def perform_semantic_search(filtered_params, default_context: nil, endpoint_tag: "new_issue_post")
    return render_404 unless current_repository.has_issues?

    unless contains_semantic_similarity_params?(filtered_params)
      context = filtered_params[:context] || default_context
      GitHub.dogstats.increment("issues.semantics_controller.error", tags: ["context:#{context}", "endpoint:#{endpoint_tag}", "error:missing_parameters"])
      render json: { error: "Title or body parameters must be provided for semantic similarity search" }, status: :bad_request
      return
    end

    search_phrase = build_semantic_search_phrase(filtered_params)
    if search_phrase.blank?
      context = filtered_params[:context] || default_context
      GitHub.dogstats.increment("issues.semantics_controller.error", tags: ["context:#{context}", "endpoint:#{endpoint_tag}", "error:empty_search_phrase"])
      render json: { error: "Unable to perform semantic search: search phrase is empty after sanitization" }, status: :bad_request
      return
    end

    # Use filtered parameters for context and pagination
    context = filtered_params[:context] || default_context

    # Track usage by context
    GitHub.dogstats.increment("issues.semantics_controller.request",
      tags: ["context:#{context}", "endpoint:#{endpoint_tag}"])

    query_result = begin
      if semantic_duplicate_issue_detection_enabled?
        find_high_confidence_duplicates(filtered_params, context:, tag: endpoint_tag)
      else
        find_semantically_similar(search_phrase, filtered_params:, context:, tag: endpoint_tag)
      end
    rescue *Search::Queries::SemanticSimilarIssueQuery::RESCUABLE_ERROR_TYPES => e
      Failbot.report(e)
      GitHub.dogstats.increment("issues.semantics_controller.error", tags: ["context:#{context}", "endpoint:#{endpoint_tag}", "error:#{e.class.name}"])
      render json: { error: "Unable to perform semantic search at this time" }, status: :internal_server_error
      return
    end

    if query_result.error.present?
      render json: { error: query_result.error }, status: :bad_request
      return
    end

    semantic_results = T.must(query_result.result)

    # Run science experiment in parallel, but always return control response format
    science "semantics_controller.llm_assisted_evaluation" do |e|
      e.run_if { contains_semantic_similarity_params?(filtered_params) && llm_assisted_evaluation_enabled? }
      e.use do
        {
          search_phrase:,
          similar_issues: serialize_similar_issues(semantic_results, current_user:, current_repository:)
        }
      end

      e.try do
        batch_result = evaluate_batch_duplicates_from_text(
          candidates: semantic_results,
          context: context,
          title: filtered_params[:title].to_s,
          body: filtered_params[:body].to_s,
          llm_enabled: true
        )

        instrument_processing_metrics(batch_result, context:)
        serialize_llm_duplicate_results(batch_result)
          .duplicates
          # Filter to only return issues classified as duplicates by LLM
          # This creates intentional mismatch with control path (which returns all similar issues)
          # since LLM evaluation is meant to be more precise than semantic similarity alone
          .filter { |item| item.duplicate_classification.is_duplicate }
      end

      e.compare do |control, candidate|
        control_ids = control[:similar_issues].map { |result| result[:issue][:id] }.sort
        candidate_ids = candidate.map(&:issue_id).sort

        # Return true only when candidate is a proper subset (LLM successfully filtered)
        # Return false when identical (no filtering occurred) or candidate has extra items
        (candidate_ids - control_ids).empty? && candidate_ids != control_ids
      end

      e.clean do |result|
        if result.is_a?(DuplicateResultSummary)
          result.duplicates.map(&:issue_id)
        elsif result.is_a?(Array) # Handle filtered duplicate arrays
          result.map(&:issue_id)
        elsif result.is_a?(Hash) && result[:similar_issues].is_a?(Array)
          result[:similar_issues].map { |i| i[:issue][:id] }
        else
          nil
        end
      end
    end
  end

  sig do
    params(
      filtered_params: ActionController::Parameters,
      context: String,
      tag: String
    ).returns(SemanticResponse)
  end
  def find_high_confidence_duplicates(filtered_params, context:, tag:)
    query_result = Search::Queries::SemanticDuplicateIssueQuery.find_high_confidence_duplicates(
      title: filtered_params[:title].to_s,
      body: filtered_params[:body].to_s,
      repository_id: current_repository.id,
      current_user:,
      page: filtered_params.fetch(:page, 1).to_i,
      per_page: filtered_params.fetch(:per_page, DEFAULT_SEMANTIC_SIMILAR_ISSUE_LIMIT).to_i,
      context:
    )

    if query_result.blank?
      # Handle the case where search may return empty Array result
      GitHub.dogstats.increment("issues.semantics_controller.empty_results", tags: ["context:#{context}", "endpoint:#{tag}", "query_type:duplicate_detection"])
      return SemanticResponse.new(error: nil, result: [])
    end

    # Normalize results for backward compatibility. Duplicate detection returns issues with a confidence score,
    # while semantic similarity returns `SimilarIssueResult` structs. We normalize the output so the controller
    # always returns a consistent response shape and the existing UI continues to work.
    #
    # TODO: If the duplicate detection query proves to be effective in practice, this compatibility layer can likely be simplified or removed.
    result = query_result.filter_map do |result|
      next if result.issue.nil? # Skip results where issue could not be loaded (e.g. deleted since search index was last updated)
      Search::Queries::SimilarIssueResult.new(issue: T.must(result.issue), score: result.score)
    end

    GitHub.dogstats.histogram("issues.semantics_controller.results_count", result.length, tags: ["context:#{context}", "endpoint:#{tag}", "query_type:duplicate_detection"])
    SemanticResponse.new(error: nil, result:)
  end

  sig do
    params(
      search_phrase: String,
      filtered_params: ActionController::Parameters,
      context: String,
      tag: String
    ).returns(SemanticResponse)
  end
  def find_semantically_similar(search_phrase, filtered_params:, context:, tag:)
    opts = {
      current_user:,
      request_ip: remote_ip,
      user_session:,
      cap_filter:,
      phrase: "is:issue repo:#{current_repository.name_with_display_owner} #{search_phrase}".strip,
      source_fields: false,
      highlight: false,
      context:,
      page: filtered_params.fetch(:page, 1).to_i,
      per_page: filtered_params.fetch(:per_page, DEFAULT_SEMANTIC_SIMILAR_ISSUE_LIMIT).to_i,
    }

    # Add validation bypass for semantic search if feature flag is enabled
    # If it is enabled, skip advanced query validation since we're constructing a simple query and want to allow for more flexible search phrases
    if semantic_search_bypass_validation_enabled?
      opts[:with_validation] = false
    end

    query = Search::Queries::ConditionalIssueSemanticQuery.new(opts)
    unless query.valid_query?
      GitHub.dogstats.increment("issues.semantics_controller.error", tags: ["context:#{context}", "endpoint:#{tag}", "query_type:similarity_search", "error:invalid_query"])
      return SemanticResponse.new(error: "Unable to perform semantic search: #{query.invalid_reason}", result: nil)
    end

    search_result = query.execute.results
    if search_result.blank?
      # Handle the case where search may return empty Array result
      GitHub.dogstats.increment("issues.semantics_controller.empty_results", tags: ["context:#{context}", "endpoint:#{tag}", "query_type:similarity_search"])
      return SemanticResponse.new(error: nil, result: [])
    end

    result = search_result.map { |result| Search::Queries::SimilarIssueResult.new(issue: result["_model"], score: result["_score"]) }
    GitHub.dogstats.histogram("issues.semantics_controller.results_count", result.length, tags: ["context:#{context}", "endpoint:#{tag}", "query_type:similarity_search"])
    SemanticResponse.new(error: nil, result:)
  end
end
