# typed: false
# frozen_string_literal: true

class CommitsController < GitContentController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::Ballast,
    only: [:show, :deferred_commit_data]

  depends_on_clusters ApplicationRecord::RepositoriesActionsChecks,
    only: [:show, :deferred_commit_data],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    only: [:commits_list_item]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :commits_list_item],
    optional: true

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    only: [:commits_list_item],
    optional: true

  rate_limit_requests \
    only: [:show],
    if: :request_is_rate_limited?,
    key: :commits_rate_limit_key,
    max: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_MAX,
    ttl: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_TTL

  PAGE_SIZE = 35

  helper :diff
  layout :current_layout
  javascript_bundle :repositories
  stylesheet_bundle :code

  skip_before_action :try_to_expand_path
  skip_before_action :cap_pagination

  include BranchesHelper
  include CommitHelper
  include ControllerMethods::Commit
  include Commits::ReactPayloadDataDependency
  include GitHub::RateLimitedRequest
  include TextHelper
  include Repos::CodeViewHelper

  self.react_bundle_name = "commits"

  def show
    if react_commits_enabled?
      # Serve json if soft-nav
      request.format = :json if request.headers["Accept"] == "application/json"
    end
    respond_to do |format|
      format.html do
        show_html
      end
      format.json do
        show_html
      end
      format.atom do
        set_header_for_no_index_and_no_follow
        show_feed
      end
    end
  end

  def show_html # rubocop:todo GitHub/UseRestfulActions
    fix_up_pagination_params!

    if commit_oid = current_repository.ref_to_sha(tree_name)
      # this raises ObjectMissing when the commit does not exist
      current_repository.commits.find(commit_oid)
    end

    render_show_html
  rescue GitRPC::ObjectMissing, Platform::Errors::Cursor
    render_404
  end

  def show_feed # rubocop:todo GitHub/UseRestfulActions
    path = path_string.presence
    commit = repository_commit
    return render_404 unless commit.present?

    etag_commits, _ = repository_commits(commit, path, pagination_params: { first: 1 })
    etag = etag_commits&.first&.oid

    if etag.present?
      fresh_when strong_etag: etag, template: false

      return if performed?
    else
      return render_404
    end

    commits, _ = repository_commits(commit, path, pagination_params: { first: 20 })
    return render_404 unless commits.present?

    # Prefill author actors
    Promise.all(commits.map { |commit| commit.author_actor.async_visible_actor(current_user) }).sync

    render "commits/feed", layout: false, locals: { commits: commits }
  end

  def deferred_commit_contributors # rubocop:todo GitHub/UseRestfulActions
    contributors = current_repository.top_contributors(
      limit: 100,
      viewer: current_user,
    )
    contributors.map! do |contributor|
      {
        primaryAvatarUrl: contributor.primary_avatar_url(nil),
        path: user_path(contributor),
        login: contributor.display_login,
        name: nil,
      }
    end

    if current_user
      contributors = contributors.delete_if { |contributor| contributor[:login] == current_user.display_login }
      contributors.insert(0, {
        primaryAvatarUrl: current_user.primary_avatar_url(nil),
        path: user_path(current_user),
        login: current_user.display_login,
        name: nil,
      })
    end

    respond_to do |format|
      format.json do
        render json: { authors: contributors }
      end
    end
  end

  def deferred_commit_data # rubocop:todo GitHub/UseRestfulActions
    if commit_oid = current_repository.ref_to_sha(tree_name)
      # this raises ObjectMissing when the commit does not exist
      current_repository.commits.find(commit_oid)
    end

    commit = repository_commit
    path = path_string.presence
    commits, pagination_cursor = repository_commits(commit, path) if commit.present?

    if pagination_cursor && !pagination_cursor.has_next_page? && current_repository && path && commits.present?
      begin
        diff = current_repository.rpc.diff_tree_path_renamed(commits.last.oid, similarity_index: 50, new_path: utf8(path))
      rescue GitRPC::CommandFailed, GitRPC::Timeout, GitRPC::ObjectMissing
        diff = []
      end

      rename_history = {
        historyUrl: commits_path((diff[1] if !diff.empty?) || nil, commits.last.oid, current_repository) + "?browsing_rename_history=true&new_path=#{params[:new_path] || path}&original_branch=#{utf8(params[:original_branch] || params[:branch])}",
        hasRenameCommits: !diff.empty?,
        oldName: (diff[1] if !diff.empty?) || nil,
      }
    end

    respond_to do |format|
      format.json do
        render json: { deferredCommits: build_deferred_commit_payload(commits, current_repository, current_user), renameHistory: rename_history }
      end
    end
  end

  def commits_list_item # rubocop:todo GitHub/UseRestfulActions
    return render_404 if params[:name].blank? || current_commit.nil?

    pull_request = if params[:pull_request_id].present?
      with_database_error_fallback(fallback: nil) do
        current_repository.pull_requests.find(params[:pull_request_id])
      end
    end

    render Commits::ListItemComponent.new(commit: current_commit, pull_request: pull_request), layout: false
  end

  def check_for_rename_commits # rubocop:todo GitHub/UseRestfulActions
    inputs = params.require(:items).permit!.to_h.values.first
    key_to_respond_with = params.require(:items).permit!.to_h.keys.first

    if !current_repository
      respond_to do |format|
        format.json { render json: { key_to_respond_with => "" } }
      end
      return
    end


    diff = current_repository.rpc.diff_tree_path_renamed(inputs["last_commit"], similarity_index: 50, new_path: inputs["current_blob_path"])

    to_respond = render_to_string Commits::BrowseRenameCommitsComponent.new(
      current_user: current_repository.owner.display_login,
      current_repository: current_repository,
      last_commit: inputs["last_commit"],
      new_file: inputs[:new_path] || inputs["current_blob_path"],
      old_file: (diff[1] if !diff.empty?) || nil,
      has_rename_commits: !diff.empty?,
      branch: inputs["branch"]), layout: false, formats: [:html]

    respond_to do |format|
      format.json { render json: { key_to_respond_with => to_respond } }
    end
  rescue GitRPC::CommandFailed, GitRPC::Timeout, GitRPC::ObjectMissing
    # rubocop:disable GitHub/RailsControllerRenderLiteral
    to_respond = render_to_string Commits::BrowseRenameCommitsComponent.default, layout: false, formats: [:html]

    respond_to do |format|
      format.json { render json: { key_to_respond_with => to_respond } }
    end
  end

  # Handle a request timeout in the show action for any of the supported formats.
  rescue_from_timeout only: [:show] do |_boom|
    respond_to do |format|
      format.html do
        if react_commits_enabled?
          @rendering_react_view = true
          add_client_feature_flag(Commits::ReactPayload.feature_flags)

          render_react_app(
            payload: {
              commitGroups: [],
              currentCommit: {
                oid: "",
              },
              filters: {
                since: params[:since],
                until: params[:until],
                newPath: params[:new_path],
                originalBranch: params[:original_branch],
                currentBlobPath: "",
                pagination: nil,
              },
              metadata: {
                browsingRenameHistory: false,
                showProfileHelp: coming_from_profile?,
                deferredDataUrl: "",
              },
              repo: Repos::ReactPayload.current_repository_payload(
                current_repository,
                current_user_can_push: current_user_can_push?
              ),
              refInfo: {
                name: tree_name,
                listCacheKey: ref_list_cache_key,
                refType: helpers.tree_type,
                currentOid: commit_sha
              },
              timedOutMessage: "git log #{tree_name_for_display ? tree_name_for_display : ""}#{defined?(path).nil? ? "" : path}",
            },
            title: "Timed out",
            app_payload_generator: -> { Commits::ReactPayload.app_payload },
            disable_ssr: !GitHub.flipper[:commits_ux_refresh_ssr].enabled?(current_user),
          )
        else
          render "commits/timeout"
        end

      end

      format.atom do
        set_header_for_no_index_and_no_follow
        render status: 503,
          plain: "Sorry, this feed is taking too long to generate.",
          layout: false
      end

      format.all do
        head 503
      end
    end
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

  def fix_up_pagination_params!
    if page = params.delete(:page)
      if page.to_i > 1
        params[:after] = Platform::ConnectionWrappers::CursorGenerator.generate_cursor((((page.to_i - 1) * PAGE_SIZE) - 1).to_s)
      end
    end
  end

  def render_show_html
    browsing_rename_history = params[:browsing_rename_history]
    path = path_string.presence
    commit = repository_commit
    commits, pagination_cursor = repository_commits(commit, path) if commit.present?

    if react_commits_enabled?
      GitHub.dogstats.increment("repos-react-migration.react", tags: dogstats_request_tags)

      @rendering_react_view = true
      add_client_feature_flag(Commits::ReactPayload.feature_flags)

      valid_params = {
        after: params[:after], before: params[:before], author: params[:author], since: params[:since], until: params[:until], path: path, original_branch: params[:original_branch] || params[:branch], new_path: params[:new_path],
      }

      returned_pagination_cursor = nil
      if !pagination_cursor.nil?
        returned_pagination_cursor = {
          startCursor: pagination_cursor.start_cursor,
          endCursor: pagination_cursor.end_cursor,
          hasNextPage: pagination_cursor.has_next_page,
          hasPreviousPage: pagination_cursor.has_previous_page,
        }
      end

      filter_author = user_or_author_to_filter_on(params[:author])
      author_info = nil
      if filter_author.present? && filter_author.is_a?(User)
        author_info = {
          primaryAvatarUrl: filter_author.primary_avatar_url(nil),
          path: user_path(filter_author),
          login: params[:author],
          name: nil,
        }
      end

      render_react_app(
        payload: {
          commitGroups: build_grouped_commits_payload(commits, current_user),
          currentCommit: {
            oid: commit ? commit.oid : "",
          },
          filters: {
            since: params[:since],
            until: params[:until],
            author: author_info,
            newPath: params[:new_path],
            originalBranch: params[:original_branch],
            currentBlobPath: path,
            pagination: returned_pagination_cursor,
          },
          metadata: {
            browsingRenameHistory: browsing_rename_history,
            showProfileHelp: coming_from_profile?,
            deferredDataUrl: deferred_commit_data_path(name: tree_name, **valid_params),
            deferredContributorUrl: deferred_commit_contributors_path,
            softNavToCommit: react_commit_enabled?,
          },
          repo: Repos::ReactPayload.current_repository_payload(
            current_repository,
            current_user_can_push: current_user_can_push?
          ),
          refInfo: {
            name: tree_name,
            listCacheKey: ref_list_cache_key,
            refType: helpers.tree_type,
            currentOid: commit_sha
          },
          timedOutMessage: "",
        },
        title: path ? "History for #{path} - #{current_repository.name_with_display_owner}" : "Commits · #{current_repository.name_with_display_owner}",
        app_payload_generator: -> { Commits::ReactPayload.app_payload },
        disable_ssr: !GitHub.flipper[:commits_ux_refresh_ssr].enabled?(current_user),
      )
    else
      GitHub.dogstats.increment("repos-react-migration.rails", tags: dogstats_request_tags)

      no_filters_present = [:after, :before, :author, :since, :until].none? { |key| params[key].present? }
      return render_404 if commits.blank? && no_filters_present

      prefill_commit_associations(commits)

      # to track react.request.duration metric for comparison to react app
      request.env[GitHub::TaggingHelper::PROCESS_REQUEST_REACT_TYPE] = "rails"

      render "commits/show", locals: {
        commit: commit,
        commits: commits,
        current_blob_path: path,
        from_profile: coming_from_profile?,
        pagination_cursor: pagination_cursor,
        browsing_rename_history: browsing_rename_history,
      }
    end
  end

  def repository_commits(commit, path, pagination_params: nil)
    pagination_params ||= graphql_pagination_params(page_size: PAGE_SIZE)
    browsing_rename_history = params[:browsing_rename_history]
    arguments = {
      path: path,
      author: author_input,
      since: parsed_since,
      until: parsed_until,
      exclude_parent: ([commit.oid] if browsing_rename_history) || nil,
      commit_oid: commit.oid,
    }

    connection = Platform::ConnectionWrappers::CommitHistory.new(
      commit.repository,
      first: pagination_params[:first],
      last: pagination_params[:last],
      after: pagination_params[:after],
      before: pagination_params[:before],
      arguments: arguments,
      parent: commit,
    )
    [connection.edge_nodes.sync, connection.page_info.sync]
  rescue GitRPC::CommandFailed, GitRPC::Timeout, GitRPC::ObjectMissing, Platform::Errors::Cursor
    [[], nil]
  end

  def repository_commit
    revision = params[:name] || current_repository.default_branch
    if oid = current_repository.ref_to_sha(revision)
      path_prefix = ::Commit.extract_path_prefix_from_expression(revision)
      Platform::Loaders::GitObject.load(current_repository, oid, path_prefix: path_prefix).sync
    end
  end

  def prefill_commit_associations(commits)
    return unless commits.present?

    Commit.prefill_comment_counts(commits)

    promises = commits.flat_map do |commit|
      [
        commit.author_actors.map { |git_actor| [git_actor.async_visible_actor(current_user), git_actor.async_commits_path_uri] },
        commit.committer_actor.async_visible_actor(current_user),
        commit.committer_actor.async_commits_path_uri,
        commit.async_authored_by_committer?,
        commit.async_short_message_html,
        commit.async_has_status_check_rollup?,
        commit.async_unique_visible_author_actors(current_user).then { |authors| authors.map { |author| author.async_visible_user(current_user) } },
      ].flatten
    end

    Promise.all(promises).sync
  end

  def author_input
    if params[:author]
      author = user_or_author_to_filter_on(params[:author])

      case author
      when ::User
        { id: author.global_relay_id }
      when ::String
        { emails: [author] }
      when ::Array
        { emails: author.map(&:to_s) }
      end
    end
  end

  def parsed_since
    date = parse_date(params[:since]) or return
    date.at_beginning_of_day.utc
  end

  def parsed_until
    date = parse_date(params[:until]) or return
    # the `until` date is inclusive, so we go until the beginning of the next day
    date += 1.day
    date.at_beginning_of_day.utc
  end

  # Parses a ISO8601 date from a param string into a TimeWithZone at 00:00:00
  # in the current user's time zone
  def parse_date(str)
    date = begin
      Date.iso8601(str)
    rescue ArgumentError
      return
    end
    date.in_time_zone(current_user&.time_zone || Time.zone)
  end

  # Handle auth specifics for feed requests.
  include GitHub::Authentication::Feed

  # Private: Actions that can response to atom requests.
  #
  # Returns an Array or Strings.
  def feed_actions
    %w(show)
  end

  # Private: find a User via login, or just return the search
  # string that is passed in (which is the case where the user is
  # searching for an email)
  #
  # Returns a User or a String
  def user_or_author_to_filter_on(author)
    User.find_by_login(author) || author
  end

  # Private: determines if the referral is coming from the
  # user profile page
  #
  # Returns a Boolean
  def coming_from_profile?
    referring_route = github_internal_referrer_route

    return false if referring_route.nil?

    referring_route[:controller] == "profiles" && referring_route[:action] == "show"
  end

  def route_supports_advisory_workspaces?
    true
  end

  # Override AbstractRepositoryController#defer_commit_badges? to
  # opt-in to deferred loading of commit signature badges.
  def defer_commit_badges?
    true
  end

  # Override AbstractRepositoryController#defer_status_check_rollups? to
  # opt-in to deferred loading of status check rollups
  def defer_status_check_rollups?
    true
  end

  def request_is_rate_limited?
    !logged_in? && request.format != "atom"
  end

  def commits_rate_limit_key
    key_base = "#{self.class.to_s.underscore}:#{action_name}"
    actor_identifier = request.env.fetch("HTTP_X_SSL_JA3_HASH", nil)
    actor_identifier = request.remote_ip if actor_identifier.blank?
    "#{key_base}:#{actor_identifier}"
  end
end
