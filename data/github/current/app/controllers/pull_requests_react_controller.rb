# typed: true
# frozen_string_literal: true

class PullRequestsReactController < AbstractRepositoryController
  include GitHub::Memoizer
  include CopilotAuthHelper

  # pointers to GraphQL query definitions in relay whose requests we preload
  # for performance. These will be requested immediately on page boot.

  # queries used on every page
  PRX_HEADER_QUERY = Rails.root.join("ui/packages/pull-request-viewer/components/header/__generated__/PullRequestHeaderWrapperQuery.graphql.ts")
  PRX_MAIN_CONTENT_AREA_QUERY = Rails.root.join("ui/packages/pull-request-viewer/components/__generated__/PullRequestMainContentAreaQuery.graphql.ts")

  # queries used on the overview page
  PRX_BODY_QUERY = Rails.root.join("ui/packages/pull-request-viewer/components/__generated__/PullRequestSummaryViewerContentQuery.graphql.ts")
  PRX_DETAILS_PANE_QUERY = Rails.root.join("ui/packages/pull-request-viewer/components/details-pane/__generated__/DetailsPaneQuery.graphql.ts")
  PRX_SECONDARY_CONTENT_QUERY = Rails.root.join("ui/packages/pull-request-viewer/components/__generated__/PullRequestSummaryViewerSecondaryContentQuery.graphql.ts")

  # queries used on the files page
  PRX_FILES_QUERY = Rails.root.join("ui/packages/pull-request-viewer/components/__generated__/PullRequestFilesViewerContentQuery.graphql.ts")
  PRX_MARKERS_COMMENTS_SIDESHEET_QUERY = Rails.root.join("ui/packages/pull-request-viewer/components/__generated__/PullRequestMarkersCommentSidesheetQuery.graphql.ts")

  # queries used on the activity page
  PRX_ACTIVITY_QUERY = Rails.root.join("ui/packages/pull-request-viewer/components/__generated__/PullRequestActivityViewerContentQuery.graphql.ts")

  # queries used on the commits page
  PRX_COMMITS_QUERY = Rails.root.join("ui/packages/pull-request-viewer/components/__generated__/PullRequestCommitsViewerContentQuery.graphql.ts")
  PRX_COMMITS_SECONDARY_CONTENT_QUERY = Rails.root.join("ui/packages/pull-request-viewer/components/commits/__generated__/DeferredCommitsDataLoaderQuery.graphql.ts")

  before_action :login_required
  before_action :add_client_feature_flags

  include BranchesHelper
  include RelayHelper
  include InternalGraphqlTracingHelper
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:toggle_new_mergebox, :toggle_generic_feature]

  layout "layouts/repository_with_container"

  stylesheet_bundle :"pull-requests"

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    optional: false, only: [:prx]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true, only: [:prx]

  preload_features [
    :copilot_reviews,
    :issues_react_prefetch,
    :prx,
    :use_pull_request_subscriptions_enabled,
  ], only: [:prx]

  preload_features [:mergebox_react_partial], only: [:toggle_new_mergebox]

  def prx # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless user_feature_enabled?(:prx) || params[:prx] == "true"
    # The single file page route `/pull/:id/file/*path` is no longer defined in routes.rb, but requests to that path
    # are still routed here via the catch-all `/pull/*id` route, so we have to manually check and respond with a 404.
    # Without this guard, the PRX app will still render, but without any content (blank page).
    return render_404 if is_single_file_page?

    @pull = find_pull_request
    return render_404 if pull.nil?

    common_query_vars = { owner: current_repository.owner.display_login, repo: current_repository.name, number: params[:id].to_i }
    # Configure our Link header / Early Hints to instruct the browser to start
    # fetching these API endpoints as early as possible.
    preload_headers = get_preload_headers(common_query_vars, pull, params[:range])
    set_preload_header(preload_headers)

    author_name = pull.user.display_login

    render_react_app(
      app_name: "pull-request-viewer",
      page_data: {
        footer: false,
        send_vitals: true
      },
      app_payload_generator: -> () {
        {
          helpUrl: GitHub.help_url,
          tracing: tracing_enabled?,
          tracing_flamegraph: tracing_flamegraph_enabled?,
          refListCacheKey: ref_list_cache_key,
          # Pass the merge method used in the initial mergeability query to seed the initial value of the context
          # The alternative is to issue yet one more query, which we are trying to avoid for the time being
          pullRequest: {
            defaultMergeMethod: default_merge_method,
            headRefOid: pull.head_sha,
            basePageDataUrl: pull.url
          },
          current_user_settings: {
            use_monospace_font: current_user&.use_fixed_width_font? || false,
            use_single_key_shortcut: current_user&.settings&.get(:keyboard_shortcuts_preference) == "all",
          },
          paste_url_link_as_plain_text: logged_in? ? current_user&.paste_url_link_as_plain_text? : false,
          ghostUser: {
            displayName: "Ghost",
            login: GitHub.ghost_user_login,
            avatarUrl: User.ghost.primary_avatar_url,
            path: "/ghost",
            url: "/ghost",
          },
          workspaceEditorEnabled: current_user&.workspace_editor_preview_enabled?(repository: current_repository),
        }.merge(app_payload_props_for_copilot_pre_review_banner)
      },
      title: "#{pull.title} by #{author_name} · Pull Request ##{pull.number}",
      layout: "layouts/repository_with_container",
      disable_ssr: true, # disabled until this app is ready for SSR
    )
  end

  def toggle_new_mergebox # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless logged_in? && request&.method == "POST" && user_feature_enabled?(:mergebox_react_partial)
    pull_number = params[:pull_number]
    new_state = params[:new_state]
    redirect_path = if pull_number
      show_pull_request_path(current_repository.owner_display_login, current_repository.name, pull_number)
    else
      :back
    end

    if !current_user&.feature_preview_enabled?(:mergebox_react_partial, enrolled_by_default_override: user_feature_enabled?(:new_merge_experience_opt_out_by_default))
      current_user&.enable_feature_preview(:mergebox_react_partial) unless new_state == "disabled"
      if request&.xhr?
        head :ok
      else
        redirect_to redirect_path.to_s + "?new_mergebox=true"
      end
    else
      current_user&.disable_feature_preview(:mergebox_react_partial) unless new_state == "enabled"
      if request&.xhr?
        head :ok
      else
        redirect_to redirect_path.to_s + "?new_mergebox=false"
      end
    end
  end

  def toggle_generic_feature # rubocop:todo GitHub/UseRestfulActions
    feature_name = params[:feature_name]

    return render_404 unless logged_in?
    return render_404 unless user_feature_enabled?(feature_name)

    if current_user&.feature_preview_enabled?(feature_name)
      current_user&.disable_feature_preview(feature_name)
    else
      current_user&.enable_feature_preview(feature_name)
    end

    feature_toggle_redirect

  end

  private

  sig { returns T::Hash[Symbol, T.untyped] }
  def app_payload_props_for_copilot_pre_review_banner
    return {} unless logged_in? && user_feature_enabled?(:copilot_reviews)

    {
      copilotPreReviewBannerPayload: {
        analyticsPath: copilot_pull_request_review_banner_path(
          params[:user_id],
          params[:repository],
          pull_request_node_id: pull.global_relay_id,
        ),
        threadName: PullRequests::Copilot::CodeReviewThreadNameGenerator.call(pull_request: pull),
        apiURL: copilot_api_url,
        signedWebsocketChannel: GitHub::WebSocket::Channels.signed_pull_request(pull),
        ssoOrganizations: sso_organizations,
      }
    }
  end

  sig { returns(String) }
  memoize def copilot_api_url
    with_database_error_fallback(fallback: "") do
      Copilot::SKUIsolation.for_user(current_user).api.endpoint
    end
  end

  def find_pull_request
    PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
  end

  def add_client_feature_flags
    add_client_feature_flag([
      :issues_react_prefetch,
      :use_pull_request_subscriptions_enabled,
    ])
  end

  # Internal: Extract OID components from PR range.
  #
  #   /github/github/pull/123/files/abc123..def456
  #   /github/github/pull/123/files/def456
  #
  # pull  - Current PullRequest
  # range - String range parameter
  #
  # If a complete range is given, a pair of resolved String OIDs will be
  # returned. If only one end sha is given, nil and a resolved String OID
  # will be returned. Otherwise nil is returned if no range was matched.
  def parse_show_range_oid_components(pull, range)
    if match = range.to_s.match(/\A(?<sha1>[a-fA-F0-9]{7,40})\.\.(?<sha2>[a-fA-F0-9]{7,40})\z/)
      sha1 = match[:sha1]
      sha2 = match[:sha2]
      [sha1, sha2] if sha1 && sha2
    elsif match = range.to_s.match(/\A(?<sha2>[a-fA-F0-9]{7,40})\z/)
      sha2 = match[:sha2]
      [nil, sha2] if sha2
    end
  end

  def is_overview_page?
    params &&
      (params[:controller] == "pull_requests" && params[:action] == "show" && params[:tab].nil?) ||
      (params[:controller] == "voltron/pull_requests_fragments" && params[:action] == "pull_request_layout")
  end

  def is_files_page?
    params && params[:controller] == "pull_requests" && (params[:action] == "files" || (params[:action] == "commits" && params[:range].present?))
  end

  def is_activity_page?
    params && params[:controller] == "pull_requests" && params[:action] == "show" && params[:tab] == "activity"
  end

  def is_commits_page?
    params && params[:controller] == "pull_requests" && params[:action] == "commits" && !params[:range].present?
  end

  # Matches requests to deprecated single file page route `/pull/:id/file/*path`, which are now routed to
  # pull_request#show via the catch-all `/pull/*id` route.
  def is_single_file_page?
    params && params[:controller] == "pull_requests" && params[:action] == "show" && params[:id] =~ /\d\/file\//
  end

  def get_preload_headers(common_query_vars, pull, range)
    start_oid, end_oid = parse_show_range_oid_components(pull, range)
    commit_range_params, has_range =
      if start_oid && end_oid
        [{ startOid: start_oid, endOid: end_oid, isSingleCommit: false }, true]
      elsif end_oid
        [{ singleCommitOid: end_oid, isSingleCommit: true }, true]
      else
        [{}, false]
      end

    common_query_vars_with_range = common_query_vars.merge(commit_range_params)
    common_query_vars_with_timeline_page_size = common_query_vars.merge({ timelinePageSize: Timeline::PullRequestTimeline::PAGE_SIZE })
    common_queries = [
      GraphQLRequest.new(
        query: PRX_HEADER_QUERY,
        variables: common_query_vars_with_range
      ),
      GraphQLRequest.new(
        query: PRX_MAIN_CONTENT_AREA_QUERY,
        variables: common_query_vars_with_range
      ),
    ]

    if is_overview_page?
      return [
        *common_queries,
        GraphQLRequest.new(
          query: PRX_BODY_QUERY,
          variables: common_query_vars
        ),
        GraphQLRequest.new(
          query: PRX_SECONDARY_CONTENT_QUERY,
          variables: common_query_vars_with_timeline_page_size
        ),
        GraphQLRequest.new(
          query: PRX_DETAILS_PANE_QUERY,
          variables: common_query_vars
        ),
      ]
    end

    if is_files_page?
      files_page_queries = [
        *common_queries,
        GraphQLRequest.new(
          query: PRX_FILES_QUERY,
          variables: common_query_vars_with_range
        ),
      ]

      files_page_queries.push(
        GraphQLRequest.new(
          query: PRX_MARKERS_COMMENTS_SIDESHEET_QUERY,
          variables: common_query_vars
        )
      ) unless has_range

      return files_page_queries
    end

    if is_activity_page?
      return [
        *common_queries,
        GraphQLRequest.new(
          query: PRX_ACTIVITY_QUERY,
          variables: common_query_vars_with_timeline_page_size
        ),
      ]
    end

    if is_commits_page?
      return [
        *common_queries,
        GraphQLRequest.new(
          query: PRX_COMMITS_QUERY,
          variables: common_query_vars
        ),
        GraphQLRequest.new(
          query: PRX_COMMITS_SECONDARY_CONTENT_QUERY,
          variables: common_query_vars
        ),
      ]
    end

    []
  end

  memoize def default_merge_method
    Platform::Models::PullRequestMergeRequirements.new(pull, nil, nil, nil, current_user).merge_method.sync.upcase
  end

  def pull
    @pull
  end

  sig { void }
  def feature_toggle_redirect
    if request&.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  # Override to add to allowlist for advisory workspace repositories.
  def route_supports_advisory_workspaces?
    action_name == "toggle_new_mergebox"
  end
end
