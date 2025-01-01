# typed: true
# frozen_string_literal: true

# CommentCreator is used by CreateCodeScanningAnnotationsJob
# to create comments on Pull Requests, as well as creating
# the necessary CodeScanningReviewComment objects
class CodeScanning::CommentCreator
  attr_reader :pull_request, :check_run, :head_commit_oid, :code_scanning_check_suite, :total_alerts, :alerts_in_the_diff, :alerts_out_the_diff, :onboarding_comment_posted, :dfa_comment_posted

  MAX_REVIEW_COMMENTS = 20

  def initialize(pull_request:, check_run:, head_commit_oid:, code_scanning_check_suite:)
    @pull_request = pull_request
    @check_run = check_run
    @head_commit_oid = head_commit_oid
    @code_scanning_check_suite = code_scanning_check_suite

    @total_alerts = 0
    @alerts_in_the_diff = 0
    @alerts_out_the_diff = 0

    @onboarding_comment_posted = false
    @dfa_comment_posted = false
  end

  # This method takes care of creating review comments for newly introduced alerts that are located in the PR diff.
  # When the alert location spans multiple lines and is not contained withing a single diff hunk, we recompute a
  # suitable range of lines for the comment to make sure it is contained within a single diff hunk.
  def create_review_comments(alerts, reviewer)
    return if alerts.empty?
    @total_alerts = alerts&.count

    if head_commit_oid != pull_request.head_sha
      log(
        "Skipping review comment creation because analyzed commit is not the PR's head",
        "gh.pull_request.head_sha" => pull_request.head_sha
      )
      return
    end

    log("Creating pull request review comments.",
      "gh.code_scanning.alert.count" => alerts&.count,
    )

    if pull_request.issue.locked?
      log "Pull request is locked - aborting review comment creation."
      return
    end

    pull_comparison = find_pull_comparison(head_commit_oid)
    if pull_comparison.nil?
      log("pull_comparison is nil - aborting review comment creation.",
        "gh.pull_request.merge_base" => pull_request.merge_base)
      return
    end
    diffs = pull_comparison.diffs
    diff_stats = CodeScanning::DiffStatus.new(diffs).stats_tags
    alert_file_diff = T.let(nil, T.nilable(GitHub::Diff))

    if pull_request.repository.code_scanning_dfa_alert_file_diff_enabled?
      alert_file_diff = diffs.only_params.tap do |d|
        d.add_paths(alerts.map { |alert| alert.location.file_path }, side: :b)
      end
      diffs = alert_file_diff
    end

    existing_cs_review_comment_alert_numbers = Set.new(pull_request.code_scanning_review_comments.map(&:alert_number))
    # If there were previously more than MAX_REVIEW_COMMENTS alerts, we won't have created review comments for each
    # of them (just the summary comment). Therefore, those alerts will show up as new here even if they're not new.
    # This is correct behaviour because if there are now fewer than MAX_REVIEW_COMMENTS alerts, we want to create
    # individual comments for the alerts.
    new_alerts = alerts.reject do |alert|
      existing_cs_review_comment_alert_numbers.include?(alert.number)
    end
    new_alerts_in_the_diff_with_comment_start_line = new_alerts.each_with_object({}) do |alert, h|
      comment_start_line = Scientist.run "code-scanning-dfa-alert-file-diff" do |e|
        e.context(
          diff_stats: diff_stats,
          repository_id: pull_request.repository_id,
          pull_request_id: pull_request.id,
          code_scanning_dfa_alert_file_diff_enabled: pull_request.repository.code_scanning_dfa_alert_file_diff_enabled?,
        )

        e.before_run do
          alert_file_diff ||= diffs.only_params.tap do |d|
            d.add_paths(alerts.map { |alert| alert.location.file_path }, side: :b)
          end
          alert_file_diff.load_diff unless alert_file_diff.loaded?
        end

        e.use { comment_start_line_for_alert(alert, diffs) }
        e.try { comment_start_line_for_alert(alert, alert_file_diff) }

        e.ignore do |control, candidate|
          control.nil? && !candidate.nil?
        end
      end

      if comment_start_line
        h[alert] = comment_start_line
      else
        log("Skipping alert review comment creation when outside the diff.",
          "gh.code_scanning.alert.file_path" => alert.location.file_path,
          "gh.code_scanning.alert.number" => alert.number)
      end
    end
    @alerts_in_the_diff = new_alerts_in_the_diff_with_comment_start_line.count
    @alerts_out_the_diff = total_alerts - alerts_in_the_diff

    if new_alerts_in_the_diff_with_comment_start_line.empty?
      log "No new review comments to be created."
    else
      log("New alerts found in diff.",
        "gh.code_scanning.diff.alerts.in" => new_alerts_in_the_diff_with_comment_start_line.count,
      )
      review = pull_request.build_code_scanning_variant_review do |r|
        r.user = reviewer
        r.head_sha = head_commit_oid
        r.merge_base_sha = pull_request.find_best_merge_base_sha(head_sha: head_commit_oid)
      end
      populate_review(review, new_alerts_in_the_diff_with_comment_start_line, pull_comparison, check_run&.code_scanning_tool_name)
      @dfa_comment_posted = true
    end
  end

  # We don't want the comment's location to escape a single diff hunk, so we may have to compute a new start_line for it
  # so the final location is the intersection of the alert's location with the diff hunk that contains the end_line.
  # This method is public so it can be tested.
  def comment_start_line_for_alert(alert, diffs)
    diff_entry = diffs.with_path(alert.location.file_path)
    return nil unless diff_entry.present?

    start_line = alert.location.start_line # we shuld never end up with this not having changed value I think?
    new_hunk = T.let(false, T::Boolean)
    diff_entry.each_line do |line|
      next if line.right < alert.location.start_line

      break if line.right > alert.location.end_line # should we ever actually hit here??

      # we are in a new hunk, we need this to move the start_line
      if line.hunk?
        new_hunk = true
        next
      end
      if new_hunk && line.right
        start_line = line.right
        new_hunk = false
        next
      end

      if line.type == :addition && alert.location.end_line == line.right
        return start_line
      end
    end

    nil
  end

  def create_onboarding_comment(
    reviewer:,
    body:
  )
    # We always mark the onboarding_comment_posted as true to avoid data inconsistencies when rerunning the CreateCodeScanningJob
    # We don't want to post the same comment more than once in order to not spam the users and annoy them,
    # but we want to track whether we have an onboarding comment to post or not
    @onboarding_comment_posted = true

    has_onboarding_comment_key = "code_scanning.#{pull_request.repository_id}.#{pull_request.number}.has_onboarding_comment"
    ActiveRecord::Base.connected_to(role: :reading) do
      # rubocop:todo GitHub/DoNotUseGlobalKv
      if GitHub.kv.exists(has_onboarding_comment_key).value!
        # rubocop:enable GitHub/DoNotUseGlobalKv
        log("Pull request already has onboarding comment - aborting creating new comment.",
          "gh.code_scanning.analysis.tool_name" => check_run&.code_scanning_tool_name,
        )
        return
      end

      if pull_request.issue.locked?
        log("Pull request is locked - aborting creating onboarding comment.")
        return
      end
    end

    begin
      pull_request.issue.comments.create!(user: reviewer, body:)
    rescue ActiveRecord::RecordInvalid => e
      log("Failed to create onboarding comment.",
        "gh.code_scanning.analysis.tool_name" => check_run&.code_scanning_tool_name,
        :exception => e,
      )
    end
    ActiveRecord::Base.connected_to(role: :writing) do
      GitHub.kv.set(has_onboarding_comment_key, "", expires: 1.year.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
    end
  end

  # This method is only intended to be used when the pr_fixed_alerts feature flag is enabled. The messaging it uses is
  # not intended for consumption by non-Hubbers. It is expected that fixed alerts would only be returned by turboscan
  # when that feature flag is enabled anyway, but callers should still check it for safety.
  def create_fixed_alerts_comment(
    reviewer:,
    fixed_count:,
    check_run:
  )
    has_fixed_alert_comment_key = "code_scanning.#{pull_request.repository_id}.#{pull_request.number}.has_fixed_alert"
    return if fixed_count.zero?
    return if GitHub.kv.exists(has_fixed_alert_comment_key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
    return if pull_request.issue.locked?
    return unless check_run&.code_scanning_tool_name

    body = <<~EOS
      :tada: Welcome to a Code Scanning beta of fixed alerts! :tada:

      You may have fixed #{fixed_count} #{'alert'.pluralize(fixed_count)} in this pull request. Check out the [#{check_run&.code_scanning_tool_name} check run](#{check_run.permalink(pull: pull_request)}) for more details.

      _To avoid overloading you this message will only be posted once a week on each pull request._
    EOS

    begin
      pull_request.issue.comments.create!(user: reviewer, body:)
    rescue ActiveRecord::RecordInvalid => e
      log("Failed to create fixed alerts comment.",
        "gh.code_scanning.analysis.tool_name" => check_run&.code_scanning_tool_name,
        :exception => e,
      )
    end
    ActiveRecord::Base.connected_to(role: :writing) do
      GitHub.kv.set(has_fixed_alert_comment_key, "", expires: 1.week.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
    end

  end

  def log_summary
    GitHub.logger.info(
      "Comment creator summary",
      "code.namespace" => "CreateCodeScanningAnnotationsJob",
      "gh.repo.id" => pull_request.repository_id,
      "gh.check_run.id" => check_run&.id,
      "gh.pull_request.id" => pull_request&.id,
      "gh.code_scanning.alert.count" => total_alerts,
      "gh.code_scanning.diff.alerts.in" => alerts_in_the_diff,
      "gh.code_scanning.diff.alerts.out" => alerts_out_the_diff,
      "gh.code_scanning.onboarding_comment.posted" => onboarding_comment_posted,
      "gh.code_scanning.dfa_comment.posted" => dfa_comment_posted,
    )
  end

  private

  def populate_review(review, alerts_with_comment_start_line, pull_comparison, tool_name)
    return handle_too_many_alerts(tool_name, review) if alerts_with_comment_start_line.count > MAX_REVIEW_COMMENTS

    # construct the review comments and code scanning review comments outside the transaction
    # to avoid a slow running transaction
    review_comment_pairs = alerts_with_comment_start_line.each_with_object(Hash.new) do |(alert, start_line), h|
      review_comment = build_review_comment(review, pull_comparison, alert, start_line)
      code_scanning_review_comment = build_code_scanning_review_comment(alert, tool_name)
      h[review_comment] = code_scanning_review_comment
    end
    # then in a transaction we save and connect them
    PullRequestReview.transaction do
      comments_created = T.let(false, T::Boolean)
      review_comment_pairs.each do |review_comment, code_scanning_review_comment|
        if review_comment.save
          comments_created = true
          code_scanning_review_comment.pull_request_review_comment_id = review_comment.id
          code_scanning_review_comment.save!
        else
          filtered_errors = review_comment.errors.filter { |error| !(error.attribute == :"pull_request_review_thread.end_commit_oid" && error.type == "is not part of the pull request") }
          if filtered_errors.length > 0
            log("Validation errors while saving review comment",
              "gh.code_scanning.validation_errors" => filtered_errors,
            )
            raise ActiveRecord::RecordInvalid.new(review_comment)
          end
        end
      end
      # this is the same as when a manual review hits comment
      # (or 'approve' or 'request changes' (which conceivably we might want to do))
      review.comment! if comments_created
    end
  end

  def handle_too_many_alerts(tool_name, review)
    review_body_message = many_alerts_review_message(tool_name)
    if pull_request.reviews.select { |r| r.body == review_body_message }.any?
      log("There's already a review saying this tool found many alerts, no need to create a new one",
        "gh.code_scanning.tool" => tool_name)
      return
    end
    review.body = review_body_message
    ActiveRecord::Base.connected_to(role: :writing) { review.comment! }
    log "Too many alerts to report, skip creating review comments but add a body"
  end

  def log(msg, attributes = {})
    # Fetch the name of the method that called this method.
    # caller_locations(1, 1) means only one is retrieved, since we only want the caller.
    # We never expect it to be missing, but we're coding defensively just in case it is
    # - you don't want logging code to fail!
    calling_method = caller_locations(1, 1)&.first&.base_label
    logger_attributes = {
      "code.namespace" => "CreateCodeScanningAnnotationsJob",
      "code.function" => calling_method,
      "gh.repo.id" => pull_request.repository_id,
      "gh.check_run.id" => check_run&.id,
      "gh.pull_request.id" => pull_request&.id,
      "gh.pull_request.head_sha" => head_commit_oid,
    }.merge(**attributes)
    if attributes.has_key?(:exception)
      GitHub.logger.error(msg, logger_attributes)
    else
      GitHub.logger.info(msg, logger_attributes)
    end

  end

  def many_alerts_review_message(tool_name)
    pr_files_path = UrlHelpers.pull_request_files_path(pull_request.repository.owner_display_login, pull_request.repository.name, pull_request.number)
    "#{tool_name} found more than #{MAX_REVIEW_COMMENTS} potential problems in the proposed changes. Check the [Files changed](#{pr_files_path}) tab for more details."
  end

  def find_pull_comparison(commit_oid)
    PullRequest::Comparison.find(
      pull: pull_request,
      start_commit_oid: pull_request.merge_base,
      end_commit_oid: commit_oid,
      base_commit_oid: pull_request.merge_base,
    )
  end

  def build_review_comment(review, pull_comparison, alert, start_line = nil)
    thread = review.build_thread

    attributes = {
      user: review.user,
      diff: pull_comparison.diffs,
      body: CodeScanningReviewComment.format_body(alert: alert, repository: pull_comparison.repository),
      path: alert.location.file_path,
      line: alert.location.end_line,
      side: :right,
    }

    if alert.location.start_line != alert.location.end_line
      attributes.merge!(
        start_line: start_line || alert.location.start_line,
        start_side: :right,
      )
    end

    thread.build_first_comment(**attributes)
  end

  def build_code_scanning_review_comment(alert, tool_name)
    CodeScanningReviewComment.new({
      repository_id: pull_request.repository_id,
      pull_request_id: pull_request.id,
      alert_number: alert.number,
      warning_level: CheckAnnotation.annotation_level_for_code_scanning_annotation(alert.security_severity, alert.rule_severity),
      tool_name: tool_name,
      alert_title: alert.rule_short_description, # TODO move these out to methods so annotations are also created with the same methods
      # we wont be able to differentiate between alerts with the message `-` and alerts with no message
      # it might be better to use the empty string to mean 'no alert message' to make it easy to render a fallback
      # but annotations does the same thing, so we would want to change that too
      alert_message: alert.message_text.presence || "-",
    })
  end
end
