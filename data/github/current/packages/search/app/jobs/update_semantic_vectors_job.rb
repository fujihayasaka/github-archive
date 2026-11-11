# typed: true
# frozen_string_literal: true

class UpdateSemanticVectorsJob < ApplicationJob
  # This job updates semantic vector fields (title_dense_vector, body_dense_vector)
  # independently from the main AddToSearchIndexJob. By decoupling vector indexing,
  # inference endpoint failures no longer block or degrade general metadata indexing.
  #
  # The job uses Elasticsearch partial updates (doc update) so only the vector fields
  # are modified — the rest of the document remains untouched.

  class DocumentMissingError < StandardError; end

  exempt_from_tenant_context_requirement

  queue_as :index_semantic_vectors

  retry_on_dirty_exit

  # Retry inference failures with polynomial backoff. We use more attempts than
  # the main indexing job because this job's sole purpose is vector generation,
  # so it's worth waiting longer for the inference endpoint to recover.
  #
  # 10 attempts ≈ ~4.5 hours of total wait time with polynomial backoff.
  retry_on(Elastomer::SemanticInferenceFailure, wait: :polynomially_longer, attempts: 10) do |job, error|
    GitHub.dogstats.increment("update_semantic_vectors.retries_exhausted", tags: ["type:#{job.type}", "error:inference_failure"])
    GitHub.logger.error("Semantic vector update retries exhausted", {
      "gh.job.name" => job.class.name,
      "gh.elasticsearch.document.type" => job.type,
      "gh.elasticsearch.document.id" => job.id,
      "exception.type" => error.class.to_s,
      "exception.message" => error.message,
    })
  end

  retry_on(Elastomer::SemanticTimeoutFailure, wait: :polynomially_longer, attempts: 10) do |job, error|
    GitHub.dogstats.increment("update_semantic_vectors.retries_exhausted", tags: ["type:#{job.type}", "error:timeout_failure"])
    GitHub.logger.error("Semantic vector update retries exhausted", {
      "gh.job.name" => job.class.name,
      "gh.elasticsearch.document.type" => job.type,
      "gh.elasticsearch.document.id" => job.id,
      "exception.type" => error.class.to_s,
      "exception.message" => error.message,
    })
  end

  # If the document doesn't exist yet (race with main indexing job), retry after a short delay.
  retry_on(DocumentMissingError, wait: :polynomially_longer, attempts: 3) do |job, _error|
    GitHub.dogstats.increment("update_semantic_vectors.document_not_found_exhausted", tags: ["type:#{job.type}"])
    GitHub.logger.error("Semantic vector update: request error after retries", {
      "gh.job.name" => job.class.name,
      "gh.elasticsearch.document.type" => job.type,
      "gh.elasticsearch.document.id" => job.id,
    })
  end

  retry_on_recoverable_exceptions(wait: :polynomially_longer, attempts: 8) do |job, _error|
    GitHub.dogstats.increment("update_semantic_vectors.recoverable_error", tags: ["type:#{job.type}"])
  end

  retry_on(ElastomerClient::Client::ConnectionFailed, wait: :polynomially_longer, attempts: 8) do |job, _error|
    GitHub.dogstats.increment("update_semantic_vectors.recoverable_error", tags: ["type:#{job.type}", "error:es_connection_failed"])
  end

  # Version conflicts occur when AddToSearchIndexJob replaces the document
  # concurrently. Retry a few times since the conflict is transient.
  retry_on(ElastomerClient::Client::DocumentAlreadyExistsError, wait: :polynomially_longer, attempts: 3) do |job, _error|
    GitHub.dogstats.increment("update_semantic_vectors.version_conflict_exhausted", tags: ["type:#{job.type}"])
  end

  attr_reader :type, :id, :options

  # Public: Update semantic vector fields for a single document.
  #
  # type - The document type as a String ("issue" or "pull_request")
  # id   - The numeric ID of the database record
  # opts - An options hash
  #
  # Returns nil.
  sig { params(type: String, id: Integer, opts: T::Hash[String, T.untyped]).void }
  def perform(type, id, opts = {})
    @type = type
    @id = id
    @options = opts.with_indifferent_access

    unless Issues::SemanticSearchEligibility.semantic_available?
      GitHub.dogstats.increment("update_semantic_vectors.skipped", tags: ["type:#{type}", "reason:semantic_unavailable"])
      return
    end

    GitHub.dogstats.increment("update_semantic_vectors.perform", tags: ["type:#{type}"])

    semantic_fields, routing_id = build_semantic_fields
    if semantic_fields.blank? || routing_id.nil?
      GitHub.dogstats.increment("update_semantic_vectors.skipped", tags: ["type:#{type}", "reason:missing_record"])
      return
    end

    if options["index"].present?
      semantic_fields = fetch_and_normalize_vectors(semantic_fields)
      if semantic_fields.nil?
        GitHub.dogstats.increment("update_semantic_vectors.skipped", tags: ["type:#{type}", "reason:missing_inference_id"])
        return
      elsif semantic_fields.blank?
        GitHub.dogstats.increment("update_semantic_vectors.skipped", tags: ["type:#{type}", "reason:empty_vectors"])
        return
      end
    end

    update_vectors_in_elasticsearch(semantic_fields, routing_id: routing_id)
  end

  private

  # Build the semantic field hash from the model's current data.
  #
  # Returns [Hash, Integer] with the fields and routing ID,
  # or [nil, nil] if the model doesn't exist. May also return
  # [nil, Integer] if the model exists but has no indexable fields.
  sig { returns(T.nilable([T.nilable(T::Hash[Symbol, String]), T.nilable(Integer)])) }
  def build_semantic_fields
    case type
    when "issue"
      issue = ::Issue.find_by(id: id)
      return unless issue
      return unless issue.repository

      [build_fields(model: issue, body_source: issue, source_label: "issue"), issue.repository_id]
    when "pull_request"
      pr = ::PullRequest.find_by(id: id)
      return unless pr

      repository = pr.repository
      return unless repository

      [build_fields(model: pr, body_source: pr.issue, source_label: "pull_request"), repository.id]
    end
  end

  sig { params(model: T.any(Issue, PullRequest), body_source: T.nilable(Issue), source_label: String).returns(T.nilable(T::Hash[Symbol, String])) }
  def build_fields(model:, body_source:, source_label:)
    fields = {}
    fields[:title_dense_vector] = model.title if model.title.present?

    if body_source && body_source.body.present?
      body = ::Search.clean_and_sanitize(body_source.body)
      cleaned_body = ::Search.remove_long_uninterrupted_strings(body, source: source_label)
      fields[:body_dense_vector] = cleaned_body if cleaned_body.present?
    end

    fields.presence
  end

  # Call the ES inference endpoint for each text field, L2-normalize the
  # returned chunk vectors, and return a hash of field → nested chunk arrays
  # ready for indexing into nested dense_vector fields.
  #
  # The inference endpoint may return multiple embeddings per field when the
  # text exceeds the configured chunk size. Each chunk is normalized and
  # wrapped as `{ embedding: [...] }` for the nested mapping.
  #
  # Raises Elastomer::SemanticInferenceFailure or SemanticTimeoutFailure
  # on inference errors so the job's existing retry_on handlers apply.
  sig { params(text_fields: T::Hash[Symbol, String]).returns(T.nilable(T::Hash[Symbol, T::Array[T::Hash[Symbol, T::Array[Float]]]])) }
  def fetch_and_normalize_vectors(text_fields)
    target_index = options["index"]
    return nil unless target_index.present?

    inference_id = GitHub.es_issues_prs_inference_id
    return nil if inference_id.nil?

    index = Elastomer::Index.new(target_index)
    vector_fields = {}

    text_fields.each do |field_name, text|
      chunks = fetch_normalized_embeddings(index, text, inference_id: inference_id)
      next if chunks.empty?

      vector_fields[field_name] = chunks.map { |vec| { embedding: vec } }
    end

    vector_fields
  rescue ElastomerClient::Client::TimeoutError => err
    raise Elastomer::SemanticTimeoutFailure, err.message
  rescue ElastomerClient::Client::Error => err
    raise Elastomer::SemanticInferenceFailure, err.message if Elastomer.semantic_inference_failure?(err)
    raise
  end

  # Fetch all chunk embedding vectors from the ES inference endpoint.
  sig { params(index: Elastomer::Index, text: String, inference_id: String).returns(T::Array[T::Array[Float]]) }
  def fetch_normalized_embeddings(index, text, inference_id:)
    embeddings = Elastomer::VectorUtils.fetch_all_embeddings(index, text, inference_id: inference_id, normalize: true)

    if embeddings.empty?
      GitHub.dogstats.increment("update_semantic_vectors.invalid_embedding_response", tags: ["type:#{type}"])
      GitHub.logger.error("Invalid embedding response from inference endpoint", {
        "gh.job.name" => self.class.name,
        "gh.elasticsearch.document.type" => type,
        "gh.elasticsearch.document.id" => id,
        "gh.elasticsearch.inference_id" => inference_id,
      })
    end

    embeddings
  end

  # Issue a partial update to Elasticsearch to set only the vector fields.
  # This uses the _update API so only the specified fields are modified.
  # Requires options["index"] to be set — the job will not write without
  # an explicit target index.
  sig { params(fields: T::Hash[Symbol, T.untyped], routing_id: Integer).void }
  def update_vectors_in_elasticsearch(fields, routing_id:)
    target_index = options["index"]
    unless target_index.present?
      GitHub.dogstats.increment("update_semantic_vectors.skipped", tags: ["type:#{type}", "reason:no_target_index"])
      return
    end

    index = Elastomer::Index.new(target_index)
    index.partial_update(id, fields, routing: routing_id)
  rescue ElastomerClient::Client::DocumentAlreadyExistsError
    # Version conflict — let retry_on handle it directly without Failbot noise.
    raise
  rescue ElastomerClient::Client::Error => err
    raise_retryable_vector_errors!(err)

    # Non-retryable: report to Failbot for detail, then re-raise so the job
    # fails visibly in job tracking infrastructure.
    GitHub.dogstats.increment("update_semantic_vectors.failed", tags: ["type:#{type}"])
    Failbot.report(err,
      "gh.elasticsearch.action": "update_semantic_vectors",
      "db.elasticsearch.path_parts.index": target_index,
      "gh.elasticsearch.document.id": id,
    )
    raise
  end

  # Classify Elasticsearch errors and re-raise as the appropriate retryable
  # exception so the job's retry_on handlers can route them correctly.
  # Returns normally only for non-retryable errors.
  sig { params(error: ElastomerClient::Client::Error).void }
  def raise_retryable_vector_errors!(error)
    raise DocumentMissingError, error.message if document_missing_error?(error)
    raise Elastomer::SemanticTimeoutFailure, error.message if error.is_a?(ElastomerClient::Client::TimeoutError)
    raise Elastomer::SemanticInferenceFailure, error.message if Elastomer.semantic_inference_failure?(error)
    raise error if error.retry?
  end

  sig { params(error: T.untyped).returns(T::Boolean) }
  def document_missing_error?(error)
    return false unless error.respond_to?(:error)

    details = error.error
    return false unless details.is_a?(Hash)

    error_type = details.dig("type") || details.dig("root_cause", 0, "type")
    error_type == "document_missing_exception"
  end
end
