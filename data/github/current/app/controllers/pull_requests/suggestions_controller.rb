# typed: strict
# frozen_string_literal: true

class PullRequests::SuggestionsController < AbstractRepositoryController
  include JsonDependency
  include VerifiedFetchDependency

  allow_verified_fetch

  before_action :login_required
  before_action :parse_json_params
  before_action :writable_repository_required
  before_action :content_authorization_required
  around_action :set_log_context

  # Unified endpoint for applying code suggestions from review comments.
  # Accepts both automated (Copilot/code scanning) and user-authored suggestions
  # in a single batch, committing them together in one commit.
  #
  # This differs from the other "apply suggestions" endpoints:
  # - MutationsController#apply_suggestions (page_data/apply_suggestions route): only handles
  #   user suggestions, expects client-extracted diffs ({ changes: [{ threadId, path, suggestion }] }),
  #   and uses PullRequestReviewComment::ApplySuggestedChange.
  # - AutomatedReviewCommentsController#apply_suggestion (singular): applies a single
  #   automated suggestion at a time.
  #
  # This endpoint resolves suggestions server-side from comment IDs, supports mixed
  # automated + user suggestions, and uses AutomatedReviewComment.apply_suggestions!.
  #
  # Request body: { comments: [{ id: Integer, suggestionIndex?: Integer }], message?: String, expectedHeadOid?: String }
  # - id: PullRequestReviewComment ID
  # - suggestionIndex: required for user comments (picks which ```suggestion block to use),
  #   must be omitted for automated comments
  # - expectedHeadOid: optional SHA (40 or 64 hex chars) of the head commit the client validated
  #   the batch against; used to distinguish head mismatch from other conflict/unprocessable errors
  sig { void }
  def apply_suggestions # rubocop:todo GitHub/UseRestfulActions
    raw_comments = Array(params[:comments])
    return render status: :bad_request, json: { error: "comments must be present" } if raw_comments.empty?

    # Parse comments: each entry is { id:, suggestionIndex?: } (camelCase from JSON)
    parsed_comments = parse_comment_params(raw_comments)
    return render status: :bad_request, json: { error: "comments contains invalid entries" } if parsed_comments.nil?

    pr_comment_ids = parsed_comments.map { |c| c[:id] }.uniq
    return render status: :bad_request, json: { error: "comments contains duplicates" } if pr_comment_ids.length != parsed_comments.length

    pull_request = PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
    return render status: :not_found, json: { error: "Pull request not found" } unless pull_request

    # Build a lookup of suggestion_index by PR comment ID
    suggestion_index_by_id =
      parsed_comments.each_with_object(T.let({}, T::Hash[Integer, T.nilable(Integer)])) do |c, hash|
        hash[c[:id]] = c[:suggestion_index]
      end

    # Fetch all PullRequestReviewComments
    pr_review_comments = PullRequestReviewComment.where(
      id: pr_comment_ids,
      pull_request_id: pull_request.id
    ).includes(:automated_review_comment, :pull_request_review_thread).to_a

    if pr_review_comments.length != pr_comment_ids.length
      return render status: :not_found, json: { error: "One or more review comments not found" }
    end

    # Partition into automated and user comment suggestion items
    items = T.let([], T::Array[ReviewComments::SuggestionItem])

    arc_suggestion_count = 0
    user_suggestion_count = 0
    pr_review_comments.each do |pr_comment|
      suggestion_index = suggestion_index_by_id[pr_comment.id]
      arc = pr_comment.automated_review_comment

      if arc.present?
        # Automated comment — suggestion_index must be nil
        if suggestion_index.present?
          return render status: :bad_request, json: {
            error: "Automated comment #{pr_comment.id} should not have a suggestion_index"
          }
        end

        arc_suggestion_count += 1
        items << ReviewComments::SuggestionItem::AutomatedSuggestionItem.new(arc)
      else
        # User comment — suggestion_index must be present
        if suggestion_index.nil?
          return render status: :bad_request, json: {
            error: "User comment #{pr_comment.id} requires a suggestion_index"
          }
        end

        user_suggestion_count += 1
        items << ReviewComments::SuggestionItem::UserSuggestionItem.new(pr_comment, suggestion_index)
      end
    end

    GitHub.dogstats.distribution("pull_request.suggestions.apply_batch.batch_size", items.count)
    if arc_suggestion_count > 0
      GitHub.dogstats.distribution(
        "pull_request.suggestions.apply_batch.batch_size.by_type",
        arc_suggestion_count,
        tags: ["type:automated"]
      )
    end
    if user_suggestion_count > 0
      GitHub.dogstats.distribution(
        "pull_request.suggestions.apply_batch.batch_size.by_type",
        user_suggestion_count,
        tags: ["type:user"]
      )
    end

    log_context = {
      "gh.pull_request.id": pull_request.id,
      "gh.pull_request.number": pull_request.number,
      "gh.pull_request.head_repository.id": pull_request.head_repository_id,
      "gh.pull_request.base_repository.id": pull_request.base_repository_id,
    }

    truncated_ids = pr_comment_ids.first(30)
    comment_ids_str = truncated_ids.join(",")
    comment_ids_str += " [truncated]" if pr_comment_ids.length > 30

    start = Time.now

    GitHub.logger.info("Applying batch suggestions",
      **log_context,
      "gh.pull_request.apply_batch.batch_suggestion_count": items.length,
      "gh.pull_request.apply_batch.automated_suggestion_count": arc_suggestion_count,
      "gh.pull_request.apply_batch.user_suggestion_count": user_suggestion_count,
      "gh.pull_request.apply_batch.comment_ids": comment_ids_str,
    )

    begin
      AutomatedReviewComment.apply_suggestions!(
        items:,
        user: current_user,
        pull_request:,
        commit_message: params[:message].to_s
      )
    rescue AutomatedReviewComment::ValidationError => e
      GitHub.dogstats.distribution_timing_since("pull_request.suggestions.apply_batch.duration", start, tags: ["outcome:validation_error", "batch_size:#{batch_size_bucket(items.length)}"])
      return render status: :unprocessable_entity, json: { error: e.message.presence || "Unable to apply suggestions." }
    rescue AutomatedReviewComment::InvalidDataError => e
      GitHub.dogstats.distribution_timing_since("pull_request.suggestions.apply_batch.duration", start, tags: ["outcome:error_invalid_data", "batch_size:#{batch_size_bucket(items.length)}"])
      Failbot.report(e, log_context)
      return render status: :unprocessable_entity, json: { error: "Unable to apply suggestions." }
    rescue AutomatedReviewComment::ConflictError => e
      if (mismatch = detect_head_oid_mismatch(pull_request))
        return render_head_oid_mismatch(mismatch, start:, items:, log_context:)
      end

      GitHub.dogstats.distribution_timing_since("pull_request.suggestions.apply_batch.duration", start, tags: ["outcome:error_conflict", "batch_size:#{batch_size_bucket(items.length)}"])
      Failbot.report(e, log_context)
      return render status: :unprocessable_entity, json: { error: e.message.presence || "Unable to apply suggestions." }
    rescue AutomatedReviewComment::UnprocessableError => e
      if e.message.include?("diff is outdated") && (mismatch = detect_head_oid_mismatch(pull_request))
        return render_head_oid_mismatch(mismatch, start:, items:, log_context:)
      end

      GitHub.dogstats.distribution_timing_since("pull_request.suggestions.apply_batch.duration", start, tags: ["outcome:error_unprocessable", "batch_size:#{batch_size_bucket(items.length)}"])
      return render status: :unprocessable_entity, json: { error: e.message.presence || "Unable to apply suggestions." }
    rescue AutomatedReviewComment::PermissionError => e
      GitHub.dogstats.distribution_timing_since("pull_request.suggestions.apply_batch.duration", start, tags: ["outcome:unauthorized", "batch_size:#{batch_size_bucket(items.length)}"])
      return render status: :unauthorized, json: { error: "User is not authorized to apply suggestions." }
    end

    GitHub.dogstats.distribution_timing_since("pull_request.suggestions.apply_batch.duration", start, tags: ["outcome:success", "batch_size:#{batch_size_bucket(items.length)}"])
    GitHub.logger.info("Batch suggestions applied successfully", **log_context)
    render json: { message: "Suggestions were successfully applied." }, status: :ok
  end

  private

  # Parse comments params. Each entry is a hash with:
  # - id: (required) the PullRequestReviewComment ID
  # - suggestionIndex: (optional) index of the suggestion block for user comments
  #
  # Returns an Array of { id: Integer, suggestion_index: Integer|nil } or nil if invalid
  sig { params(raw_comments: T::Array[T.untyped]).returns(T.nilable(T::Array[{ id: Integer, suggestion_index: T.nilable(Integer) }])) }
  def parse_comment_params(raw_comments)
    raw_comments.map do |entry|
      unless entry.is_a?(ActionController::Parameters) || entry.is_a?(Hash)
        return nil
      end

      id = entry[:id] || entry["id"]
      return nil unless id.present?

      suggestion_index = entry[:suggestionIndex] || entry["suggestionIndex"]
      if suggestion_index.present?
        suggestion_index = suggestion_index.to_i
        return nil if suggestion_index < 0
      else
        suggestion_index = nil
      end

      { id: id.to_i, suggestion_index: }
    end
  end

  sig { returns(T.untyped) }
  def content_authorization_required
    authorize_content(:pull_request, action_to_authorize: :apply_suggestions, repo: current_repository)
  end

  # Records timing + a structured warning, then renders the 409 HEAD_OID_MISMATCH response.
  # `mismatch` is the hash returned by detect_head_oid_mismatch ({ expected:, current: }).
  sig { params(mismatch: { expected: String, current: String }, start: Time, items: T::Array[ReviewComments::SuggestionItem], log_context: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
  def render_head_oid_mismatch(mismatch, start:, items:, log_context:)
    GitHub.dogstats.distribution_timing_since("pull_request.suggestions.apply_batch.duration", start, tags: ["outcome:head_mismatch", "batch_size:#{batch_size_bucket(items.length)}"])
    GitHub.logger.warn("Batch suggestion head OID mismatch",
      **log_context,
      "gh.pull_request.apply_batch.expected_head_oid": mismatch[:expected],
      "gh.pull_request.apply_batch.current_head_oid": mismatch[:current],
    )
    render status: :conflict, json: {
      error: "The pull request head has changed since the batch was validated. Please refresh and try again.",
      code: "HEAD_OID_MISMATCH",
    }
  end

  # Validates and checks the expectedHeadOid param against the pull request's current head.
  # Returns nil if no mismatch (or param absent/invalid), or a hash with :expected and :current on mismatch.
  sig { params(pull_request: PullRequest).returns(T.nilable({ expected: String, current: String })) }
  def detect_head_oid_mismatch(pull_request)
    raw = params[:expectedHeadOid]
    return nil unless raw.is_a?(String) && raw.present?

    # OIDs are 40 (SHA-1) or 64 (SHA-256) lowercase hex characters
    return nil unless /\A[0-9a-f]{40}([0-9a-f]{24})?\z/.match?(raw)

    current = pull_request.head_sha
    return nil if raw == current

    { expected: raw, current: current }
  end

  sig { params(count: Integer).returns(String) }
  def batch_size_bucket(count)
    case count
    when 0 then "0"
    when 1 then "1"
    when 2..5 then "2-5"
    when 6..10 then "6-10"
    when 11..20 then "11-20"
    else "20+"
    end
  end

  sig { params(block: T.proc.void).void }
  def set_log_context(&block)
    context = {
      "gh.request.controller": controller_name,
      "gh.request.action": action_name,
      "gh.user.id": current_user.id,
      "gh.repository.id": current_repository.id,
    }
    Failbot.push(context)
    GitHub.logger.with_named_tags(**context) { yield }
  end
end
