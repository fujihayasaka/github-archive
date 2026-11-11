# typed: strict
# frozen_string_literal: true

module Issues::SemanticsHelper
  extend T::Helpers

  # Precomputed pattern for detecting search qualifiers in text
  SEARCH_QUALIFIERS_PATTERN = /\b(#{Search::Queries::ConditionalIssueQuery.field_list.map { |f| Regexp.escape(f.to_s) }.join('|')}):/i

  abstract!

  sig { abstract.returns(Repository) }
  def current_repository; end

  sig { abstract.returns(ActionController::Parameters) }
  def params; end

  sig { returns(T.nilable(User)) }
  def current_user
    super
  end

  # Feature flag to enable semantic similarity endpoints for clients
  # When enabled, clients can access endpoints that provide semantic detection results.
  sig { returns(T::Boolean) }
  def semantic_similarity_endpoints_for_client_enabled?
    FeatureFlag.vexi.enabled?(:semantic_similarity_duplicate_issue_detection, current_repository, current_repository.owner, current_user, default: false)
  end

  # Feature flag killswitch for LLM-assisted duplicate detection results
  # When enabled:
  #   - it allows LLM-assisted evaluation to be used in the duplicate detection flow,
  #   - This may provide more accurate results at the cost of increased latency and potential costs.
  # When disabled:
  #   - the system will fall back to the traditional semantic similarity based on vector search alone
  #   - No LLM calls will be made, ensuring faster responses and no additional costs, but potentially less accurate duplicate detection.
  sig { returns(T::Boolean) }
  def llm_assisted_evaluation_enabled?
    FeatureFlag.vexi.enabled?(:llm_assisted_semantic_duplicate_issue_detection, current_repository, current_repository.owner, current_user, default: false)
  end

  sig { returns(T::Boolean) }
  def semantic_search_bypass_validation_enabled?
    FeatureFlag.vexi.enabled?(:semantic_search_bypass_validation, current_repository, current_repository.owner, current_user, default: false)
  end

  sig { returns(T::Boolean) }
  def semantic_duplicate_issue_detection_enabled?
    FeatureFlag.vexi.enabled?(:semantic_duplicate_issue_detection, current_repository, current_repository.owner, current_user, default: false)
  end

  sig { params(filtered_params: T.nilable(ActionController::Parameters)).returns(T::Boolean) }
  def contains_semantic_similarity_params?(filtered_params = nil)
    # Use filtered params if provided, otherwise fallback to direct params access
    params_to_check = filtered_params || params
    params_to_check[:title].present? || params_to_check[:body].present?
  end

  sig { params(filtered_params: T.nilable(ActionController::Parameters)).returns(String) }
  def build_semantic_search_phrase(filtered_params = nil)
    # Use filtered params if provided, otherwise fallback to direct params access
    params_to_check = filtered_params || params
    phrase = [params_to_check[:title], params_to_check[:body]].compact.join(" ").strip
    return phrase if phrase.blank?

    # If the phrase contains search qualifiers, skip semantic search entirely
    # Semantic search works best with natural language, not structured queries
    if phrase.match?(SEARCH_QUALIFIERS_PATTERN)
      GitHub.dogstats.increment("issues.semantics_helper.search_qualifiers_detected")
      GitHub.logger.info("issues.semantic_search.qualifiers_detected",
        "gh.user.id": current_user&.id,
        "gh.repository.id": current_repository.id,
        "gh.issues.semantic_search.phrase_length": phrase.length,
        "gh.issues.semantic_search.qualifiers": phrase.scan(SEARCH_QUALIFIERS_PATTERN).flatten.uniq.join(","),
        "gh.issues.semantic_search.qualifier_count": phrase.scan(SEARCH_QUALIFIERS_PATTERN).flatten.uniq.size,
        "gh.issues.semantic_search.has_title": params_to_check[:title].present?,
        "gh.issues.semantic_search.has_body": params_to_check[:body].present?,
        "code.namespace": T.unsafe(self).class.name
      )
      return "" # Return empty string to skip semantic search
    end

    # Apply conditional markdown sanitization if markdown syntax is detected
    phrase = conditionally_sanitize_markdown(phrase)

    # For natural language queries, sanitize for better semantic search
    sanitized = phrase
      # Remove search operators (case-sensitive - only uppercase AND/OR/NOT)
      .gsub(/\b(AND|OR|NOT)\b/, " ")
      # Remove quotes (single and double)
      .gsub(/["']/, " ")
      # Clean up multiple spaces and strip
      .gsub(/\s+/, " ")
      .strip

    sanitized
  end

  # Strong parameter filtering for GET semantic similarity requests (flat structure)
  # Allows route parameters plus semantic search parameters
  # Handles both camelCase and snake_case parameter names for client flexibility
  sig { returns(ActionController::Parameters) }
  def semantic_similarity_params_get
    params.permit(
      # Route parameters for repository/user context
      :user_id,
      :repository,
      :id,
      # Semantic search parameters
      :title,
      :body,
      :context,
      :page,
      :per_page,
      :threshold
    )
  end

  # Strong parameter filtering for POST semantic similarity requests (nested structure)
  # Expects parameters nested under 'search' key for better API design
  # Handles both camelCase and snake_case parameter names for client flexibility
  sig { returns(ActionController::Parameters) }
  def semantic_similarity_params_post
    permitted = params.permit(
      :user_id,
      :repository,
      :id,
      search: [
        :title,
        :body,
        :context,
        :page,
        :per_page,
        :threshold
      ]
    )

    # Flatten the structure by merging route params with search params
    route_params = permitted.slice(:user_id, :repository, :id)
    search_params = permitted[:search] || {}

    route_params.merge(search_params)
  end

  private

  # Conditionally sanitizes markdown if detected in the phrase.
  # Only applies sanitization when markdown syntax is present to avoid unnecessary processing.
  sig { params(phrase: String).returns(String) }
  def conditionally_sanitize_markdown(phrase)
    return phrase unless contains_markdown?(phrase)

    ::Search.clean_and_sanitize(phrase)
  end

  # Detects if text contains meaningful markdown by checking if CommonMarker parsing
  # produces different plaintext output than the original (indicating markdown was processed).
  # This leverages GitHub's existing markdown processing to determine if sanitization would help.
  sig { params(text: String).returns(T::Boolean) }
  def contains_markdown?(text)
    return false if text.blank?

    # Quick regex check first for performance - only do expensive parsing if we suspect markdown
    return false unless text.match?(/[*_`#\[\]<>~]/)

    begin
      # Use CommonMarker (same as Search.clean_markdown) to detect if text contains markdown
      # If the plaintext output differs significantly from input, markdown was processed
      normalized_input = text.strip.gsub(/\s+/, " ")
      processed_output = CommonMarker.render_doc(text, :DEFAULT, [:strikethrough, :table]).to_plaintext.strip.gsub(/\s+/, " ")

      # If the processed output is different from normalized input, markdown was detected and processed
      normalized_input != processed_output
    rescue StandardError => e
      # If parsing fails for any reason, fall back to true to be safe
      # (better to over-sanitize than under-sanitize)
      GitHub.dogstats.increment("issues.semantics_helper.markdown_detection_error")
      Failbot.report(e, context: "Issues::SemanticsHelper#contains_markdown?")
      true
    end
  end

  # Serialize an array of SimilarIssueResult structs for API responses
  # This method provides a centralized way to serialize issues for semantic similarity endpoints
  sig { params(results: T::Array[Search::Queries::SimilarIssueResult], current_user: T.nilable(User), current_repository: Repository).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def serialize_similar_issues(results, current_user:, current_repository:)
    results.map do |result|
      {
        issue: Api::Serializer.serialize(:issue_hash, result.issue, { current_user:, repo: current_repository }),
        score: result.score
      }
    end
  end
end
