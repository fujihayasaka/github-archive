# typed: true
# frozen_string_literal: true

module IssuesReactHelper
  extend T::Helpers

  requires_ancestor { ApplicationController }
  requires_ancestor { AbstractRepositoryController }

  abstract!

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  sig { abstract.returns(T.nilable(ActionDispatch::Request)) }
  def request; end

  include GitHub::Memoizer
  include DateMacroHelper
  include RelayHelper
  include ReactHelper
  include InternalGraphqlTracingHelper
  include IssuesReactGraphqlQueries
  include IssuesSubscriptionsHelper
  include SubIssuesReactHelper

  # note that this list also exists in ui/packages/issues-react/constants/queries.ts
  DEFAULT_QUERIES_BY_PATH = {
    "/issues" => { "title": "Issues", "query": "state:open archived:false assignee:@me sort:updated-desc" },
    "/issues/assigned" => { "title": "Assigned to me", "query": "state:open archived:false assignee:@me sort:updated-desc" },
    "/issues/mentioned" => { "title": "Mentioned", "query": "state:open archived:false mentions:@me sort:updated-desc" },
    "/issues/createdByMe" => { "title": "Created by me", "query": "state:open archived:false author:@me sort:updated-desc" },
    "/issues/recentActivity" => { "title": "Recent activity", "query": "involves:@me updated:>@today-1w sort:updated-desc" },
  }

  PULLS_DASHBOARD_QUERIES = {
    "/pulls" => { "title": "Pull Requests", "query": "state:open archived:false involves:@me is:pr updated:>@today-60d sort:updated-desc" },
    "/pulls/assigned" => { "title": "Assigned to me", "query": "state:open archived:false assignee:@me is:pr sort:updated-desc" },
    "/pulls/mentioned" => { "title": "Mentioned", "query": "state:open archived:false mentions:@me is:pr sort:updated-desc" },
    "/pulls/review-requested" => { "title": "Review requested", "query": "state:open archived:false review-requested:@me is:pr sort:updated-desc" },
  }

  REACT_SERVER_INDEX_FEATURE_LIST = [
    :azure_exp_staffbar,
    :bypass_oopfs_query,
    :cache_public_resource_resource,
    :command_palette_commands,
    :disable_react_ssr,
    :elastomer_circuit_breaker_open,
    :gql_report_field_stats,
    :gql_run_analyzers_on_persisted_queries,
    :graphql_graceful_degredation,
    :hydro_async_sink,
    :hydro_gateway_publish,
    :invalidate_private_profile_searches,
    :issues_advanced_search,
    :issues_react_close_as_duplicate,
    :issues_advanced_search_performance_validation,
    :issue_and_pulls_search_increase_timeout,
    :issues_react_perf_test,
    :issues_react_v2,
    :issues_react_logged_out,
    :issues_react_helper_logging,
    :issues_react_helper_logging_timing_data,
    :issues_react_use_defer_directive,
    :persisted_tracer_mode,
    :persisted_tracer_debug_mode,
    :new_pulls_dashboard,
    :optimize_single_repo_filter,
    :platform_authorization_log_authz_decision,
    :secure_user_to_server_search,
    :skip_open_graph_url_encoding,
    :graphql_preload_business_user_accounts,
    :graphql_memoize_actor_limiter,
    :graphql_skip_reauthorize_scoped_items,
    :graphql_track_allocated_objects,
  ]

  REACT_SERVER_CREATE_FEATURE_LIST = [
    :cache_public_resource_resource,
    :disable_react_ssr,
    :global_health_files_repository_loader_new_fetch_implementation,
    :gql_report_field_stats,
    :gql_run_analyzers_on_persisted_queries,
    :graphql_graceful_degredation,
    :issues_react_fix_template_url,
    :issues_react_perf_test,
    :issues_react_v2,
    :issues_react_logged_out,
    :issues_react_helper_logging,
    :issues_react_helper_logging_timing_data,
    :issues_react_use_defer_directive,
    :persisted_tracer_mode,
    :persisted_tracer_debug_mode,
    :owner_scoped_github_apps,
    :platform_authorization_log_authz_decision,
    :slash_commands,
    :two_factor_cap_enforcement,
    :graphql_memoize_actor_limiter,
    :graphql_skip_reauthorize_scoped_items,
    :graphql_track_allocated_objects,
  ]

  REACT_SERVER_SHOW_FEATURE_LIST = [
    :adaptive_card_markdown_parsing,
    :azure_exp_staffbar,
    :cache_public_resource_resource,
    :command_palette_commands,
    :cpq_check,
    :disable_react_ssr,
    :early_hints,
    :goomba_tlb_filter_first,
    :gql_field_tracer,
    :persisted_tracer_mode,
    :persisted_tracer_debug_mode,
    :gql_n_plus_one_tracer,
    :gql_read_arguments_from_replicas,
    :gql_report_field_stats,
    :gql_run_analyzers_on_persisted_queries,
    :gql_run_native_analyzers,
    :graphql_graceful_degredation,
    :hierarchy_cache_key,
    :hydro_async_sink,
    :hydro_gateway_publish,
    :insights_codeblocks,
    :new_pulls_dashboard,
    :platform_authorization_log_authz_decision,
    :issues_react,
    :issues_react_perf_test,
    :issues_react_v2,
    :issues_react_logged_out,
    :issues_react_helper_logging,
    :issues_react_helper_logging_timing_data,
    :issues_react_use_defer_directive,
    :new_pulls_dashboard,
    :secure_user_assets_auth_check,
    :tasklist_block_input_validation,
    :tasklist_block_markdown_at_rest,
    :tasklist_block_nested_html_pipeline,
    :tasklist_block_precache,
    :sub_issues,
    :graphql_preload_business_user_accounts,
    :graphql_memoize_actor_limiter,
    :graphql_skip_reauthorize_scoped_items,
    :projects_classic_sunset_ui,
    :projects_classic_sunset_override,
    :graphql_track_allocated_objects,
    :refresh_image_video_src,
    :issues_react_close_as_duplicate,
    :sub_issues_perf_testing
  ]

  REACT_CLIENT_FEATURE_LIST = [
    :use_pull_request_subscriptions_enabled,
    :pull_request_single_subscription,
    :disable_issues_react_ssr,
    # Temporarily required to instantiate Profiles::Kv (which backs preferred_emoji_skin_tone) during dual-write transition period
    :profiles_write_to_target,
    :issues_react,
    :issues_react_prefetch,
    :issue_types,
    :issues_react_dashboard_saved_views,
    :copilot_workspace,
    :sub_issues,
    :copilot_natural_language_github_search,
    :issues_react_ui_commands_migration,
    :private_avatars,
    :reserved_domain,
    :projects_classic_sunset_ui,
    :projects_classic_sunset_override,
    :issues_react_new_timeline,
    :refresh_image_video_src,
    :issues_react_bypass_es_limits,
    :issues_react_close_as_duplicate,
    :issues_react_customise_notifications_ui,
    :notifyd_issue_watch_activity_notify,
    :notifyd_enable_issue_thread_subscriptions,
    :issues_react_new_sort_dropdown,
  ]

  # callbacks that are called when a specific query is done (and could depend on its result )
  def get_query_callbacks
    return {} unless logged_in?
    callbacks_hash = {}

    # issues#index
    ["/:owner/:repo/issues"].each do |path|
      callbacks_hash[path] = ->(query_id, result) {
        return unless query_id == ISSUE_INDEX_PAGE_QUERY.graphql_query_id
        # Adding a 'Link' header to the response to preload the secondary query.  This depends on the node IDs from the result of the main query
        # check if we have a repo scoped search or a global search
        edges = (result.dig("data", "repository", "search", "edges") || result.dig("data", "search", "edges") || [])

        # get all the issue and pull request ids from the search result
        ids = edges
        .compact
        .map { |edge| edge.dig("node", "id") }
        .flatten
        .compact
        .filter { |id| id.start_with?("I_", "PR_") }

        set_preload_header([
          GraphQLRequest.new(
            query: ISSUE_INDEX_SECONDARY_QUERY_PATH,
            variables: {
              nodes: ids,
              includeReactions: false,
            }
          )
        ])
      }
    end

    callbacks_hash
  end

  def get_precompute_subscription_hash(preload_pull_requests: false)
    return {} unless logged_in?
    subscription_hash = {}

    # issues#dashboard
    ["/issues", "/issues/assigned", "/issues/mentioned", "/issues/createdByMe", "/issues/recentActivity"].each do |path|
      subscription_hash[path] = ->(query_id, result) {
        IssuesSubscriptionsHelper.compute_subscriptions_for_issues_dashboard_query(query_id, result, path, preload_pull_requests:)
      }
    end

    # issues#dashboard, custom views
    ["/issues/:id"].each do |path|
      subscription_hash[path] = ->(query_id, result) {
        return nil unless query_id == ISSUE_DASHBOARD_CUSTOM_VIEW_PAGE_QUERY.graphql_query_id
        IssuesSubscriptionsHelper.get_hash_for_path(path, query_id, result)
      }
    end

    # issues#index
    ["/:owner/:repo/issues"].each do |path|
      subscription_hash[path] = ->(query_id, result) {
        IssuesSubscriptionsHelper.compute_subscriptions_for_issues_index_query(query_id, result, path, preload_pull_requests:)
      }
    end

    # issues#show
    subscription_hash["/:owner/:repo/issues/:number"] = ->(query_id, result) {
      IssuesSubscriptionsHelper.compute_subscriptions_for_issue_viewer_query(query_id, result)
    }
    subscription_hash
  end

  DEFAULT_ISSUE_SEARCH_PAGE_SIZE = 25
  MAX_ISSUE_SEARCH_PAGE_SIZE = 100

  def get_variable_overwrite_hash
    issues_react_new_timeline = feature_enabled_globally_or_for_user?(feature_name: :issues_react_new_timeline)

    variable_hash = {
      "/issues/assigned" => ->(variables) {
        variables[:query] = DEFAULT_QUERIES_BY_PATH["/issues/assigned"][:query]
        variables = set_page_variables(variables)

        variables
      },
      "/issues/mentioned" => ->(variables) {
        variables[:query] = DEFAULT_QUERIES_BY_PATH["/issues/mentioned"][:query]
        variables = set_page_variables(variables)

        variables
      },
      "/issues/createdByMe" => ->(variables) {
        variables[:query] = DEFAULT_QUERIES_BY_PATH["/issues/createdByMe"][:query]
        variables = set_page_variables(variables)

        variables
      },
      "/issues/recentActivity" => ->(variables) {
        # TODO handle @today in query
        variables[:query] = replace_today_macro(DEFAULT_QUERIES_BY_PATH["/issues/recentActivity"][:query])
        variables = set_page_variables(variables)

        variables
      },
      "/:owner/:repo/issues/:number" => ->(variables) {
        variables[:id] = "repository"
        variables[:useNewTimeline] = issues_react_new_timeline
        variables
      },
      "/:owner/:repo/issues/:number/parallel" => ->(variables) {
        variables[:id] = "repository"
        variables
      },
      "/issues" => ->(variables) {
        variables[:query] = replace_today_macro(params[:q])
        variables[:includeReactions] = query_contains_reactions?(variables[:query])
        variables = set_page_variables(variables)

        variables
      },
      "/:owner/:name/issues/new" => ->(variables) {
        # These define all of the metadata params that we support
        if params[:assignees].present?
          variables[:assigneeLogins] = params[:assignees]
          variables[:withAssignees] = true
        end

        if params[:labels].present?
          variables[:labelNames] = params[:labels]
          variables[:withLabels] = true
        end

        if params[:milestone].present?
          variables[:milestoneTitle] = params[:milestone]
          variables[:withMilestone] = true
        end

        if params[:projects].present?
          valid_project_numbers = parse_valid_project_numbers_from_url_parameter(
            owner: scoped_repository[:owner],
            projects_with_owners: params[:projects])

          if valid_project_numbers.size > 0
            variables[:projectNumbers] = valid_project_numbers
            variables[:withProjects] = true
          end
        end

        discussion_number = Integer(params[:created_from_discussion_number], exception: false)
        variables[:discussionNumber] = discussion_number
        variables[:includeDiscussion] = !!discussion_number

        if params[:type].present?
          variables[:type] = params[:type]
          variables[:withType] = true
        end

        variables[:includeTemplates] = true
        variables[:withAnyMetadata] = variables[:withAssignees] || variables[:withLabels] || variables[:withMilestone] || variables[:withProjects] || variables[:withType] || variables[:includeDiscussion] || false
        variables[:withTriagePermission] = variables[:withType] || variables[:withProjects] || false

        variables
      },
      "/:owner/:name/issues/new/choose" => ->(variables) {
        variables[:includeTemplates] = true

        if params[:milestone].present?
          variables[:milestoneTitle] = params[:milestone]
          variables[:withMilestone] = true
        end

        variables[:withAnyMetadata] = variables[:withMilestone] || false
        variables
      },
      "/issues/:id" => ->(variables) {
        if !@custom_shortcut.nil?
          variables[:query] = replace_today_macro(@custom_shortcut.query)
          variables[:includeReactions] = query_contains_reactions?(variables[:query])
        end
        variables
      },
    }

    [
      "/:owner/:repo/issues",
      "/:owner/:repo/issues/created_by/:author",
      "/:owner/:repo/issues/created_by/app/:author",
      "/:owner/:repo/issues/assigned/:assignee",
      "/:owner/:repo/issues/mentioned/:mentioned",
    ].each do |url|
      variable_hash[url] = ->(variables) {
        current_query = if params[:q].nil?
          "is:issue state:open"
        else
          params[:q]
        end
        current_query = get_custom_query(current_query, params)
        variables[:query] = get_repo_query(query: current_query, owner: scoped_repository[:owner], name: scoped_repository[:name])

        variables = set_page_variables(variables)

        variables[:owner] = scoped_repository[:owner]
        variables[:name] = scoped_repository[:name]
        variables[:includeReactions] = query_contains_reactions?(variables[:query])
        variables
      }
    end

    variable_hash
  end

  def set_page_variables(variables)
    page_size = DEFAULT_ISSUE_SEARCH_PAGE_SIZE

    if !params[:pageSize].nil? && params[:pageSize].to_i > 0
      page_size = [params[:pageSize].to_i, MAX_ISSUE_SEARCH_PAGE_SIZE].min
      variables[:first] = page_size
    end

    if !params[:page].nil? && (params[:page].is_a? Integer) && params[:page].to_i > 1
      variables[:skip] = (params[:page].to_i - 1) * page_size
    else
      variables[:skip] = 0
    end

    variables
  end

  # We want to only return valid integer numbers that are a part of the underlying owner.
  # For example, `projects_with_owners` could be `github/1,github/2` and we want to return [1,2]
  def parse_valid_project_numbers_from_url_parameter(owner:, projects_with_owners:)
    # We support at most 20 projects
    projects = projects_with_owners.split(",").take(20)
    valid_numbers = []
    projects.each do |project|
      project_owner, project_number_s = project.split("/")
      project_number = project_number_s.to_i
      if project_owner == owner && project_number.to_s == project_number_s && project_number > 0
        valid_numbers.push(project_number)
      end
    end

    valid_numbers
  end

  # Modify the query to include the custom parameters: creator, assignee, mentioned
  def get_custom_query(query, params)
    query += " author:#{params[:creator]}" if params[:creator]
    query += " assignee:#{params[:assignee]}" if params[:assignee]
    query += " mentions:#{params[:mentioned]}" if params[:mentioned]

    query
  end

  # Get a query to execute from a user input query and an optional scoped repository
  # Warning, this function must stay in sync with its counterpart in the backend
  # see ui/packages/list-view-items-issues-prs/utils/query.ts#get_query
  def get_repo_query(query:, owner:, name:)
    advanced_search_enabled = feature_enabled_globally_or_for_user?(feature_name: :issues_advanced_search) || GitHub.issues_react_ghes_enabled?

    query = replace_today_macro(query)
    parsed_query = Search::Queries::IssueQuery.parse(query)
    deduplicated_query = remove_duplicate_values(parsed_query)

    sort_qualifier_specified = deduplicated_query.map { |e| e.is_a?(Array) && e[0] }.compact.include?(:sort)
    sort_qualifier = sort_qualifier_specified ? "" : " sort:created-desc"

    # This implementation aims for functional equivalency with the *non* feature-flagged implementation with one main
    # exception: it does *not* reorder the query to move search terms to the front of the string. This is to support
    # the addition of Boolean operators in the query itself (which would be rendered useless by reordering).
    if advanced_search_enabled
      removed_values = parsed_query - deduplicated_query

      # Remove each of the deduplicated values as determined by remove_duplicate_values
      # from the raw query string
      removed_values.each do |filter|
        str = "#{filter[0]}:#{filter[1]}"
        query.gsub!(str, "")
      end

      # when we scope a query to a given repo, we want to make sure to ignore
      # any user entered search qualifier about repo/org/user to make sure to pull
      # issues only from the scoped repository
      query.gsub!(/(org|user|repo):[\w\-\/+\.@]+/, "")

      # Replace any whitespace with a single space
      query.gsub!(/\s+/, " ")

      query = query.strip
      query += " " if query.size > 0
      return "#{query}repo:#{owner}/#{name}#{sort_qualifier}" # rubocop:disable GitHub/DoNotAllowLogin
    end

    scoped_query = ""
    free_text = ""
    deduplicated_query.each do |component|
      if component.is_a?(String)
        free_text += "#{component} "
      elsif component.is_a?(Array) && component.size == 2
        key = component[0].to_s
        value = component[1]

        if value.is_a?(String) && value.include?(" ")
          value = "\"#{value}\""
        end

        # when we scope a query to a given repo, we want to make sure to ignore
        # any user entered search qualifier about repo/org/user to make sure to pull
        # issues only from the scoped repository
        if key != "repo" && key != "org" && key != "user"
          scoped_query += "#{key}:#{value} "
        end
      end
    end
    full_query = "#{free_text}#{scoped_query}"

    rewritten_query = full_query.strip
    rewritten_query += " " if rewritten_query.size > 0

    "#{rewritten_query}repo:#{owner}/#{name}#{sort_qualifier}" # rubocop:disable GitHub/DoNotAllowLogin
  end

  def remove_duplicate_values(parsed_query)
    values_for_is = []
    values_for_type = []

    # Getting all of the values for 'is' and 'type'
    parsed_query.each do |component|
      if component.is_a?(Array) && component.size == 2
        key = component[0].to_s
        value = component[1]

        if key == "is"
          values_for_is.push(value)
        elsif key == "type"
          values_for_type.push(value)
        end
      end
    end

    return parsed_query if values_for_is.empty? && values_for_type.empty?

    has_type_value = {
      issue: values_for_is.include?("issue"),
      pr: values_for_is.include?("pr"),
    }

    new_parsed_query = []

    parsed_query.each do |component|
      if component.is_a?(Array) && component.size == 2
        key = component[0].to_s
        value = component[1]
        if key == "type"
          # if is:issue or is:pr is already set, we don't want to add type:issue or type:pr
          new_parsed_query << [:type, value] if !has_type_value[value.to_sym]
        else
          new_parsed_query << [key.to_sym, value]
        end
      elsif component.is_a?(String)
        new_parsed_query << component
      end
    end

    new_parsed_query
  end

  def default_queries_by_path
    if pr_react_dashboard_enabled?
      DEFAULT_QUERIES_BY_PATH.merge(PULLS_DASHBOARD_QUERIES)
    else
      DEFAULT_QUERIES_BY_PATH
    end
  end

  memoize def issue_react_dashboard_enabled?
    (current_user&.feature_preview_enabled?(:issues_react) && user_feature_enabled?(:issues_react))
  end

  memoize def pr_react_dashboard_enabled?
    user_feature_enabled?(:new_pulls_dashboard)
  end

  memoize def issue_react_enabled?
    if logged_in?
      # issues_react_v2 flag is enabled on the org
      return true if owner.is_a?(Organization) && owner.feature_enabled?(:issues_react_v2)

      return true if owner.is_a?(Organization) && owner.feature_enabled?(:issues_react_logged_out)

      # if the issues_react_v2 flag is not enable on the org, it must be on the user with feature preview enabled
      return true if user_feature_enabled?(:issues_react_v2) && current_user&.feature_preview_enabled?(:issues_react_v2)

      # issues_react_v2 is fully enabled
      return true if GitHub.flipper[:issues_react_v2].enabled?
    else
      # do not use issues react for robot until we have clarified how this could impact SEO
      return false if robot?

      # issues_react_logged_out flag is enabled on the org
      return true if owner.is_a?(Organization) && owner.feature_enabled?(:issues_react_logged_out)

      # issues_react_logged_out flag is fully enabled
      return true if GitHub.flipper[:issues_react_logged_out].enabled?
    end

    # enabled on GHES through an env var, disabled otherwise
    GitHub.issues_react_ghes_enabled?
  end

  memoize def emoji_skin_tone_preference
    return nil unless logged_in?
    current_user&.profile_settings.preferred_emoji_skin_tone
  end

  def is_issue_dashboard_path?
    params[:controller] == "issues" && params[:action] == "dashboard" && request&.path&.start_with?("/issues")
  end

  def is_pr_dashboard_path?
    params[:controller] == "issues" && params[:action] == "dashboard" && request&.path&.start_with?("/pulls")
  end

  def is_issue_show_path?
    if !params || !(
      (params[:controller] == "issues" && params[:action] == "show") ||
      (params[:controller] == "voltron/issues_fragments" && params[:action] == "issue_conversation_content")
    )
      return false
    end

    true
  end

  def is_issue_show_legacy_path?
    if params && (params[:legacy] && params[:id])
      return true
    end
    false
  end

  def is_issue_new_path?
    request&.path&.ends_with?("/issues/new") || request&.path&.ends_with?("/issues/new/choose")
  end

  def is_excluded_view?
    # Exclude paths that are not supported by the React app
    # See https://github.com/github/issues/issues/12419
    controller_name == "issues" && action_name == "index" && (params[:label_name] || params[:milestone_name])
  end

  def is_issue_index_path?
    params && params[:controller] == "issues" && params[:action] == "index" && !is_excluded_view?
  end

  def is_issue_create_path?
    params && params[:controller] == "issues" && (params[:action] == "new" || params[:action] == "choose") \
      && is_issue_new_path?
  end

  def is_issue_index_author_path?
    # This is covering the case where we are on the index page and we are filtering by author using
    # the url /:owner/:repo/issues/:author
    is_issue_index_path? && params[:creator].present? && !request&.path.include?("/created_by/")
  end

  def created_by_path(author)
    "/#{scoped_repository[:owner]}/#{scoped_repository[:name]}/issues/created_by/#{author}"
  end

  def render_issue_react_dashboard_opt_in?
    feature_enabled_for_current_user?(feature_name: :issues_react) && is_issue_dashboard_path?
  end

  def render_issue_react_index_opt_in?
    is_issue_index_path? && feature_enabled_for_current_user?(feature_name: :issues_react_v2) && !(params && params[:pulls_only] == true)
  end

  def render_issue_react_create_opt_in?
    is_issue_create_path? && feature_enabled_for_current_user?(feature_name: :issues_react_v2)
  end

  def render_issue_v2_opt_out?
    feature_enabled_for_current_user?(feature_name: :issues_react_v2)
  end

  def query_contains_reactions?(query)
    query.include?("sort:reactions-")
  end

  # get the query WITHOUT the defaults applied
  def get_query
    query = default_queries_by_path[request&.path]&.dig(:query)

    if query.nil?
      if @custom_shortcut.present?
        query = @custom_shortcut.query
        if @custom_shortcut.scoping_repository.present?
          # scope the query to scoping repo
          query = "repo:#{@custom_shortcut.scoping_repository.owner.display_login}/#{@custom_shortcut.scoping_repository.name} #{query}"
        end
      else
        # this should never happen
        query = "archived:false"
      end
    end

    if !params[:q].nil?
      query = params[:q]
    end
    query
  end

  def set_shortcut_from_path
    @default_shortcut = default_queries_by_path[request&.path]&.dig(:title)

    # set shortcut for different paths. This way '/inbox/:param1/:param2/...' will be accepted
    # as a valid url in hyperlist. Ex: Splitting by '/' and removing the first empty value returns 'inbox'
    # that is used to set the default shortcut
    unless @default_shortcut
      path = request&.path.split("/").reject(&:empty?).first
    end
    # fetch the passed shortcut by graphQL id
    @custom_shortcut = if params[:shortcut_id].present?
      (
              begin
                typed_object_from_id(
                  [Platform::Objects::SearchShortcut, Platform::Objects::TeamSearchShortcut], params[:shortcut_id]
                )
              rescue Platform::Errors::NotFound
                nil
              end
            )
    else
      nil
    end
  end

  def verify_access_to_shortcut?
    set_shortcut_from_path

    return true if @default_shortcut

    if @custom_shortcut.is_a?(SearchShortcut)
      @custom_shortcut.user&.id == T.must(current_user).id
    else
      @custom_shortcut&.dashboard&.team&.visible_to?(current_user)
    end
  end

  def get_preloaded_records
    # all the records that will be inserted into the relay store before the first query
    # this allow to display the data without waiting for the query response
    preloaded_records = {}
    if !@custom_shortcut.nil?
      preloaded_records[@custom_shortcut.global_relay_id] = {
        __typename: @custom_shortcut&.is_a?(TeamSearchShortcut) ? "TeamSearchShortcut" : "SearchShortcut",
        __id: @custom_shortcut.global_relay_id,
        id: @custom_shortcut.global_relay_id,
        query: @custom_shortcut.query,
        name: @custom_shortcut.name,
        description: @custom_shortcut.description,
        icon: @custom_shortcut.icon,
        color: @custom_shortcut.color,
        scopingRepository: nil
      }

      if !@custom_shortcut.scoping_repository.nil?
        preloaded_records[@custom_shortcut.global_relay_id]["scopingRepository"] = {
          name: @custom_shortcut.scoping_repository.name,
          owner: {
            name: @custom_shortcut.scoping_repository.owner.display_login
          }
        }
      end
    end
    preloaded_records
  end

  def render_app(app_name: "issues-react", catalog_service:, url_override: nil, path_override: nil, skip_layout: false, origin: nil, feedback_url: nil)
    prepare_app_timer = Timer.start
    render_app_timer = nil
    stats = {}

    begin
      owner = current_repository&.owner if scoped_repository
      org = owner if owner.present? && owner.organization?
      is_using_ssr = !is_pr_dashboard_path? && !tracing_enabled? && !feature_enabled_globally_or_for_current_user?(:disable_issues_react_ssr)

      return redirect_to "/issues/assigned" if request&.path == "/issues" && params[:q].nil? && is_using_ssr
      return render_404 if is_issue_dashboard_path? && !verify_access_to_shortcut?

      layout = if skip_layout
        false
      elsif scoped_repository && logged_in?
        layout_for_turbo_request
      elsif logged_in?
        "application"
      else
        # the application layout renders the new site header that is not shipped to logged out users
        # for those users, we default to the layout that renders the old site header
        "repository_with_container"
      end

      custom_tags = [
        "ssr:#{is_using_ssr ? 'true' : 'false'}",
      ]
      url_pattern = GitHub.route_query_mapper.get_matching_url_pattern(request&.path)
      custom_tags << "url_pattern:#{url_pattern[:url]}" if url_pattern.present?

      # adds the referrer_controller_action custom tag
      router_response = Rails.application.routes.recognize_path(request&.path, method: :get)
      controller = GitHub::TaggingHelper.formatted_controller(router_response[:controller])
      action_name = router_response[:action]
      custom_tags << "referrer_controller_action:#{controller}##{action_name}"
      preload_pull_requests = current_user&.feature_enabled?(:pull_request_single_subscription)

      enabled_flags = T.let([], T::Array[T.untyped])
      add_client_feature_flag(
        REACT_CLIENT_FEATURE_LIST,
        entity: org,
      )

      add_client_feature_flag(
        [:tasklist_block],
        entity: org,
      ) do |_feature_name, organization|
        tb_enabled = GitHub.flipper[:tasklist_block].enabled?(organization)
        enabled_flags = enabled_flags.push(:tasklist_block) if tb_enabled
        tb_enabled
      end

      add_client_feature_flag(
        [:issues_react_perf_test],
        entity: org
      ) do |feature_name, organization|
        feature_enabled_globally_or_for_current_user_or_entity?(feature_name, organization) && ENV["LUC_PERFORMANCE"] == "1"
      end

      add_client_feature_flag(
        [:sub_issues],
        entity: owner
      ) do |_feature_name, owner|
        SubIssuesFeature.enabled?(current_repository) || SubIssuesFeature.enabled?(owner)
      end

      enabled_flags.push(:issues_react_close_as_duplicate) if (feature_enabled_globally_or_for_current_user?(:issues_react_close_as_duplicate) \
        || owner&.feature_enabled?(:issues_react_close_as_duplicate))

      if params[:id].to_i > 0
        issues_react_new_timeline = feature_enabled_globally_or_for_user?(feature_name: :issues_react_new_timeline)
        set_preload_header([
          GraphQLRequest.new(
            query: ISSUE_VIEWER_SECONDARY_VIEW_QUERY_PATH,
            variables: {
              owner: current_repository.owner.display_login,
              repo: current_repository.name,
              number: params[:id].to_i,
              markAsRead: true,
              useNewTimeline: issues_react_new_timeline
            }
          )
        ])
      end

      turbo = if scoped_repository
        {
          id: "repo-content-turbo-frame",
          target: "_top",
          action: "advance",
          class: ""
        }
      else
        nil
      end

      run_async_with_defer = use_defer?
      params = {
        app_name: app_name,
        payload: {
          preloaded_records: get_preloaded_records,
        },
        app_payload_generator: -> () {
          team_id = nil
          can_edit_view = true
          if @custom_shortcut&.is_a?(TeamSearchShortcut)
            team_id = @custom_shortcut.dashboard&.team&.global_relay_id
            can_edit_view = @custom_shortcut.dashboard&.team&.adminable_by?(current_user) || @custom_shortcut.dashboard&.team&.member?(current_user) || false
          end
          return {
            initial_view_content: {
              team_id: team_id,
              can_edit_view: can_edit_view
            },
            current_user:
              if logged_in?
                {
                  id: current_user&.global_relay_id,
                  login: current_user&.display_login,
                  avatarUrl: current_user&.primary_avatar_url,
                  is_staff: current_user&.employee?,
                  is_emu: current_user&.is_enterprise_managed?,
                }
              else
                nil
              end,
            current_user_settings: {
              use_monospace_font: current_user&.use_fixed_width_font? || false,
              use_single_key_shortcut: current_user&.settings&.get(:keyboard_shortcuts_preference) == "all",
              preferred_emoji_skin_tone: emoji_skin_tone_preference,
            },
            paste_url_link_as_plain_text: logged_in? ? current_user&.paste_url_link_as_plain_text? : false,
            base_avatar_url: GitHub.alambic_avatar_url,
            feedback_url: feedback_url,
            help_url: GitHub.help_url,
            sso_organizations: action_name == "dashboard" ? sso_organizations : nil,
            tracing: tracing_enabled?,
            tracing_flamegraph: tracing_flamegraph_enabled?,
            catalog_service: catalog_service,
            scoped_repository: scoped_repository,
            proxima: GitHub.multi_tenant_enterprise?,
            render_opt_out: render_issue_v2_opt_out?,
          }
        },
        stats: stats,
        turbo: turbo,
        layout: layout,
        variable_overwrite_fns: get_variable_overwrite_hash,
        precompute_subscription_fns: get_precompute_subscription_hash(preload_pull_requests:),
        query_callback_fns: get_query_callbacks,
        add_query_time_tags_fn: get_sub_issues_add_query_time_tags_fn,
        ssr: !tracing_enabled? && is_using_ssr,
        custom_tags: custom_tags,
        url_override: url_override,
        path_override: path_override,
        enabled_flags: enabled_flags,
        origin: origin,
        run_async_with_defer: run_async_with_defer,
        layout_locals_generator: -> do
          {
            show_announcements: !layout || layout == "application",
            show_archived: !layout || layout == "application",
          }
        end
      }
      prepare_app_timer.stop
      GitHub.dogstats.distribution("request.issues.prepare_react_app.time", prepare_app_timer.elapsed_ms, tags: custom_tags)
      render_app_timer = Timer.start

      render_react_app(**params)
    ensure
      if render_app_timer.present?
        render_app_timer.stop
        GitHub.dogstats.distribution("request.issues.render_react_app.time", render_app_timer.elapsed_ms, tags: custom_tags)
      end

      if feature_enabled_globally_or_for_user?(feature_name: :issues_react_helper_logging)
        log_data = {
          "component" => "issues_react_helper",
          "user" => current_user&.display_login,
          "is_staff" => current_user&.employee?,
          "request_id" => GitHub.context[:request_id],
          "ssr" => is_using_ssr,
          "tracing_enabled" => tracing_enabled?,
          "url_pattern" => url_pattern.present? ? url_pattern[:url] : nil,
          "referrer_controller_action" => "#{controller}##{action_name}",
          "is_react" => "true",
          "url" => request&.url,
          "active_experiment" => active_experiment,
        }
        log_stats = feature_enabled_globally_or_for_user?(feature_name: :issues_react_helper_logging_timing_data)
        stats.each do |key, value|
          # The detailed query timings might generate too much data, so they can be disabled/sampled with a FF
          next if !log_stats && (key == :query_timings || key == :query_deferred_timing_data)
          log_data[key.to_s] = value
        end
        log_data["repo_public"] = current_repository && current_repository.public?
        log_data["prepare_app_duration"] = prepare_app_timer.elapsed_ms
        if render_app_timer.present?
          log_data["render_app_duration"] = render_app_timer.elapsed_ms
        end
        GitHub.logger.info(log_data)
      end
    end
  end

  def issue_react_index_handler(pulls_only: false, url_override: nil, path_override: nil, skip_layout: false)
    return false if pulls_only
    return false unless is_issue_index_path? || is_issue_new_path?
    return false unless issue_react_enabled?
    return redirect_to(created_by_path(params[:creator])) if is_issue_index_author_path?

    GitHub::TaggingHelper.override_action_tag(env: env, action: "index_react")
    GitHub.current_span&.set_attribute(GitHub::TaggingHelper::ACTION_TAG, "index_react")

    feedback_url = "https://gh.io/issues-updates-feedback"

    # using Platform::ORIGIN_INTERNAL under the assumption that authorization happens in the controller flow
    render_app(
      catalog_service: "github/issues_experience",
      origin: Platform::ORIGIN_INTERNAL,
      feedback_url: feedback_url,
      url_override: url_override,
      path_override: path_override,
      skip_layout: skip_layout,
    )
    true
  end

  def issue_react_choose_new_handler
    return false unless is_issue_create_path?
    return false unless logged_in?
    return false unless issue_react_enabled?

    GitHub::TaggingHelper.override_action_tag(env: env, action: "new_react")
    GitHub.current_span&.set_attribute(GitHub::TaggingHelper::ACTION_TAG, "new_react")

    render_app(
      catalog_service: "github/issues_experience",
      origin: Platform::ORIGIN_INTERNAL,
    )
    true
  end

  def issue_react_show_handler(current_issue:, url_override: nil, path_override: nil, skip_layout: false)
    return false unless is_issue_show_path?
    return false unless issue_react_enabled?
    return redirect_to issue_path(current_repository.owner, current_repository, current_issue), status: 301 if is_issue_show_legacy_path?

    GitHub::TaggingHelper.override_action_tag(env: env, action: "show_react")
    GitHub.current_span&.set_attribute(GitHub::TaggingHelper::ACTION_TAG, "show_react")
    render_app(catalog_service: "github/issues_experience", url_override: url_override, path_override: path_override, skip_layout: skip_layout, origin: Platform::ORIGIN_INTERNAL)
    true
  end

  def issue_react_dashboard_handler
    # check if feature preview toggle must be updated
    if logged_in? && params[:new_issues_experience].present? && request&.method == "POST"
      if params[:new_issues_experience] == "true"
        current_user&.enable_feature_preview(:issues_react)
        redirect_to "/issues"
        return true
      elsif params[:new_issues_experience] == "false"
        current_user&.disable_feature_preview(:issues_react)
        redirect_to "/issues"
        return true
      end
    end

    if issue_react_dashboard_enabled? && is_issue_dashboard_path?
      feedback_url = if current_user&.employee?
        "https://github.com/github/issues/discussions/9949"
      else
        "https://github.surveymonkey.com/r/MFKV58Y"
      end

      GitHub::TaggingHelper.override_action_tag(env: env, action: "dashboard_react")
      GitHub.current_span&.set_attribute(GitHub::TaggingHelper::ACTION_TAG, "dashboard_react")
      render_app(catalog_service: "github/issues_experience", origin: Platform::ORIGIN_INTERNAL, feedback_url: feedback_url)

      return true
    end

    # Render React /pulls page if :new_pulls_dashboard feature flag is enabled
    if pr_react_dashboard_enabled? && is_pr_dashboard_path?
      GitHub::TaggingHelper.override_controller_tag(env: env, controller: "pull_requests_react")
      GitHub.current_span&.set_attribute(GitHub::TaggingHelper::CONTROLLER_TAG, "pull_requests_react")
      render_app(app_name: "pulls-dashboard", catalog_service: "github/pull_requests", origin: Platform::ORIGIN_INTERNAL)
      return true
    end

    # 404 for legacy issues when feature flag or feature preview are disabled
    if !issue_react_dashboard_enabled? && params[:shortcut_id].present?
      render_404
      true
    end
  end

  def issue_create_handler
    return false unless logged_in? && request&.method == "POST" && scoped_repository

    # We're handling all the flags here in order to not enable POST routes for #new, #index #choose
    if params[:new_issues_experience].present?
      if params[:new_issues_experience] == "true"
        current_user&.enable_feature_preview(:issues_react_v2)
        redirect_to "/#{scoped_repository[:owner]}/#{scoped_repository[:name]}/issues"

        return true
      elsif params[:new_issues_experience] == "false"
        current_user&.disable_feature_preview(:issues_react_v2)
        redirect_to "/#{scoped_repository[:owner]}/#{scoped_repository[:name]}/issues"

        return true
      end
    end

    if params[:new_create_experience].present?
      if params[:new_create_experience] == "true"
        current_user&.enable_feature_preview(:issues_react_v2)
        redirect_to "/#{scoped_repository[:owner]}/#{scoped_repository[:name]}/issues/new"

        return true
      elsif params[:new_create_experience] == "false"
        current_user&.disable_feature_preview(:issues_react_v2)
        redirect_to "/#{scoped_repository[:owner]}/#{scoped_repository[:name]}/issues/new"

        return true
      end
    end

    false
  end

  private

  memoize def scoped_repository
    return nil unless params && params[:user_id] && params[:repository]
    {
      id: current_repository.global_relay_id,
      owner: params[:user_id],
      name: params[:repository],
      is_archived: current_repository.archived?,
    }
  end

  def sso_organizations
    return [] unless logged_in?
    saml_for_user.protected_organizations.map { |org| { id: org.id.to_s, name: org.name, login: org.display_login } }
  end

  def set_scoped_repo_id
    true
  end

  # helper to see if the @defer or @stream directives should be used
  def use_defer?
    feature_enabled_globally_or_for_user?(feature_name: :issues_react_use_defer_directive)
  end

  def active_experiment
    if GitHub.flipper[:persisted_tracer_debug_mode].enabled?(current_user)
      return "persisted_tracer_debug_mode"
    else
      return "no_active_experiment"
    end
  end
end
