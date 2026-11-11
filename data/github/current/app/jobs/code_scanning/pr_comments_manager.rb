# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

# PrCommentsManager is used by CreateCodeScanningAnnotationsJob
# to create, update, and resolve comments on Pull Requests
class CodeScanning::PrCommentsManager
  include PullRequestAnalyses::ReviewCommentsHelper
  include GitHub::Memoizer

  MAX_REVIEW_COMMENTS = 20

  sig do
    params(
      pull_request: PullRequest,
      check_run: CheckRun,
      head_commit_oid: String,
      merge_commit_oid: T.nilable(String),
      alerts: T::Array[Turboscan::Proto::DiffedAlert],
      bot: User
    ).void
  end
  def initialize(pull_request:, check_run:, head_commit_oid:, merge_commit_oid:, alerts:, bot:)
    @pull_request = pull_request
    @check_run = check_run
    @head_commit_oid = head_commit_oid
    @merge_commit_oid = merge_commit_oid
    @alerts = alerts
    @bot = bot
    @prefer_security_severity = T.let(
      FeatureFlag.vexi.enabled?(:code_scanning_arc_prefer_security_severity, @pull_request.repository, default: false),
      T::Boolean,
    )

    @total_alerts = T.let(0, Integer)
    @alerts_in_the_diff = T.let(0, Integer)
    @alerts_out_the_diff = T.let(0, Integer)

    @dfa_comment_posted = T.let(false, T::Boolean)
  end

  sig { void }
  def manage_comments
    post_new_comments
    fixed_comments = manage_fixed_comments
    unfixed_comments = manage_unfixed_comments
    notify_affected_pull_request_reviews(fixed_comments + unfixed_comments)
  end

  sig { void }
  def post_new_comments
    log("Posting new code scanning review comments")
    if @alerts.empty?
      log("No alerts to create code scanning review comments for")
      return
    end

    @total_alerts = @alerts.count

    if @head_commit_oid != @pull_request.head_sha
      log(
        "Skipping review comment creation because analyzed commit is not the PR's head",
        "gh.pull_request.head_sha" => @pull_request.head_sha
      )
      return
    end

    log("Creating pull request review comments",
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

    # Batch-fetch annotation data to get has_code_paths for all new alerts
    code_paths_by_alert_number = fetch_code_paths_by_alert_number(alerts_with_comment_start_line.keys.map(&:number))

    # construct the review comments and code scanning review comments outside the transaction
    # to avoid a slow running transaction
    review_comment_pairs = T.let({}, T::Hash[PullRequestReviewComment, AutomatedReviewComment])
    alerts_with_comment_start_line.each do |(alert, start_line)|
      automated_review_comment = build_automated_review_comment(alert, has_code_paths: code_paths_by_alert_number[alert.number] || false)
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
      has_code_paths: T::Boolean,
    ).returns(AutomatedReviewComment)
  end
  def build_automated_review_comment(alert, has_code_paths: false)
    title = CodeScanning::AutomatedReviewCommentTitle.build(
      tool_name: @check_run.code_scanning_tool_name.to_s,
      rule_short_description: alert.rule_short_description.to_s,
    )
    security_severity = find_security_severity(alert)
    severity = if @prefer_security_severity
      security_severity == :security_severity_none ? find_severity(alert) : :severity_none
    else
      find_severity(alert)
    end

    AutomatedReviewComment.new(
      repository_id: @pull_request.repository_id,
      pull_request_id: @pull_request.id,
      source: :source_code_scanning,
      resource_id: alert.number.to_s,
      title: title,
      message: alert.message_text.to_s + "\n\n" + show_more_details_link(alert),
      severity:,
      security_severity:,
      suggestion_state: :suggestion_state_no_suggestion,
      metadata: { "has_code_paths" => has_code_paths },
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

  sig { returns(T::Array[AutomatedReviewComment]) }
  def manage_fixed_comments
    log("Managing fixed code scanning review comments")
    # Get all unfixed code scanning automated review comments, indexed by alert number
    unfixed_comments_by_alert_number = AutomatedReviewComment.where(
      repository: @pull_request.repository,
      pull_request: @pull_request,
      source: :source_code_scanning,
      fixed_at: nil
    ).index_by { |comment| comment.resource_id.to_i }

    if unfixed_comments_by_alert_number.empty?
      log("No code scanning comments to fix",
        "gh.code_scanning.fixed.comment.count" => 0)
      return []
    end

    log("Found unfixed code scanning review comments",
      "gh.code_scanning.unfixed.comment.count" => unfixed_comments_by_alert_number.length,
    )

    # Query Turboscan API to get current alert status
    # We can't assume missing alerts are fixed (race condition with other tools/configs)
    annotation_results = GitHub::Turboscan.annotations(
      repository_id: @pull_request.repository_id,
      numbers: unfixed_comments_by_alert_number.keys,
      merge_commit_oid: @merge_commit_oid,
      head_commit_oid: @head_commit_oid,
    )&.data&.results || []

    # Split annotation results into fixed and unfixed in one pass
    fixed_results, unfixed_results = annotation_results.partition { |ar| ar.result.most_recent_instance&.is_fixed }
    fixed_alert_numbers = fixed_results.filter_map { |ar| ar.result&.number }
    unfixed_alert_numbers = unfixed_results.filter_map { |ar| ar.result&.number }

    # Refresh has_code_paths metadata only for comments that remain unfixed
    unfixed_alert_numbers.each do |alert_number|
      comment = unfixed_comments_by_alert_number[alert_number]
      next unless comment

      has_code_paths = unfixed_results.find { |ar| ar.result&.number == alert_number }&.has_code_paths

      update_comment_has_code_paths_metadata(comment, has_code_paths)
    end

    log("Found code scanning alerts to fix",
      "gh.code_scanning.fixed.alert.count" => fixed_alert_numbers.length,
    )
    comments_to_fix = fixed_alert_numbers.filter_map do |alert_number|
      unfixed_comments_by_alert_number[alert_number]
    end

    comments_to_fix.each(&:fix!)
  end

  sig { returns(T::Array[AutomatedReviewComment]) }
  def manage_unfixed_comments
    log("Managing unfixed code scanning review comments")

    if @alerts.empty?
      log("No alerts to manage unfixed code scanning review comments for")
      return []
    end

    alert_numbers = @alerts.map { |alert| alert.number.to_s }
    comments_to_unfix = AutomatedReviewComment.where(
      repository: @pull_request.repository,
      pull_request: @pull_request,
      source: :source_code_scanning,
      resource_id: alert_numbers,
    ).where.not(fixed_at: nil).to_a

    if comments_to_unfix.empty?
      log("No code scanning review comments to unfix",
        "gh.code_scanning.comments_to_unfix.count" => 0,
      )
      return []
    end

    log("Found code scanning review comments to unfix",
      "gh.code_scanning.comments_to_unfix.count" => comments_to_unfix.length,
    )

    # Refresh has_code_paths metadata for comments being unfixed
    code_paths_by_alert_number = fetch_code_paths_by_alert_number(comments_to_unfix.map { |c| c.resource_id.to_i })
    comments_to_unfix.each do |comment|
      alert_number = comment.resource_id.to_i
      has_code_paths = code_paths_by_alert_number[alert_number]
      update_comment_has_code_paths_metadata(comment, has_code_paths)
    end

    comments_to_unfix.each(&:unfix!)
  end

  private

  sig { params(alert_numbers: T::Array[Integer]).returns(T::Hash[Integer, T::Boolean]) }
  def fetch_code_paths_by_alert_number(alert_numbers)
    return {} if alert_numbers.empty?

    annotation_results = GitHub::Turboscan.annotations(
      repository_id: @pull_request.repository_id,
      numbers: alert_numbers,
      merge_commit_oid: @merge_commit_oid,
      head_commit_oid: @head_commit_oid,
    )&.data&.results || []

    annotation_results.each_with_object({}) do |annotation_result, hash|
      hash[annotation_result.result.number] = annotation_result.has_code_paths || false
    end
  end

  sig { params(comments: T::Array[AutomatedReviewComment]).void }
  def notify_affected_pull_request_reviews(comments)
    review_comment_ids = comments.map(&:pull_request_review_comment_id).uniq
    review_ids = PullRequestReviewComment.where(id: review_comment_ids).distinct.pluck(:pull_request_review_id)
    unique_reviews = PullRequestReview.where(id: review_ids).to_a

    log(
      "Notifying affected pull request reviews",
      "gh.code_scanning.notify.comments.count" => comments.length,
      "gh.code_scanning.notify.review_comments.count" => review_comment_ids.length,
      "gh.code_scanning.notify.unique_reviews.count" => unique_reviews.length,
      "gh.code_scanning.notify.comments_missing_review_comment.count" => comments.length - review_comment_ids.length,
    )

    unique_reviews.each(&:notify_socket_subscribers)
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
      "gh.pull_request.merge_sha" => @merge_commit_oid,
    }.merge(**attributes)
    if attributes.has_key?(:exception)
      GitHub.logger.error(msg, logger_attributes)
    else
      GitHub.logger.info(msg, logger_attributes)
    end
  end

  sig { params(alert: Turboscan::Proto::DiffedAlert).returns(Symbol) }
  def find_severity(alert)
    rule_severity = alert.rule_severity
    rule_severity_as_sym = rule_severity.is_a?(Integer) ? Turboscan::Proto::RuleSeverity.lookup(rule_severity) : rule_severity

    case rule_severity_as_sym
    when :NOTE
      :severity_note
    when :WARNING
      :severity_warning
    when :ERROR
      :severity_error
    else
      :severity_none
    end
  end

  sig { params(alert: Turboscan::Proto::DiffedAlert).returns(Symbol) }
  def find_security_severity(alert)
    security_severity = alert.security_severity
    security_severity_as_sym = security_severity.is_a?(Integer) ? Turboscan::Proto::SecuritySeverity.lookup(security_severity) : security_severity

    case security_severity_as_sym
    when :LOW
      :security_severity_low
    when :MEDIUM
      :security_severity_medium
    when :HIGH
      :security_severity_high
    when :CRITICAL
      :security_severity_critical
    else
      :security_severity_none
    end
  end

  sig { params(comment: AutomatedReviewComment, has_code_paths: T.nilable(T::Boolean)).void }
  def update_comment_has_code_paths_metadata(comment, has_code_paths)
    new_has_code_paths = has_code_paths || false
    current_metadata = comment.metadata || {}
    if current_metadata["has_code_paths"] != new_has_code_paths
      comment.update!(metadata: current_metadata.merge("has_code_paths" => new_has_code_paths))
    end
  end
end
