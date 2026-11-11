# typed: true
# frozen_string_literal: true

module PullRequests::ReactDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }

  include PullRequests::NewFilesChangedHelper
  include GitHub::Memoizer
  include GateRequestHelper
  include BranchesHelper
  include PullRequests::PageTitleHelper
  include RawBlob::AbstractRepositoryHelper
  include SiteHelper
  include PullRequests::DiffContentLoadingHelper
  include FileFilterHelper
  include ActionView::Helpers::TextHelper
  include PullRequests::MergeboxHelper
  include PullRequests::ComparisonTracking
  include InProductTargeting::TransactionalMessageConcern
  include PullRequests::ChecksDependency

  # Implement abstract methods from FileFilterHelper
  sig { override.returns(T.any(ActionController::Parameters, Hash)) }
  def params
    T.must(super)
  end

  sig { override.returns(T.nilable(::User)) }
  def current_user
    super
  end

  def render_pull_requests_react(
    pull:,
    range: nil,
    mode: nil,
    use_changes_range: false,
    skip_layout: false,
    url_override: false
  )
    add_react_feature_flags

    if action_name == "files" || action_name == "changes"
      single_file_mode = mode == "single"
      force_virtualization = mode == "virtualization"

      begin
        files_payload = build_prx_files_payload(pull, range, single_file_mode, use_changes_range, force_virtualization)
      rescue TypeError # raised when unable to init pull request comparison
        return render "pull_requests/files_unavailable"
      rescue PullRequests::Errors::FilesUnavailable, GitRPC::ObjectMissing
        return render "pull_requests/files_unavailable"
      rescue PullRequests::Errors::NonCanonicalRange => e
        return redirect_to(range: e.canonical_range)
      rescue PullRequests::Errors::OrphanCommit => e
        return render "pull_requests/orphan_commit", status: :not_found, locals: { oid2: e.oid2 }
      rescue GitHub::Diff::Parser::UnrecognizedText
        return render "pull_requests/unrecognized_diff_text", status: :not_found, locals: { pull: pull }
      end
    end

    nested_payloads = []

    if action_name == "commits"
      current_path = defined?(path_string_for_display) ? path_string_for_display : ""

      commits_data = PullRequests::PageData::CommitsPayload.build(
        current_path:,
        current_user:,
        pull_request: pull,
        tree_name: tree_name_for_display
      )

      payload = PullRequests::ReactPayloads::PullRequestsCommitsPayload.new(commits_data)
    elsif action_name == "files"
      if range
        # maps to `/pulls/:id/files/:range`
        payload = PullRequests::ReactPayloads::PullRequestsFilesWithRangePayload.new(files_payload)
      else
        # maps to `/pulls/:id/files`
        payload = PullRequests::ReactPayloads::PullRequestsFilesPayload.new(files_payload)
      end
    elsif action_name == "changes"
      if range
        # maps to `/pulls/:id/changes/:range`
        payload = PullRequests::ReactPayloads::PullRequestsChangesWithRangePayload.new(files_payload)
      else
        # maps to `/pulls/:id/changes`
        payload = PullRequests::ReactPayloads::PullRequestsChangesPayload.new(files_payload)
      end
    # support voltron route
    elsif action_name == "show" || action_name == "pull_request_layout"
      payload = PullRequests::ReactPayloads::PullRequestsConversationsPayload.new(
        locked: current_repository_locked_for_migration?,
        pull_request: pull,
        current_user: current_user,
        default_merge_method: default_merge_method_for_user(pull, current_user)
      )
    elsif action_name == "checks"
      payload = checks_partial_payload(pull)
    elsif action_name == "overview"
      overview_data = PullRequests::PageData::Overview::Loader.load(pull_request: pull, current_user:)
      overview_payload = PullRequests::PageData::Overview::Payload.call(overview_data)
      payload = PullRequests::ReactPayloads::PullRequestsOverviewPayload.new(overview_payload.as_json)
    end


    respond_to do |format|
      format.html do
        track_missed_soft_navigation

        if action_name == "show" || action_name == "pull_request_layout"
          voltron = action_name == "pull_request_layout"

          nested_payloads = [
            conversation_body_payload(pull),
            conversation_timeline_payload(pull, voltron: voltron),
            conversation_timeline_actions_payload(pull),
            conversation_sidebar_partial_payload(pull: pull, voltron: voltron)
          ]
        end

        header_data = PullRequests::PageData::HeaderPayload.build(
          current_user:,
          pull_request: pull,
        )

        render_react_html(
          title: pull_request_page_title(pull),
          payload: payload,
          nested_payloads: [PullRequests::ReactPayloads::PullRequestsLayoutPayload.new(header_data)] + nested_payloads,
          app_name: "pull-requests",
          app_payload_generator: -> {
            user = current_user
            {
              helpUrl: GitHub.help_url,
              refListCacheKey: ref_list_cache_key,
              transactionalMessageBanner: user ? transactional_message_payload(user, :prs, helpers) : nil,
            }
          },
          custom_tags: [
            "referrer_controller_action:pull_requests##{action_name}",
            "is_react:true"
          ],
          page_data: react_page_metadata(pull, action_name),
          url_override: url_override ? pull.url : nil,
          path_override: url_override ? pull.url(include_host: false) : nil,
          layout: skip_layout ? false : "layouts/repository_with_container",
        )
      end

      format.json do
        render_react_json(title: pull_request_page_title(pull), payload: payload)
      end
    end

  # BadRange error is handled the same for PR#files and PR#commits
  rescue PullRequests::Errors::BadRange
    disable_account_switcher_popover
    render "pull_requests/bad_range", status: :not_found
  end

  def add_react_feature_flags
    add_client_feature_flag(
      [
        :move_new_comments_ui,
        :copilot_code_review_findings_ui,
        :copilot_workspace,
        :cotd_derive_thread_previews,
        :batch_suggested_changes,
        :prx_dynamic_split_pref,
        :prx_files,
        :prx_files_lite_throttle,
        :prx_files_medium_throttle,
        :"pulls-files-skip-prefer-any-solo-entry",
        :generate_groups_on_files_view,
        :pull_request_file_tree_width_persistence,
        :pull_request_stacks,
        :prx_robust_small_screen_support,
      ]
    )
    add_client_feature_flag([:cotd_ui], entity: current_repository) do |feature_name, repo|
      repo.feature_flag_enabled?(feature_name, default: false) && repo.feature_flag_enabled?(:prx_comment_outside_the_diff, default: false) || repo.owner&.feature_flag_enabled?(feature_name, default: false) && repo.owner&.feature_flag_enabled?(:prx_comment_outside_the_diff, default: false)
    end
    # pull_request_merge_status_button_opt_out is an org-level feature flag use to disable the merge status button
    add_client_feature_flag([:pull_request_merge_status_button_opt_out], entity: current_repository.owner)

    # UI is checking for the react_data_router_pull_request_files flag in payload even if we're not checking vexi for it anymore
    # when providing a block to add_client_feature_flag, the flag will only be added if the block returns true
    add_client_feature_flag([:react_data_router_pull_request_files], entity: current_user) do |_, user|
      # we need to ensure that new files changed is enabled so soft nav attempts from commits -> files do not error
      # this check will need to be around until new files changes is GA-ed
      new_files_changed_feature_enabled_for_user?(user, params)
    end
  end

  # Private: Determines if the React files changed view should be rendered.
  #
  # This method checks two conditions:
  # 1. If the new files changed feature is enabled for the current user
  # 2. If the app type header indicates a soft navigation context
  #
  # The check_app_type_header check is necessary to gracefully handle soft navigation from commits to files.
  # This ensures that if the user initially rendered the app with React files changed view, subsequent
  # navigations to the files tab will also render the React view, even if the feature flag state changes externally.
  #
  # check_app_type_header will only evaluate to true when performing a soft navigation, as the header is only set in that context.
  # Additionally, a soft navigation is only possible if the user initially loaded with New Files Changed & Files Data Router enabled.
  #
  # Returns a Boolean indicating whether to render the React files changed view.
  def should_render_react_files_changed?
    new_files_changed_feature_enabled_for_user?(current_user, params) || check_app_type_header
  end

  memoize def conversations_react_enabled?
    FeatureFlag.vexi.enabled?(:prs_conversations_react, current_user, default: false)
  end

  memoize def checks_react_enabled?
    FeatureFlag.vexi.enabled?(:prs_checks_react, current_user, default: false)
  end

  memoize def overview_react_enabled?
    FeatureFlag.vexi.enabled?(:prs_overview_react, current_user, default: false)
  end

  def layout_data(pull_request)
    header_data = PullRequests::PageData::HeaderPayload.build(
      current_user:,
      pull_request: pull_request,
    )
    PullRequests::ReactPayloads::PullRequestsLayoutPayload.new(header_data)
  end

  def conversation_sidebar_partial_payload(pull:, voltron: false)
    PullRequests::ReactPayloads::PullRequestsConversationsSidebarPartialPayload.new(
      fragment_id: "sidebar",
      partial_proc: -> {
        render_rails_partial("pull_requests/sidebar", locals: {
          deferred_content: false,
          pull: pull
        })
      },
      voltron_enabled: voltron
    )
  end

  def create_pull_node(pull)
    if FeatureFlag.vexi.enabled?(:pulls_new_default_timeline_item_cap, current_user, default: false)
      pagination_params = { exclude_item_types: exclude_item_types, per_page: params[:timeline_per_page] || PullRequestsController::DEFAULT_TIMELINE_ITEMS_PAGE_LIMIT }
    else
      pagination_params = { exclude_item_types: exclude_item_types, per_page: params[:timeline_per_page] }
    end

    PullRequest::ShowLoader.issue_node(pull, current_repository, current_user, cap_filter: cap_filter, pagination_params: pagination_params)
  end

  def conversation_partial_payload(pull, voltron: false)
    PullRequests::ReactPayloads::PullRequestsConversationsPartialPayload.new(
      fragment_id: "content",
      partial_proc: -> {
        render_rails_partial("pull_requests/conversation_content", locals: {
          pull_node: create_pull_node(pull),
          pull_request: pull,
          gate_requests: gate_requests_for(pull_request: pull, user: current_user),
          force_timeline: true
        })
      },
      voltron_enabled: voltron
    )
  end

  def conversation_body_payload(pull)
    PullRequests::ReactPayloads::PullRequestsConversationsBodyPayload.new(
      -> { render_rails_partial(PullRequests::BodyComponent.new(pull_request: pull)) }
    )
  end

  def conversation_timeline_payload(pull, voltron: false)
    PullRequests::ReactPayloads::PullRequestsConversationsTimelinePayload.new(
      fragment_id: "content",
      partial_proc: -> {
        render_rails_partial("pull_requests/conversation_timeline_react", locals: {
          pull_node: create_pull_node(pull),
          pull_request: pull,
          gate_requests: gate_requests_for(pull_request: pull, user: current_user),
          current_repository: current_repository,
          current_user: current_user,
        })
      },
      voltron_enabled: voltron
    )
  end

  def conversation_timeline_actions_payload(pull)
    PullRequests::ReactPayloads::PullRequestsConversationsTimelineActionsPartialPayload.new(
      lambda do
        render_rails_partial("pull_requests/conversation_timeline_actions_react", locals: {
          pull_request: pull,
        })
      end
    )
  end

  def checks_partial_payload(pull)
    PullRequests::ReactPayloads::PullRequestsChecksPartialPayload.new(
      lambda do
        render_rails_partial("pull_requests/checks_partial", locals: checks_partial_data(pull))
      end
    )
  end

  private

  # Private: Build the payload for the PRX files changed view.
  # pull_request - The PullRequest object.
  # range - The range parameter for the files view.
  # single_file_mode - Boolean indicating if user has requested single file mode (via params).
  # use_changes_range - Boolean indicating if changes range should be used for comparison.
  # force_virtualization - Boolean indicating if virtualization should be forced (via param).
  def build_prx_files_payload(pull_request, range, single_file_mode = false, use_changes_range = false, force_virtualization = false)
    pull_comparison = calculate_comparison(pull_request, range, current_user, use_changes_range)

    if pull_comparison && current_user.present?
      async_mark_comparison_as_seen(pull_comparison, user: T.must(current_user))
    end

    limit_config = PullRequests::PageData::Files::PageLimitConfig.new(
      repository: current_repository,
      user: current_user,
      single_file_mode: single_file_mode,
      force_virtualization: force_virtualization,
    )

    files_data = PullRequests::PageData::Files::Loader.load(
      comparison: T.must(pull_comparison),
      current_user: current_user,
      file_filter: {
        selected_file_extensions: params[FILE_TYPE_FILTER_PARAM],
        show_deleted_files: !deleted_files_hidden?,
        show_only_manifest_files: manifest_files_active?,
        show_only_owned_files: only_owned_by_active?,
        show_vendored_files: !vendored_files_hidden?,
        show_viewed_files: !viewed_files_hidden?,
      },
      has_range_param: range.present?,
      ignore_whitespace: ignore_whitespace?(pull_request, params, current_user, logged_in?),
      include_codeowners: only_owned_by_active?,
      timeout: request_time_left / 2,
      pull_request: pull_request,
      cap_filter: cap_filter,
      user_session: user_session,
      limit_config: limit_config,
      short_path: params[:short_path]
    )

    PullRequests::PageData::Files::Payload.call(files_data).as_json
  end

  def react_page_metadata(pull, action_name)
    metadata = {
      selected_link: :repo_pulls,
      send_vitals: true,
      container_xl: true,
      stafftools:    UrlHelpers.stafftools_repository_pull_request_path(
                       pull.repository.owner_display_login, pull.repository.name, pull.number),
      richweb: {
        title:       pull_request_page_title(pull),
        url:         pull.url.to_s,
        description: pull.repository.feature_flag_enabled?(:new_pr_page_description, default: false) ? page_description(pull) : pull.body_text,
        image:       pull.repository.show_enhanced_og_image? ? pull.og_image_url : pull.repository.open_graph_image_url(T.unsafe(self).current_user),
        author:      pull.user&.display_login,
      },
      dashboard_pinnable_item_id: pull.id,
      html_class: "js-skip-scroll-target-into-view", # opt out of behavior.js scroll management
    }

    if action_name == "checks"
      metadata[:skip_pjax_container] = true
    end

    metadata
  end

  def page_description(pull_request)
    viewer = T.unsafe(self).current_user
    cap_filter = T.unsafe(self).cap_filter

    truncate(pull_request.body_text(context: pull_request.body_html_context(viewer:, cap_filter:)) || "", length: 200)
  end

  # Private: Track when a hard navigation occurs but should have been a soft navigation.
  #
  # Detects different types of missed soft navigation opportunities
  # Temporary while we roll out soft navigation for PR files changed view.
  #
  # Returns nothing.
  def track_missed_soft_navigation
    return unless FeatureFlag.vexi.enabled?(:track_missed_soft_navigation, current_user, default: false)

    referrer_route = github_internal_referrer_route
    return unless referrer_route && referrer_route[:action] == action_name

    # Detect the type of navigation change
    referrer_range = referrer_route[:range]
    current_range = params[:range]

    nav_type = if referrer_range != current_range
      # Navigating between full view and range view, or between different ranges
      if referrer_range.nil? && current_range.present?
        "full_to_range"
      elsif referrer_range.present? && current_range.nil?
        "range_to_full"
      elsif referrer_range != current_range
        "range_to_range"
      else
        "unknown"
      end
    elsif params[:w].present?
      # Whitespace parameter is present in current request
      "whitespace_toggle"
    elsif request.query_parameters.present?
      # Other query parameters present - filter changes, etc.
      "filter_change"
    else
      # Same range, no query params - plain reload
      "reload"
    end

    GitHub.dogstats.increment(
      "pull_requests.missed_soft_navigation",
      tags: [
        "action:#{action_name}",
        "nav_type:#{nav_type}"
      ]
    )
  rescue => e
    # Still track that we missed a soft nav, even if we couldn't classify it
    GitHub.dogstats.increment(
      "pull_requests.missed_soft_navigation",
      tags: [
        "action:#{action_name}",
        "nav_type:indeterminate",
      ]
    )
  end

  def exclude_item_types
    if current_user&.site_admin?
      params.fetch(:exclude_item_types, [])
    else
      []
    end
  end
end
