# typed: strict
# frozen_string_literal: true

class AutomatedReviewComment < ApplicationRecord::Domain::IssuesPullRequests
  class Error < StandardError; end
  class PermissionError < Error; end
  class ArgumentError < Error; end
  class UnprocessableError < Error; end
  class InvalidDataError < UnprocessableError; end
  class ConflictError < UnprocessableError; end
  class ValidationError < UnprocessableError; end

  class DiffAppliableStatus < T::Enum
    enums do
      Appliable = new
      AlreadyApplied = new
      NotAppliable = new
    end
  end

  RESOLUTION_NOTE_MAX_LENGTH = 280

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain legacy_return_type: true
  belongs_to :pull_request
  belongs_to :pull_request_review_comment

  enum :source, {
    source_code_quality:  0,
    source_code_scanning: 1,
    source_license_compliance: 2,
    source_copilot: 3,
    source_code_scanning_ai: 4,
  }

  enum :severity, {
    severity_none:  0,
    severity_note:  1,
    severity_warning: 2,
    severity_error: 3,
    severity_nit: 4,
    severity_low: 5,
    severity_medium: 6,
    severity_high: 7,
    severity_critical: 8,
  }

  enum :security_severity, {
    security_severity_none:  0,
    security_severity_low: 1,
    security_severity_medium: 2,
    security_severity_high: 3,
    security_severity_critical: 4,
  }

  attribute :title, StringFromBinary.new
  attribute :message, StringFromBinary.new

  enum :suggestion_state, {
    suggestion_state_no_suggestion: 0,
    suggestion_state_pending: 1,
    suggestion_state_present: 2,
    suggestion_state_error: 3,
    suggestion_state_applied: 4,
    suggestion_state_outdated: 5
  }

  sig { returns(String) }
  def suggestion_state
    state = read_attribute(:suggestion_state)

    # Legacy on-read computation for backwards compatibility
    # If the suggestion state is of value `suggestion_state_present`, we check and return if it's outdated
    if state == "suggestion_state_present"
      return "suggestion_state_outdated" if suggestion_outdated?
    end

    state
  end

  # TODO remove this method when automated_review_comment_outdated flag is fully enabled
  sig { params(value: T.any(String, Symbol, Integer)).returns(T.any(String, Symbol, Integer)) }
  def suggestion_state=(value)
    if value.to_s == "suggestion_state_outdated"
      if FeatureFlag.vexi.enabled?(:automated_review_comment_outdated, repository, default: false)
        return write_attribute(:suggestion_state, "suggestion_state_outdated")
      else
        # Legacy behavior: don't store outdated, store as present
        return write_attribute(:suggestion_state, "suggestion_state_present")
      end
    end

    super(value)
  end

  sig { returns(T.nilable(ReviewComments::Suggestion)) }
  def suggestion
    suggestion_hash = read_attribute(:suggestion)
    return nil if suggestion_hash.blank?

    commit_sha = T.let(suggestion_hash["commit_sha"].presence || "", String)
    files = T.let([], T::Array[ReviewComments::Suggestion::File])
    suggestion_hash["files"].each do |file|
      files.append(ReviewComments::Suggestion::File.new(
        path: file["path"],
        diff_content: file["diff_content"]
      ))
    end

    ReviewComments::Suggestion.new(commit_sha:, files:)
  end

  sig { returns(String) }
  def format_body
    comment_body = []
    comment_body << "## #{ title }" if title.present?
    comment_body << "#{ message }" if message.present?
    comment_body.join("\n\n")
  end

  sig { returns(T::Boolean) }
  def fixed?
    fixed_at.present?
  end

  sig { returns(T::Boolean) }
  def dismissed?
    dismissal_reason.present?
  end

  sig { returns(T.nilable(String)) }
  def dismissed_by
    review_thread.resolver&.name
  end

  sig { returns(T::Boolean) }
  def dismissable?
    evaluator_instance = evaluator
    return false if evaluator_instance.nil?

    evaluator_instance.dismissable?
  end

  sig { returns(T::Boolean) }
  def delegated_dismissal_enabled?
    evaluator_instance = evaluator
    return false if evaluator_instance.nil?

    evaluator_instance.delegated_dismissal_enabled?
  end

  sig { params(user: User).returns(T::Boolean) }
  def can_dismiss?(user:)
    if !review_thread.resolved? # the thread could already be resolved if the comment is fixed
      return false unless review_thread.async_can_resolve(user).sync
    end

    evaluator_instance = evaluator
    return false if evaluator_instance.nil?

    evaluator_instance.can_dismiss?(user:, comment: self)
  end

  sig do
    params(
      user: User,
      reason: String,
      resolution_note: T.nilable(String)
    ).void
  end
  def dismiss!(user:, reason:, resolution_note:)
    raise UnprocessableError if dismissed?
    raise PermissionError unless can_dismiss?(user:)

    evaluator_instance = T.must(evaluator)
    evaluator_instance.dismiss(
      comment: self,
      user: user,
      reason: reason,
      resolution_note: resolution_note
    )

    self.dismissal_reason = reason
    self.dismissed_at = Time.now
    save!

    resolve_conversation!(user:)
  end

  sig do
    params(
      user: User,
      reason: String,
      resolution_note: T.nilable(String)
    ).void
  end
  def request_dismissal(user:, reason:, resolution_note:)
    raise UnprocessableError if dismissed?
    raise PermissionError unless can_dismiss?(user:)

    evaluator_instance = T.must(evaluator)
    evaluator_instance.request_dismissal(
      comment: self,
      user: user,
      reason: reason,
      resolution_note: resolution_note
    )
  end

  sig { params(user: User).returns(T::Boolean) }
  def can_reopen?(user:)
    return false unless review_thread.async_can_unresolve(user).sync

    evaluator_instance = evaluator
    return false if evaluator_instance.nil?

    evaluator_instance.can_reopen?(user:)
  end

  sig do
    params(
      user: User,
    ).void
  end
  def reopen!(user:)
    raise UnprocessableError unless dismissed?
    raise PermissionError unless can_reopen?(user:)

    evaluator_instance = T.must(evaluator)
    evaluator_instance.reopen(
      comment: self,
      user: user,
    )

    self.dismissal_reason = nil
    self.dismissed_at = nil
    save!

    unresolve_conversation!(user:) if !fixed? # If it's fixed, the thread should stay resolved
  end

  sig { returns(T::Boolean) }
  def has_suggestion?
    valid_state = suggestion_state.in?(%w[
        suggestion_state_present
        suggestion_state_applied
      ])
    valid_state && suggestion.present?
  end

  sig do
    params(
      items: T::Array[ReviewComments::SuggestionItem],
      user: User,
      pull_request: PullRequest,
      commit_message: String,
    ).void
  end
  def self.apply_suggestions!(items:, user:, pull_request:, commit_message: "")
    raise UnprocessableError.new("No comments provided") if items.empty?

    # Validate all items belong to the PR and have valid suggestions
    items.each { |item| item.validate!(pull_request) }

    # Use head_repository (not the comment's repository) so that ref_to_sha
    # resolves the head branch in the correct repo for cross-fork PRs.
    head_repo = T.must(pull_request.head_repository)

    # Collect diff entries from all items
    all_diff_entries = items.flat_map(&:diff_entries)
    raise UnprocessableError.new("No diff entries found") if all_diff_entries.empty?

    # Collect unique co-author trailers
    co_author_notes = items.filter_map(&:co_author_trailer).uniq.join("\n")

    begin
      suggested_change = DiffEntrySuggestedChange.new(
        repository: head_repo,
        pull_request: pull_request,
        diff_entries: all_diff_entries
      )

      message = if commit_message.present?
        commit_message
      elsif items.length == 1
        T.must(items.first).default_single_commit_message
      elsif items.all? { |i| i.is_a?(ReviewComments::SuggestionItem::AutomatedSuggestionItem) }
        "Applying #{items.length} automated review suggestions"
      else
        "Applying #{items.length} suggestions"
      end

      commit_result = suggested_change.commit_change_for_user(
        author: user,
        current_oid: pull_request.head_sha,
        message:,
        sign: true,
        co_author_note: co_author_notes.presence,
        reflog_data: {
          repo_name: head_repo.name_with_display_owner,
          repo_public: head_repo.public?,
          user_login: user.display_login,
          from: GitHub.context[:from],
          via: "automated review comment batch suggestion",
        }
      )
    rescue ReviewComments::Suggestion::ParseError => e
      # Something went wrong parsing the diff entries from the suggestions
      raise InvalidDataError, e.message
    rescue DiffEntrySuggestedChange::InvalidDataError => e
      raise InvalidDataError, e.message
    rescue DiffEntrySuggestedChange::ConflictError => e
      raise ConflictError, e.message
    rescue DiffEntrySuggestedChange::NotFoundError => e
      raise UnprocessableError, e.message
    rescue DiffEntrySuggestedChange::UnprocessableError => e
      raise UnprocessableError, e.message
    rescue DiffEntrySuggestedChange::ForbiddenError => e
      raise PermissionError, e.message
    end

    commit_oid = commit_result&.first

    # Run post-commit actions for each item
    items.each { |item| item.on_applied(user: user, pull_request: pull_request, commit_sha: commit_oid) }
  end

  sig do
    params(
      user: User,
      commit_message: String
    ).void
  end
  def apply_suggestion!(user:, commit_message: "")
    raise UnprocessableError unless suggestion_state != "suggestions_state_present"
    raise UnprocessableError if suggestion.nil?

    pr_review_comment = T.must(pull_request_review_comment)
    pr = T.must(pull_request)

    begin
      # Use head_repository (not the comment's repository) so that ref_to_sha
      # resolves the head branch in the correct repo for cross-fork PRs.
      suggested_change = DiffEntrySuggestedChange.new(
        repository: T.must(pr.head_repository),
        pull_request: pr,
        diff_entries: suggestion&.diff_entries
      )

      default_commit_message = "Potential fix for pull request finding"
      default_commit_message += ": #{title}" if title.present?
      co_author_note = "Co-authored-by: Copilot Autofix powered by AI <#{pr_review_comment.user&.git_author_email}>"

      suggested_change.commit_change_for_user(
        author: user,
        current_oid: pr.head_sha,
        message: commit_message.presence || default_commit_message,
        sign: true,
        co_author_note: co_author_note,
        reflog_data: {
          repo_name: suggested_change.repository.name_with_display_owner,
          repo_public: suggested_change.repository.public?,
          user_login: user.display_login,
          from: GitHub.context[:from],
          via: "automated review comment suggestion",
        }
      )
    rescue ReviewComments::Suggestion::ParseError => e
      raise InvalidDataError, e.message
    rescue DiffEntrySuggestedChange::InvalidDataError => e
      raise InvalidDataError, e.message
    rescue DiffEntrySuggestedChange::ConflictError => e
      raise ConflictError, e.message
    rescue DiffEntrySuggestedChange::ForbiddenError => e
      raise PermissionError, e.message
    rescue DiffEntrySuggestedChange::NotFoundError => e
      raise UnprocessableError, e.message
    rescue DiffEntrySuggestedChange::UnprocessableError => e
      raise UnprocessableError, e.message
    end

    # Wrap this in a transition together with the actual commit creation ^?
    suggestion_state_applied!
    evaluator&.apply_suggestion(comment: self, user:, pull: pr)

    # Example on how to do the telemetry events:
    # GlobalInstrumenter.instrument("automated_review_comment.suggestion_event", {
    #   repository_id: repository.id,
    #   pull_request_id: pull_request.id,
    #   pull_request_number: pull_request.number,
    #   review_comment_id: review_comment_id,
    #   automated_review_comment_id: id,
    #   type: type,
    #   resource_id: resource_id,
    #   event_type: :SUGGESTION_EVENT_TYPE_APPLIED,
    # })
  end

  sig do
    params(
      user: User,
      feedback: Symbol,
      choices: T::Array[Symbol],
      text_response: T.nilable(String),
    ).void
  end
  def feedback!(user:, feedback:, choices:, text_response:)
    raise ArgumentError, "feedback should be positive or negative" unless [:POSITIVE, :NEGATIVE].include?(feedback)
    raise ArgumentError, "no choice must be selected if feedback is positive" if feedback == :POSITIVE && choices.present?
    raise ArgumentError, "invalid feedback choice" unless choices.all? { |choice| feedback_options_values.include?(choice) }

    payload = {
      repository_id: repository_id,
      automated_review_comment_id: id,
      pull_request_id: pull_request_id,
      pull_request_number: pull_request&.number,
      pull_request_review_comment_id: pull_request_review_comment_id,
      source: read_attribute_before_type_cast(:source),
      source_name: source,
      resource_id: resource_id,
      type: feedback,
      choice: choices,
      text_response: text_response,
    }
    GlobalInstrumenter.instrument("automated_review_comments.suggestion_feedback", payload)

    evaluator&.feedback(comment: self, user:, feedback:, choices:, text_response:)
  end

  sig { void }
  def fix!
    self.fixed_at = Time.now
    save!

    user = T.must(pull_request_review_comment&.user)

    resolve_conversation!(user: user)
  end

  sig { void }
  def unfix!
    self.fixed_at = nil
    save!

    user = T.must(pull_request_review_comment&.user)
    unresolve_conversation!(user: user)
  end

  sig { returns(T::Boolean) }
  def show_feedback_buttons?
    evaluator&.show_feedback_buttons?(comment: self) || false
  end

  sig { returns(T::Array[{ value: String, label: String }]) }
  def feedback_options
    evaluator&.feedback_options || []
  end

  sig { returns(T::Array[Symbol]) }
  def feedback_options_values
    feedback_options.map { |option| option[:value].to_sym }
  end

  sig { returns(T::Boolean) }
  def show_ai_note?
    evaluator&.show_ai_note?(comment: self) || false
  end

  sig { returns(T::Array[{ value: String, label: String, description: String }]) }
  def dismissal_options
    evaluator&.dismissal_options || []
  end

  sig { returns(T::Array[Symbol]) }
  def dismissal_options_values
    dismissal_options.map { |option| option[:value].to_sym }
  end

  sig do
    params(
      pull_request: T.untyped,
      pull_request_review_comment: T.untyped,
      user: T.nilable(User),
    ).returns(T::Boolean)
  end
  def show_apply_changes_button?(pull_request:, pull_request_review_comment:, user:)
    evaluator&.show_apply_changes_button?(ar_comment: self, pull_request:, pull_request_review_comment:, user:) || false
  end

  sig { returns(T.nilable(ReviewComments::DelegatedDismissalRequest)) }
  def current_delegated_dismissal_request
    evaluator&.current_delegated_dismissal_request(comment: self)
  end

  # Public: Checks whether this comment's suggestion diff can be applied at the given commit.
  #
  # Returns a Hash with:
  #   :status - DiffAppliableStatus enum value
  #   :adjusted_diff_files - Array of Suggestion::File when the applied patch differs from the input, nil otherwise
  sig { params(commit_oid: T.nilable(String)).returns({ status: DiffAppliableStatus, adjusted_diff_files: T.nilable(T::Array[ReviewComments::Suggestion::File]) }) }
  def check_diff_appliable(commit_oid)
    return { status: DiffAppliableStatus::NotAppliable, adjusted_diff_files: nil } if suggestion.nil? || repository.nil? || commit_oid.blank?

    sugg = T.must(suggestion)
    repo = T.must(repository)
    diff_patch = build_diff_patch_with_index(sugg, repo)
    return { status: DiffAppliableStatus::NotAppliable, adjusted_diff_files: nil } if diff_patch.blank?

    start = Time.now
    result_tag = "unknown"
    result = begin
      resp = repo.spokes_api.get_diff_appliable(commit_oid:, diff_patch:)

      case resp[:result]
      when SpokesAPI::Types::DiffAppliableResult::Appliable
        result_tag = "appliable"
        { status: DiffAppliableStatus::Appliable, adjusted_diff_files: parse_diff_into_suggestion_files(resp[:resolved_diff_patch]) }
      when SpokesAPI::Types::DiffAppliableResult::AlreadyApplied
        result_tag = "already_applied"
        { status: DiffAppliableStatus::AlreadyApplied, adjusted_diff_files: nil }
      when SpokesAPI::Types::DiffAppliableResult::Conflicts,
           SpokesAPI::Types::DiffAppliableResult::InvalidCommit,
           SpokesAPI::Types::DiffAppliableResult::MalformedPatch
        result_tag = "not_appliable"
        { status: DiffAppliableStatus::NotAppliable, adjusted_diff_files: nil }
      else
        Failbot.report(StandardError.new("Unexpected DiffAppliableResult: #{resp[:result].serialize}"), {
          context: "AutomatedReviewComment#check_diff_appliable",
          automated_review_comment_id: id,
          repository_id:,
          commit_oid:,
        })
        result_tag = "unexpected_result"
        { status: DiffAppliableStatus::NotAppliable, adjusted_diff_files: nil }
      end
    rescue SpokesAPI::Error => e
      result_tag = "error"
      Failbot.report!(e, {
        context: "AutomatedReviewComment#check_diff_appliable",
        "gh.pull_request.comment.id": id,
        "gh.repository.id": repository_id,
        "gh.commit_oid": commit_oid
      })
      { status: DiffAppliableStatus::NotAppliable, adjusted_diff_files: nil }
    rescue UnprocessableError => e
      result_tag = "error"
      Failbot.report(e, {
        context: "AutomatedReviewComment#check_diff_appliable",
        "gh.pull_request.comment.id": id,
        "gh.repository.id": repository_id,
        "gh.commit_oid": commit_oid,
      })
      { status: DiffAppliableStatus::NotAppliable, adjusted_diff_files: nil }
    end

    GitHub.dogstats.distribution_timing_since("automated_review_comment.check_diff_appliable.duration", start, tags: ["status:#{result_tag}"])
    result
  end

  private

  # Builds a unified diff patch string from suggestion files, injecting index lines
  # where missing so that `git apply -3` can perform three-way merges.
  sig { params(sugg: ReviewComments::Suggestion, repo: Repository).returns(String) }
  def build_diff_patch_with_index(sugg, repo)
    log_context = {
      "gh.pull_request.comment.id": id,
      "gh.repository.id": repo.id,
      "gh.pull_request.suggestion.commit_sha": sugg.commit_sha,
      "gh.pull_request.suggestion.file_count": sugg.files.length,
    }

    start = Time.now

    # Identify which files need a blob OID lookup (not new/deleted, no existing index line)
    files_needing_lookup = sugg.files.select do |file|
      !file.diff_content.match?(/^index [0-9a-f]+\.\.[0-9a-f]+/m) &&
        !file.diff_content.include?("--- /dev/null") &&
        !file.diff_content.include?("+++ /dev/null")
    end

    # Batch-resolve all blob OIDs in a single RPC call
    blob_oids = {}
    if files_needing_lookup.any?
      GitHub.dogstats.distribution("automated_review_comment.build_diff_patch.file_count", files_needing_lookup.length)
      selectors = files_needing_lookup.map do |file|
        { by_treeish_and_path: { treeish: { oid: { id: sugg.commit_sha } }, path: { name: file.path } } }
      end

      resp = repo.spokes_api.resolve_objects_by(selectors)
      files_needing_lookup.each_with_index do |file, i|
        item = resp.items[i]
        if item&.object.present?
          blob_oids[file.path] = item.object.oid.id
        else
          # If we find a file that we can't resolve, it's safer to return an empty patch which will be treated
          # as not appliable, rather than risk generating a bad patch.
          GitHub.logger.warn("Failed to resolve blob OID for file in diff patch", **log_context, "gh.file_path": file.path)
          GitHub.dogstats.distribution_timing_since("automated_review_comment.build_diff_patch.duration", start, tags: ["outcome:unresolved_blob"])
          return ""
        end
      end
    end

    diff_patches = sugg.files.map do |file|
      content = file.diff_content
      old_blob_oid = blob_oids[file.path]
      next content if old_blob_oid.nil?

      content.sub("\n--- ", "\nindex #{old_blob_oid[0...7]}..0000000\n--- ")
    end

    GitHub.dogstats.distribution_timing_since("automated_review_comment.build_diff_patch.duration", start, tags: ["outcome:success"])
    diff_patches.map { |p| p.end_with?("\n") ? p : "#{p}\n" }.join
  end

  # Parses a unified diff string (potentially covering multiple files) into
  # an array of Suggestion::File objects using the existing GitHub::Diff::Parser.
  sig { params(adjusted_patch: T.nilable(String)).returns(T.nilable(T::Array[ReviewComments::Suggestion::File])) }
  def parse_diff_into_suggestion_files(adjusted_patch)
    return nil if adjusted_patch.blank?

    parser = GitHub::Diff::Parser.new(adjusted_patch)
    files = T.let([], T::Array[ReviewComments::Suggestion::File])
    parser.each do |entry|
      files << ReviewComments::Suggestion::File.new(
        path: entry.path.to_s,
        diff_content: entry.to_diff_text
      )
    end
    files.presence
  rescue GitHub::Diff::Parser::UnrecognizedText => e
    Failbot.report(e, {
      context: "AutomatedReviewComment#parse_diff_into_suggestion_files",
      "gh.pull_request.comment.id": id,
      "gh.pull_request.id": pull_request_id,
      "gh.repository.id": repository_id,
    })
    raise UnprocessableError, "Failed to parse adjusted diff patch for AutomatedReviewComment #{id}: #{e.message}"
  end

  sig { returns(T::Boolean) }
  def suggestion_outdated?
    if FeatureFlag.vexi.enabled?(:automated_review_comment_outdated, repository, default: false)
      read_attribute(:suggestion_state) == "suggestion_state_outdated"
    else
      current_head_sha = pull_request_review_comment&.pull_request&.head_sha
      suggestion&.commit_sha != current_head_sha
    end
  end

  sig { returns(T.nilable(ReviewComments::AutomatedReviewCommentEvaluator)) }
  def evaluator
    return @evaluator if @evaluator

    @evaluator ||= T.let(nil, T.nilable(ReviewComments::AutomatedReviewCommentEvaluator))
    @evaluator = case source
    when "source_code_quality"
      ReviewComments::Evaluators::CodeQuality.new(T.must(repository))
    when "source_code_scanning"
      ReviewComments::Evaluators::CodeScanning.new(T.must(repository))
    when "source_license_compliance"
      ReviewComments::Evaluators::LicenseCompliance.new(T.must(repository))
    when "source_copilot"
      ReviewComments::Evaluators::Copilot.new(T.must(repository))
    when "source_code_scanning_ai"
      ReviewComments::Evaluators::CodeScanningAi.new(T.must(repository))
    else
      nil
    end
  end

  sig do
    params(
      user: User
    ).void
  end
  def resolve_conversation!(user:)
    review_thread.resolve(resolver: user)
  end

  sig do
    params(
      user: User
    ).void
  end
  def unresolve_conversation!(user:)
    review_thread.unresolve(unresolver: user)
  end

  sig { returns(PullRequestReviewThread) }
  def review_thread
    T.must(pull_request_review_comment&.pull_request_review_thread)
  end
end
