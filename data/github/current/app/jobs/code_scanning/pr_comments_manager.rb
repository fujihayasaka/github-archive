# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

# PrCommentsManager is used by CreateCodeScanningAnnotationsJob
# to create, update, and resolve comments on Pull Requests
class CodeScanning::PrCommentsManager
  include PullRequestAnalyses::ReviewCommentsHelper

  MAX_REVIEW_COMMENTS = 20

  sig do
    params(
      pull_request: PullRequest,
      check_run: CheckRun,
      head_commit_oid: String,
      alerts: T::Array[Turboscan::Proto::DiffedAlert],
      bot: User
    ).void
  end
  def initialize(pull_request:, check_run:, head_commit_oid:, alerts:, bot:)
    @pull_request = pull_request
    @check_run = check_run
    @head_commit_oid = head_commit_oid
    @alerts = alerts
    @bot = bot

    @total_alerts = T.let(0, Integer)
    @alerts_in_the_diff = T.let(0, Integer)
    @alerts_out_the_diff = T.let(0, Integer)

    @dfa_comment_posted = T.let(false, T::Boolean)
  end

  sig { void }
  def manage_comments
    post_new_comments
    manage_fixed_comments
    manage_unfixed_comments
  end

  sig { void }
  def post_new_comments
    return if @alerts.empty?
    @total_alerts = @alerts.count

    if @head_commit_oid != @pull_request.head_sha
      log(
        "Skipping review comment creation because analyzed commit is not the PR's head",
        "gh.pull_request.head_sha" => @pull_request.head_sha
      )
      return
    end

    log("Creating pull request review comments.",
      "gh.code_scanning.alert.count" => @total_alerts,
    )

    if @pull_request.issue&.locked? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      log("Pull request is locked - aborting review comment creation.")
      return
    end

    pull_comparison = find_pull_comparison(@pull_request, @head_commit_oid)
    if pull_comparison.nil?
      log("pull_comparison is nil - aborting review comment creation.",
        "gh.pull_request.merge_base" => @pull_request.merge_base)
      return
    end

    # TODO: use the link from the PR like code scanning review comments when moving out of the KV
    # existing_cs_review_comment_alert_numbers = Set.new(pull_request.code_scanning_review_comments.map(&:alert_number))
    existing_comments_alert_numbers = AutomatedReviewComment.where(repository: @pull_request.repository, pull_request: @pull_request, source: :source_code_scanning)
        .map { |comment| comment.resource_id.to_i }
    existing_comments_alert_numbers = Set.new(existing_comments_alert_numbers)

    # If there were previously more than MAX_REVIEW_COMMENTS alerts, we won't have created review comments for each
    # of them (just the summary comment). Therefore, those alerts will show up as new here even if they're not new.
    # This is correct behaviour because if there are now fewer than MAX_REVIEW_COMMENTS alerts, we want to create
    # individual comments for the alerts.
    new_alerts = @alerts.reject do |alert|
      existing_comments_alert_numbers.include?(alert.number)
    end

    alert_file_diff = pull_comparison.diffs
    alert_file_diff.add_paths(@alerts.map { |alert| alert.location&.file_path }, side: :b)

    new_alerts_in_the_diff_with_comment_start_line = T.let({}, T::Hash[Turboscan::Proto::DiffedAlert, Integer])
    new_alerts.each do |alert|
      comment_start_line = comment_start_line(alert, alert_file_diff)

      if comment_start_line
        new_alerts_in_the_diff_with_comment_start_line[alert] = comment_start_line
      else
        log("Skipping alert review comment creation when outside the diff.",
          "gh.code_scanning.alert.file_path" => alert.location&.file_path,
          "gh.code_scanning.alert.number" => alert.number)
      end
    end

    @alerts_in_the_diff = new_alerts_in_the_diff_with_comment_start_line.count
    @alerts_out_the_diff = @total_alerts - @alerts_in_the_diff

    if new_alerts_in_the_diff_with_comment_start_line.empty?
      log("No new review comments to be created.")
      return
    end

    log("New alerts found in diff.",
      "gh.code_scanning.diff.alerts.in" => new_alerts_in_the_diff_with_comment_start_line.count,
    )
    post_automated_review(new_alerts_in_the_diff_with_comment_start_line, alert_file_diff)
  end

  sig do
    params(
      alerts_with_comment_start_line: T::Hash[Turboscan::Proto::DiffedAlert, Integer],
      diff: GitHub::Diff,
    ).void
  end
  def post_automated_review(alerts_with_comment_start_line, diff)
    review = @pull_request.build_automated_variant_review do |r|
      r.user = @bot
      r.head_sha = @head_commit_oid
      r.merge_base_sha = @pull_request.find_best_merge_base_sha(head_sha: @head_commit_oid)
    end

    if alerts_with_comment_start_line.count > MAX_REVIEW_COMMENTS
      return handle_too_many_alerts(review)
    end

    # construct the review comments and code scanning review comments outside the transaction
    # to avoid a slow running transaction
    review_comment_pairs = T.let({}, T::Hash[PullRequestReviewComment, AutomatedReviewComment])
    alerts_with_comment_start_line.each do |(alert, start_line)|
      automated_review_comment = build_automated_review_comment(alert)
      review_comment = build_review_comment(review, diff, alert, start_line, automated_review_comment.format_body)

      if review_comment
        review_comment_pairs[review_comment] = automated_review_comment
      end
    end

    # then in a transaction we save and connect them
    PullRequestReview.transaction do
      comments_created = T.let(false, T::Boolean)
      review_comment_pairs.each do |review_comment, automated_review_comment|
        if review_comment.save
          comments_created = true
          automated_review_comment.pull_request_review_comment_id = review_comment.id
          automated_review_comment.save!
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

    @dfa_comment_posted = true
  end

  sig do
    params(
      alert: Turboscan::Proto::DiffedAlert,
    ).returns(AutomatedReviewComment)
  end
  def build_automated_review_comment(alert)
    severity = case alert.rule_severity
    when "NOTE"
      :severity_note
    when "WARNING"
      :severity_warning
    when "ERROR"
      :severity_error
    else
      :severity_note
    end

    AutomatedReviewComment.new(
      repository_id: @pull_request.repository_id,
      pull_request_id: @pull_request.id,
      source: :source_code_scanning,
      resource_id: alert.number.to_s,
      title: "#{@check_run.code_scanning_tool_name} / #{alert.rule_short_description}",
      message: alert.message_text.to_s + "\n\n" + show_more_details_link(alert),
      severity: severity,
    )
  end

  sig do
    params(
      review: PullRequestReview,
      diff: GitHub::Diff,
      alert: Turboscan::Proto::DiffedAlert,
      start_line: Integer,
      body: String,
    ).returns(T::nilable(PullRequestReviewComment))
  end
  def build_review_comment(review, diff, alert, start_line, body)
    attributes = {
      user: review.user,
      diff: diff,
      body: body,
      path: alert.location&.file_path,
      line: alert.location&.end_line,
      side: :right,
    }.merge(extra_comment_attributes(alert.location&.start_line, alert.location&.end_line, start_line))

    review.build_thread.build_first_comment(**T.unsafe(attributes))
  end

  sig do
    params(
      alert: Turboscan::Proto::DiffedAlert,
    ).returns(String)
  end
  def show_more_details_link(alert)
    "[Show more details](#{UrlHelpers.repository_code_scanning_result_url(
        host: GitHub.url,
        user_id: @pull_request.repository&.owner_display_login,
        repository: @pull_request.repository,
        number: alert.number,
      )})"
  end

  sig do
    params(
      review: PullRequestReview
    ).void
  end
  def handle_too_many_alerts(review)
    tool_name = @check_run.code_scanning_tool_name

    pr_files_path = UrlHelpers.pull_request_files_path(@pull_request.repository&.owner_display_login, @pull_request.repository&.name, @pull_request.number)
    review_body_message = "#{tool_name} found more than #{MAX_REVIEW_COMMENTS} potential problems in the proposed changes. Check the [Files changed](#{pr_files_path}) tab for more details."

    if @pull_request.reviews.select { |r| r.body == review_body_message }.any?
      log("There's already a review saying this tool found many alerts, no need to create a new one",
        "gh.code_scanning.tool" => tool_name)
      return
    end

    review.body = review_body_message
    ActiveRecord::Base.connected_to(role: :writing) { review.comment! }
    log "Too many alerts to report, skip creating review comments but add a body"
  end

  sig { void }
  def manage_fixed_comments
    # TODO
  end

  sig { void }
  def manage_unfixed_comments
    # TODO
  end

  sig { params(msg: String, attributes: T::Hash[T.untyped, T.untyped]).void }
  def log(msg, attributes = {})
    calling_method = caller_locations(1, 1)&.first&.base_label
    logger_attributes = {
      "code.namespace" => "CreateCodeScanningAnnotationsJob",
      "code.function" => calling_method,
      "gh.repo.id" => @pull_request.repository_id,
      "gh.check_run.id" => @check_run.id,
      "gh.pull_request.id" => @pull_request.id,
      "gh.pull_request.head_sha" => @head_commit_oid,
    }.merge(**attributes)
    if attributes.has_key?(:exception)
      GitHub.logger.error(msg, logger_attributes)
    else
      GitHub.logger.info(msg, logger_attributes)
    end
  end
end
