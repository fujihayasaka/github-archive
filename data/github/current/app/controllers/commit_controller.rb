# typed: false
# frozen_string_literal: true

class CommitController < GitContentController
  include ActionView::Helpers::NumberHelper
  include ShowPartial
  include ApplicationHelper
  include RepositoriesHelper
  include GitHub::Encoding
  include ControllerMethods::Commit
  include ControllerMethods::Diffs
  include GitHub::RateLimitedRequest
  include CommitShowMethods
  include DiffViewHelper
  include Commit::ReactPayloadDataDependency
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:lock, :unlock, :context_lines]

  rate_limit_requests only: [:show],
    max: 5000,
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL,
    key: :rate_limit_key_by_ip

  rate_limit_requests \
    only: [:branch_commits],
    if: :request_is_rate_limited?,
    key: :commit_rate_limit_key,
    max: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_MAX,
    ttl: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_TTL

  preload_features [:commit_avatar_stack_view_component], only: :show

  around_action :record_stats, only: [:show, :spoofed_commit_check, :branch_commits, :show_partial, :check_commit_quorum]

  helper :diff

  layout :current_layout
  javascript_bundle :diffs
  stylesheet_bundle :code

  self.react_bundle_name = "commits"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:show, :context_lines, :rich_diff]

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Repositories,
  ApplicationRecord::Collab,
  ApplicationRecord::Spokes,
  ApplicationRecord::Configurations,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::IssuesPullRequests,
  ApplicationRecord::Mysql2,
  only: [:deferred_comment_data, :discussion_comments]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    only: [:inline_comments]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Configurations,
    only: [:show_partial]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    only: [:branch_commits]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    only: [:deferred_commit_data]

  depends_on_clusters ApplicationRecord::RepositoriesActionsChecks,
    only: [:deferred_commit_data],
    optional: true

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::Ballast,
    only: [:show],
    optional: true

  MAX_EXTRA_DIFFS_TO_GET = GitHub::Diff::DEFAULT_MAX_FILES

  def show
    return render_404 if current_commit.nil? || params[:name].blank?
    async_mark_thread_as_read current_commit

    # 404 if scoped path isn't in the diff
    return render_404 if path_string.present? && commit_tree_diff_page.nil?

    diff_options = {
      use_summary: true,
      ignore_whitespace: ignore_whitespace?,
      paths: path_string.present? ? [path_string] : [],
    }
    current_commit.set_diff_options(diff_options)

    diff_options[:top_only] = true
    current_commit.set_diff_options(diff_options)

    stats.entity = current_commit

    GitHub.dogstats.time("diff.load.initial", tags: dogstats_request_tags) do
      current_commit.init_diff.apply_auto_load_single_entry_limits!
      current_commit.diff # loads diff
    end

    @diffs = current_commit.diff
    # Indicates that this commit was in the commit cache, but isn't
    # actually present in the repository.
    return render_404 if @diffs.missing_commits?

    begin
      respond_to do |wants|
        wants.html do
          if react_commit_enabled?
            render_commit_react_app
          else
            preload_commit_comment_data

            # to track react.request.duration metric for comparison to react app
            request.env[GitHub::TaggingHelper::PROCESS_REQUEST_REACT_TYPE] = "rails"

            render "commit/show", locals: {
              commit: current_commit,
              file_list_view: file_list_view,
              show_checks_status: GitHub.actions_enabled?,
            }
          end
        end

        wants.json do
          if react_commit_enabled?
            render_commit_react_app
          else
            head :not_acceptable
          end
        end

        wants.diff  { diff }
        wants.patch { diff(as_patch: true) }
        wants.all   { head :not_acceptable }
      end
    rescue GitRPC::ObjectMissing
      # We shouldn't get here, if we do the repo could be in a bad state
      render_404
    end
  end

  rescue_from_timeout only: [:show] do |_boom|
    if react_commit_enabled?
      render_commit_react_app_unavailable("timeout")
    else
      render "commit/timeout", locals: { commit: current_commit }
    end
  end

  def spoofed_commit_check # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless current_commit

    stats.entity = current_commit

    respond_to do |format|
      format.html do
        # Render the view that perfroms the check whether a given commit might be spoofed
        # A potentially spoofed commit is one that is not present in the current repo's branches or PRs
        render partial: "commit/spoofed_commit_check", locals: {
          view: create_view_model(Commits::BranchListView, commit: current_commit)
        }
      end
    end
  end

  def branch_commits # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless current_commit

    stats.entity = current_commit

    respond_to do |format|
      format.html do
        render partial: "commit/branch_commits", locals: {
          view: create_view_model(Commits::BranchListView, commit: current_commit)
        }
      end
      format.json do
        render json: build_branch_commit_payload(current_commit, current_user)
      end
    end
  end

  def find_in_diff_worker_path # rubocop:todo GitHub/UseRestfulActions
    web_worker_url("find-in-diff-worker.js")
  end

  def rich_diff # rubocop:todo GitHub/UseRestfulActions
    path = params[:path]

    return :not_found unless current_commit && path

    diff_entry = file_list_view.each_diff.to_a.find { |diff| diff.diff.path == path }

    return :not_found unless diff_entry

    if diff_entry.prose_diff?
      prose_diff = prose_diff_html(diff_entry.diff, current_repository)
    elsif diff_entry.code_rendering_service.supports_view?
      render_info = rendered_blob(diff_entry, file_list_view, diff_entry.diff)
    end

    respond_to do |format|
      format.json do
        render json: { proseDiffHtml: prose_diff, fileRendererInfo: render_info }
      end
    end
  end

  def context_lines # rubocop:todo GitHub/UseRestfulActions
    file_for_context = get_selected_diff(params[:pathDigest])
    line_ranges_object_array = []
    line_ranges_object_array = params[:lineRanges].map { |range_string| JSON.parse(range_string) } if !params[:lineRanges].nil?
    line_ranges_array = []
    line_ranges_object_array.each { |range| line_ranges_array.push(Range.new(range["start"], range["end"])) }
    current_diff = file_for_context[0].diff

    highlighted_diff = SyntaxHighlightedDiff.new(file_list_view.repository)
    context_lines = {}

    context_lines[current_diff.a_path] = line_ranges_array
    context_injector = GitHub::Diff::ContextInjector.new(
      diff_text: current_diff.to_diff_text,
      context_lines: context_lines,
      sha2: current_diff.b_sha,
      rpc: file_list_view.repository.rpc,
      repo: file_list_view.repository,
    )

    entries = []
    parser = GitHub::Diff::Parser.new(context_injector.expanded_diff)
    parser.each { |e| entries.push(e) }
    diff_with_context = entries[0]

    if GitHub.flipper[:css_custom_highlighting].enabled?(current_user)
      highlighted_diff.highlight_with_styled_directives!([diff_with_context])
      styling_directives = highlighted_diff.styling_directive(diff_with_context)
    else
      highlighted_diff.highlight!([diff_with_context])

      shd = highlighted_diff.colorized_lines(diff_with_context)
      if shd
        shd.each(&:freeze)
        shd.freeze
      end
    end

    diff_lines = build_diff_line_data(diff_with_context, shd)

    respond_to do |format|
      format.json do
        render json: { diffEntryWithContext: diff_lines }
      end
    end
  end

  def discussion_comments # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless current_commit

    preload_discussion_comments_data(params[:before_comment_id])

    discussion_comments_payload = build_discussion_comment_payload(current_commit)

    render json: {
      **discussion_comments_payload,
      subscribed: is_subscribed_to_commit(current_user, current_repository, current_commit),
    }
  end

  def inline_comments # rubocop:todo GitHub/UseRestfulActions
    path = params[:path]
    position = params[:position].to_i

    return head :not_found unless path.present? && position.present?
    return head :not_found unless current_commit

    thread_comments = file_list_view.threads.path(path).position(position).flat_map(&:comments)

    preload_comment_associations(thread_comments, current_user, current_repository)

    comments_payload = thread_comments.map do |comment|
      build_commit_comment_payload(comment, current_user, current_repository, cap_filter, prefill_associations: false)
    end

    render json: {
      comments: comments_payload,
    }
  end

  def deferred_commit_data # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless current_commit

    respond_to do |format|
      format.json do
        render json: { data: build_deferred_commit_payload([current_commit], current_repository, current_user)[0] }
      end
    end
  end

  # consolidated endpoint for fetching all deferred comment data after initial page load
  def deferred_comment_data # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless current_commit

    preload_commit_comment_data(params[:until_comment_id]) # populates current_commit.comments and file_list_view

    discussion_comments_payload = build_discussion_comment_payload(current_commit)

    inline_thread_data = file_list_view.threads.map do |thread|
      build_inline_thread_data(thread)
    end

    if GitHub.flipper[:diff_inline_comments].enabled?(current_user)

      loaded_comments = PullRequests::PageData::CommitComments::Loader.load(current_user:, file_list_view:, cap_filter:, current_repository:)
      comments_payload = PullRequests::PageData::CommitComments::Payload.call(loaded_comments)

      render json: {
        threadMarkers: inline_thread_data,
        inlineComments: comments_payload,
        discussionComments: discussion_comments_payload,
        subscribed: is_subscribed_to_commit(current_user, current_repository, current_commit),
      }
    else
      render json: {
        threadMarkers: inline_thread_data,
        discussionComments: discussion_comments_payload,
        subscribed: is_subscribed_to_commit(current_user, current_repository, current_commit),
      }
    end
  end

  def show_partial # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless current_commit

    stats.entity = current_commit

    if params[:partial] == "commit/timeline_marker"
      Commit.prefill_combined_statuses([current_commit], current_repository)

      comments = CommitComment.for_display(current_user, current_commit, current_repository)
      if params[:before_comment_id]
        current_commit.comments = fetch_page(comments.discussion, params[:before_comment_id])
      else
        current_commit.comments = comments
          .discussion
          .where("created_at > ?", helpers.discussion_last_modified_at)
      end

      preload_commit_comment_associations(current_commit.comments)

      respond_to do |format|
        format.html do
          render partial: "commit/timeline_marker", object: current_commit, layout: false, locals: { commit: current_commit }
        end
      end
    elsif params[:partial] == "commit/condensed_details"
      respond_to do |format|
        format.html_fragment do
          render partial: "commit/condensed_details", formats: [:html], locals: { commit: current_commit }
        end
        format.html do
          render partial: "commit/condensed_details", locals: { commit: current_commit }
        end
      end
    else
      head :not_found
    end
  end

  def lock # rubocop:todo GitHub/UseRestfulActions
    current_commit.lock(current_user)
    respond_to do |format|
      format.html { redirect_to :back }
      format.json {  head :ok }
    end
  end

  def unlock # rubocop:todo GitHub/UseRestfulActions
    current_commit.unlock(current_user)
    respond_to do |format|
      format.html { redirect_to :back }
      format.json {  head :ok }
    end
  end

  def check_commit_quorum # rubocop:todo GitHub/UseRestfulActions
    stats.entity = current_commit

    attempt_number = params[:attempt_number].nil? ? 1 : Integer(params[:attempt_number], exception: false)

    # current_commit is nil if the commit is not in the repo
    increment_commit_has_quorum_stats(current_commit.present?, attempt_number)

    render(json: { data: { hasQuorum: current_commit.present? } }, status: :ok)
  end

  private

  def current_layout
    if @rendering_react_view
      # We set @rendering_react_view right before render_react_app and after any potential failure paths, so that the
      # correct layout template for the React app is used. Temporary, until all paths in controller are React based.
      "layouts/repository_with_container"
    else
      "repository"
    end
  end

  def has_copilot_access?
    current_copilot_user_v2&.dotcom_chat_enabled? || false
  end

  def render_commit_react_app
    return render_commit_react_app_unavailable(current_commit.diff.unavailable_reason) if current_commit.diff.unavailable_reason

    @rendering_react_view = true
    add_client_feature_flag(Commit::ReactPayload.feature_flags)
    full_index = !!params[:full_index]
    short_path = params[:short_path]

    add_csrf_token("#{diffview_path}?diff=split", :post)
    add_csrf_token("#{diffview_path}?diff=unified", :post)
    add_csrf_token("#{pr_file_tree_visibility_setting_path(user_id: current_user.display_login)}", :put) unless current_user.nil?
    add_csrf_token(notifications_thread_subscribe_path, :post)

    payload = instrument_react_payload_time do
      commit_show_payload(
        current_repository: current_repository,
        current_commit: current_commit,
        file_list_view: file_list_view,
        current_user: current_user,
        short_path: short_path,
        ignore_whitespace: ignore_whitespace?,
        full_path: request.path,
        diff_view: diff_view,
        has_copilot_access: has_copilot_access?,
      )
    end

    render_react_app(
      app_payload_generator: -> { { helpUrl: GitHub.help_url, findInDiffWorkerPath: find_in_diff_worker_path } },
      payload: payload,
      title: page_title,
      custom_tags: [
        "referrer_controller_action:commit#show",
        "is_react:true"
      ],
      page_data: {
        selected_link: :repo_commits,
        send_vitals: true,
        richweb: {
          title: page_title,
          url: commit_url(current_commit.oid),
          description: helpers.truncate(current_commit.message_body_text || "", length: 240),
          image: repository_open_graph_image_url(current_repository, resource: current_commit),
          updated_time: current_commit.committed_date.to_i,
        }
      },
      disable_ssr: !GitHub.flipper[:diff_ux_refresh_ssr].enabled?(current_user),
    )
  end

  def render_commit_react_app_unavailable(reason)
    @rendering_react_view = true
    add_client_feature_flag(Commit::ReactPayload.feature_flags)
    full_index = !!params[:full_index]

    render_react_app(
      app_payload_generator: -> { { helpUrl: GitHub.help_url, } },
      payload: {
        commit: build_commit_payload(current_commit, current_user),
        unavailableReason: reason, # when we get here, it's now a string reason instead of boolean | string
        currentUser: Repos::ReactPayload.current_user_payload_for_diff(current_user),
        repo: Repos::ReactPayload.current_repository_payload(
          current_repository,
          current_user_can_push: current_user_can_push?
        ),
        path: request.path,
      },
      title: page_title,
      page_data: {
        selected_link: :repo_commits,
        send_vitals: true,
        richweb: {
          title: page_title,
          url: commit_url(current_commit.oid),
          description: helpers.truncate(current_commit.message_body_text || "", length: 240),
          image: repository_open_graph_image_url(current_repository, resource: current_commit),
          updated_time: current_commit.committed_date.to_i,
        }
      },
      disable_ssr: !GitHub.flipper[:diff_ux_refresh_ssr].enabled?(current_user),
    )
  end

  def build_discussion_comment_payload(current_commit)
    comments_payload = current_commit.comments.map do |comment|
      build_commit_comment_payload(comment, current_user, current_repository, cap_filter, prefill_associations: false)
    end

    {
      comments: comments_payload,
      count: current_commit.comment_count,
      canLoadMore: current_commit.can_load_more_comments?, # set in fetch_page
    }
  end

  PATCH_TIMEOUT_SECONDS = 3

  def diff(as_patch: false)
    timeout_client_error do
      set_request_category! "raw"

      full_index = !!params[:full_index]
      diff = current_repository.rpc.with_timeout(PATCH_TIMEOUT_SECONDS) do
        if as_patch
          current_repository.rpc.native_patch_text(current_commit.oid, full_index: full_index)
        else
          current_repository.rpc.native_diff_text(current_commit.oid, full_index: full_index)
        end
      end

      # Security fix. See #36923
      render_error_for_pdf_headers(diff)

      content_type = detect_content_type(diff)

      render(content_type: content_type, body: diff) unless performed?
    end
  end

  def detect_content_type(data)
    content_type = "text/plain"
    encoding     = "utf-8"

    if (detected = guess_encoding(data)) && detected[:type] == :text
      encoding = detected[:encoding].downcase
    end

    "#{content_type}; charset=#{encoding}"
  end

  def commit_tree_diff # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @commit_tree_diff ||= current_repository.rpc.read_tree_diff(current_commit.oid)
  end
  helper_method :commit_tree_diff

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def commit_tree_diff_page # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @commit_tree_diff_page ||= begin
      filenames = commit_tree_diff.map { |c| c["old_file"]["path"] }
      if index = filenames.index(path_string)
        index + 1
      end
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator
  helper_method :commit_tree_diff_page

  def route_supports_advisory_workspaces?
    true
  end

  # Override AbstractRepositoryController#defer_commit_badges? to
  # opt-in to deferred loading of commit signature badges.
  def defer_commit_badges?
    !live_updating_commit_details?
  end

  # Override AbstractRepositoryController#defer_status_check_rollups? to
  # opt-in to deferred loading of status check rollups
  def defer_status_check_rollups?
    !live_updating_commit_details?
  end

  def live_updating_commit_details?
    params[:action] == "show_partial" && params[:partial] == "commit/condensed_details"
  end

  def get_selected_diff(path_digest)
    file_list_view.each_diff.to_a.select do |diff|
      path_digest == Digest::SHA256.hexdigest(diff.diff.path)
    end
  end

  def page_title
    title_message = current_commit.short_message_text.empty? ? "" : "#{current_commit.short_message_text} · "
    "#{title_message}#{current_repository.name_with_display_owner}@#{current_commit.abbreviated_oid}"
  end

  def record_stats
    stats.instrument_controller_action do
      yield
      response.successful?
    end
  end

  def increment_commit_has_quorum_stats(has_quorum, attempt_number)
    result_tag = has_quorum ? "success" : "failure"
    GitHub.dogstats.increment("commit", tags: ["type:quorum_check", "result:#{result_tag}", "attempt_number:#{attempt_number}"])
  end

  def request_is_rate_limited?
    !logged_in? && GitHub.flipper[:branch_commits_anon_rate_limiting].enabled?
  end

  def commit_rate_limit_key
    key_base = "#{self.class.to_s.underscore}:#{action_name}"
    actor_identifier = request.env.fetch("HTTP_X_SSL_JA3_HASH", nil)
    actor_identifier = request.remote_ip if actor_identifier.blank?
    "#{key_base}:#{actor_identifier}"
  end

  def stats # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_stats ||= ::PageStats.new(
      controller_name: "commit",
      action_name: action_name,
      viewer: current_user,
      pjax: pjax?,
    )
  end

  helper_method :stats
end
