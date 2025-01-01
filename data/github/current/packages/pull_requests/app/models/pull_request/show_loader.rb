# typed: true
# frozen_string_literal: true

class PullRequest::ShowLoader < Issue::ShowLoader
  include GitHub::ResilienceMixin

  SUPPORTED_EVENTS = Issue::ShowLoader::SUPPORTED_EVENTS + %w[
    added_to_merge_queue
    auto_merge_disabled
    auto_merge_enabled
    auto_squash_enabled
    auto_rebase_enabled
    automatic_base_change_succeeded
    automatic_base_change_failed
    base_ref_changed
    base_ref_deleted
    base_ref_force_pushed
    convert_to_draft
    copilot_work_finished
    copilot_work_finished_failure
    copilot_work_started
    deployed
    deployment_environment_changed
    head_ref_deleted
    head_ref_force_pushed
    head_ref_restored
    merged
    ready_for_review
    removed_from_merge_queue
    review_dismissed
    review_requested
    review_request_removed
  ]

  attr_reader :pagination_params, :timeline_loader

  def self.issue_node(issue, repository, viewer, cap_filter: nil, pagination_params: {}, cpu_timer: nil)
    show_loader = new(issue, repository, viewer, cap_filter: cap_filter, pagination_params: pagination_params, cpu_timer: cpu_timer)
    PullRequest::Adapter::PullRequestAdapter.new(show_loader.context, timeline_loader: show_loader.timeline_loader)
  end

  def initialize(pull_request, repository, viewer, cap_filter: nil, pagination_params: {}, cpu_timer: nil)
    @context = PullRequest::Adapter::Context.new(pull_request, repository, viewer, cap_filter)
    @pagination_params = pagination_params
    @cpu_timer = cpu_timer
    preload
  end

  def load_timeline
    track_execution_time do
      @timeline_loader = PullRequest::Loader::PullRequestTimeline.new(@context, pagination_params)
      @all_visible_entries = @timeline_loader.timeline_entries

      @all_visible_entries.each do |entry|
        entry.strict_loading! if entry.is_a? ApplicationRecord::Base
      end
    end
  end

  def preload
    track_execution_time(scope: :shared) do
      super # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    track_execution_time(scope: :prs_only) do
      kick_off_async_work
      preload_review_dismissed_events
      preload_merged_events
      preload_deployed_events
      preload_deployment_environment_changed_events
      preload_head_ref_deleted_events
      preload_review_request_events
      preload_ready_for_review_events
      preload_commits
      preload_reviews
      preload_merge_queue
      preload_legacy_review_threads
    end
  end

  def load_issue_events
    super(SUPPORTED_EVENTS)
  end

  private

  def preload_reviews
    track_execution_time(tags: ["defer_syntax_highlighted_diffs:true"]) do
      # Preload this data so it doesn't happen during render time
      context.pull_request.head_repository
      if context.viewer
        context.pull_request.suggested_change_applicable_by?(context.viewer)
        context.pull_request.pending_review_by?(context.viewer)
        context.viewer.slash_commands_enabled?
        context.viewer.employee?
      end

      context.reviews_by_id = reviews.index_by(&:id)

      GitHub::PrefillAssociations.prefill_associations(reviews, :pull_request, available_records: [context.pull_request])
      GitHub::PrefillAssociations.prefill_batch_method(reviews, :dismissed_review_state)
      GitHub::PrefillAssociations.prefill_batch_method(reviews, :prelude_paginated_review_threads_and_replies_for, context.viewer, PullRequests::ReviewComponent.pagination_params)
      GitHub::PrefillAssociations.prefill_batch_method(reviews, :prelude_body_html, {
        context: PullRequests::ReviewComponent.body_html_context(
          pull_request: context.pull_request,
          viewer: context.viewer,
          cap_filter: context.cap_filter,
        )
      })
      GitHub::PrefillAssociations.prefill_batch_method(reviews, :prelude_viewer_can_react, context.viewer)
      GitHub::PrefillAssociations.prefill_batch_method(reviews, :prelude_user_logins_by_reaction)
      GitHub::PrefillAssociations.prefill_batch_method(reviews, :prelude_on_behalf_of_visible_teams_for, context.viewer)
      GitHub::PrefillAssociations.prefill_batch_method(reviews, :prelude_thread_comment_ids, context.viewer)
      Issue::Loader::Base.new.async_preload_attribute(reviews, :async_author_can_push, :async_author_can_push_to_repository?).sync
      Issue::Loader::Base.new.async_preload_attribute(reviews, :async_author_is_qualified_reviewer, :async_author_is_qualified_reviewer?).sync

      visible_threads, visible_cross_replies = reviews.map do |review|
        page_info = review.prelude_paginated_review_threads_and_replies_for(context.viewer, PullRequests::ReviewComponent.pagination_params)
        visible_items = page_info[:first_group]
        visible_items += page_info[:last_group] if page_info[:last_group]
        visible_items
      end.flatten.partition do |item|
        item.is_a?(PullRequestReviewThread)
      end

      PullRequests::ReviewThreadComponent.preload_review_threads(review_threads: visible_threads, viewer: context.viewer, pull_request: context.pull_request)
      GitHub::PrefillAssociations.prefill_batch_method(
        visible_threads.reject(&:resolved?),
        :prelude_diff_lines,
        {
          max_context_lines: PullRequests::ReviewThreadDiffLinesComponent::MAX_CONTEXT_LINES,
          cache_only: true
        }
      )

      visible_review_comments = T.let([], Array)
      visible_review_comments = visible_cross_replies + visible_threads.map do |thread|
        page_info = thread.prelude_paginated_review_comments_for(context.viewer, PullRequests::ReviewThreadBodyComponent.pagination_params)
        visible_review_comments = page_info[:first_group]
        visible_review_comments += page_info[:last_group] if page_info[:last_group]
        visible_review_comments
      end.flatten

      PullRequests::ReviewCommentComponent.preload_review_comments(
        review_comments: visible_review_comments,
        reviews: reviews,
        pull_request: context.pull_request,
        viewer: context.viewer,
        cap_filter: context.cap_filter,
        timer: @cpu_timer,
      )

      # Wait for the annotations back from turboscan here, before attempting to preload the code scanning review comments.
      track_execution_time(scope: :code_scanning_load_annotations_sync) do
        code_scanning_annotations_promise.sync
      end if code_scanning_annotations_promise

      if context.pull_request.repository
        # Wait for the suggested fixes back from turboscan here, before attempting to preload the code scanning suggested fixes.
        track_execution_time(scope: :code_scanning_load_suggested_fixes_sync) do
          code_scanning_suggested_fixes_promise.sync
        end if code_scanning_suggested_fixes_promise
      end

      track_execution_time(scope: :preload_code_scanning_review_comments) do
        CodeScanning::ReviewCommentComponent.preload_review_comments(pull_request: context.pull_request)
      end
    end
  end

  def preload_merged_events
    track_execution_time do
      merged_events = context.events.select { |issue_event| issue_event.event == "merged" }
      with_async_database_error_fallback(Promise.all(merged_events.map { |event| event.async_revertable_by?(context.viewer) }), fallback: nil).sync

      Issue::Loader::Base.new.async_preload_attribute(
        merged_events,
        :commit,
        :async_commit
      ).sync
    end
  end

  def preload_head_ref_deleted_events
    track_execution_time do
      return unless context.events.find { |issue_event| issue_event.event == "head_ref_deleted" }

      with_async_database_error_fallback(context.pull_request.async_head_ref_restorable_by?(context.viewer), fallback: false).sync
    end
  end

  def preload_review_request_events
    track_execution_time do
      review_request_events = context.events.select { |issue_event| issue_event.event == "review_requested" || issue_event.event == "review_request_removed" }
      review_request_ids = review_request_events.map { |issue_event| issue_event.event == "review_requested" ? issue_event.review_request_id : nil }.compact
      review_requests = context.pull_request.unscoped_review_requests.where(id: review_request_ids)

      GitHub::PrefillAssociations.prefill_batch_method(review_requests, :prelude_visible_assigned_from_team_name, context.viewer)

      review_requests_by_id = review_requests.index_by(&:id)
      review_request_events.each do |issue_event|
        issue_event.preload_attr(:review_request, review_requests_by_id[issue_event.review_request_id])
      end

      GitHub::PrefillAssociations.prefill_batch_method(review_request_events, :visible_subject_for, context.viewer)
      Promise.all(
        review_request_events.map do |issue_event|
          subject = issue_event.visible_subject_for(context.viewer)
          next unless subject.is_a?(Team)
          subject.async_organization
        end.compact
      ).sync

      with_database_error_fallback(fallback: []) do
        Promise.all(review_request_events.map(&:review_request).map { |review_request| [review_request&.async_codeowners_path_uri, review_request&.async_codeowners_file] }.flatten).sync
      end
    end
  end

  def preload_ready_for_review_events
    track_execution_time do
      ready_for_review_events = context.events.select { |issue_event| issue_event.event == "ready_for_review" }
      Promise.all(ready_for_review_events.map { |event| event.async_subject }).sync
    end
  end

  def preload_review_dismissed_events
    track_execution_time do
      dismissed_events = context.events.select { |issue_event| issue_event.event == "review_dismissed" }

      # preload and memoize on the pull_request
      context.pull_request.reviews_for(context.viewer)

      # TODO(dzader): find a better place to do this - is it worth a whole loader?
      Issue::Loader::Base.new.async_preload_attribute(
        dismissed_events,
        :dismissal_message,
        :async_message_html
      ).sync
    end
  end

  def preload_deployed_events
    track_execution_time do
      deployment_ids = context.deployed_events.map(&:deployment_id)
      deployments = context.pull_request.repository.deployments.includes(:latest_status, :statuses)
        .where(id: deployment_ids).index_by(&:id)

      context.deployed_events.each do |event|
        event.preload_attr(:deployment, deployments[event.deployment_id])
      end
    end
  end

  def preload_deployment_environment_changed_events
    track_execution_time do
      deployment_status_ids = context.deployment_environment_changed_events.map(&:deployment_status_id)
      deployment_statuses = DeploymentStatus.where(id: deployment_status_ids).index_by(&:id)

      context.deployment_environment_changed_events.each do |event|
        event.preload_attr(:deployment_status, deployment_statuses[event.deployment_status_id])
      end

      Promise.all(context.deployment_environment_changed_events.map { |event| [event.async_path_uri, event.async_integration_for_user(context.viewer)] }.flatten).sync
    end
  end

  def preload_merge_queue
    track_execution_time do
      context.pull_request.merge_queue
    end
  end

  def preload_commits
    track_execution_time do
      visible_oids = @all_visible_entries.select { |p| p.is_a?(Platform::Models::PullRequestCommit) }.map(&:oid)
      all_commits = context.pull_request.changed_commits
      commits = all_commits.select { |commit| visible_oids.include?(commit.oid) }

      GitHub::PrefillAssociations.prefill_batch_method(commits, :prelude_comment_count, context.pull_request.repository)

      Promise.all(
        commits.map do |commit|
          [
            commit.author_actors.map { |git_actor| [git_actor.async_visible_actor(context.viewer), git_actor.async_commits_path_uri] },
            commit.author_actor.async_visible_actor(context.viewer),
            commit.author_actor.async_commits_path_uri,
            commit.committer_actor.async_visible_actor(context.viewer),
            commit.committer_actor.async_commits_path_uri,
            commit.async_authored_by_committer?,
            commit.async_short_message_html,
            commit.async_message_body_html,
            commit.async_unique_visible_author_actors(context.viewer).then { |authors| authors.map { |author| author.async_visible_user(context.viewer) } },
          ].flatten
        end.flatten
      ).sync

      context.commits_by_oid = commits.index_by(&:oid)
      context.commit_comments_by_oid = context.pull_request.repository.commit_comments.where(commit_id: all_commits.map(&:oid)).group_by(&:commit_id)
    end
  end

  def preload_legacy_review_threads
    track_execution_time do
      visible_ids = @all_visible_entries.select { |p| p.is_a?(PullRequestReviewThread) }.map(&:id)
      all_review_threads = context.pull_request.legacy_review_threads.where(id: visible_ids).index_by(&:id)
      context.legacy_reviews_by_id = all_review_threads
    end
  end

  # Start work that will execute in the background while other data loading happens.
  def kick_off_async_work
    # just start the async work and return immediately
    code_scanning_annotations_promise
    code_scanning_suggested_fixes_promise
  end

  def reviews
    @reviews ||= begin
      review_ids = @all_visible_entries.select { |p| p.is_a?(PullRequestReview) }.map(&:id)
      PullRequestReview.where(id: review_ids).includes(:user).to_a
    end
  end

  def code_scanning_annotations_promise
    return @code_scanning_annotations_promise if defined?(@code_scanning_annotations_promise)
    @code_scanning_annotations_promise = if reviews.any?(&:code_scanning?)
      track_execution_time(scope: :code_scanning_load_annotations) do
        context.pull_request.async_preload_code_scanning_alerts
      end
    end
  end

  def code_scanning_suggested_fixes_promise
    return @code_scanning_suggested_fixes_promise if defined?(@code_scanning_suggested_fixes_promise)
    @code_scanning_suggested_fixes_promise = if reviews.any?(&:code_scanning?)
      track_execution_time(scope: :code_scanning_load_suggested_fixes) do
        context.pull_request.async_preload_code_scanning_suggested_fixes
      end
    end
  end

  # scope is an optional string for disambiguating multiple calls to the same loader/preloader method
  def track_execution_time(scope: nil, tags: [])
    result = T.let(nil, T.untyped)
    timer = T.let(nil, T.nilable(Timer))

    metric_name = "pull_request_loader"

    klass = self.class.name&.demodulize.downcase
    method = T.must(caller_locations(1, 1))[0]&.base_label
    method = "#{method}.#{scope}" if scope
    span_name = "#{metric_name}::#{klass}::#{method}"
    mysql_count_start = GitHub::MysqlInstrumenter.query_count

    GitHub.tracer.in_span(span_name, kind: :internal) do |span|
      timer = Timer.start
      result = yield
      timer.stop

      mysql_count = GitHub::MysqlInstrumenter.query_count
      span.set_attribute("gh.mysql_queries", mysql_count - mysql_count_start)
    end

    GitHub.dogstats.distribution("#{metric_name}.dist.time", timer&.elapsed_ms, tags: tags + [
      "fn:#{klass}:#{method}"
    ])

    result
  end

  def track_placeholders(placeholders)
    GitHub.dogstats.distribution("pull_request_loader.dist.placeholders", placeholders.count)
    by_klass = placeholders.group_by { |p| p.class.name.demodulize }
    by_klass.each do |(klass, klass_placeholders)|
      GitHub.dogstats.distribution("pull_request_loader.dist.placeholders.by_class", klass_placeholders.count, tags: %W[class:#{klass}])
    end
  end
end
