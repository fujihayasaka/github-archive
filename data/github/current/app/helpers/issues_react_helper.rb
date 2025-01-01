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
  include InternalGraphqlTracingHelper
  include IssuesReactGraphqlQueries
  include IssuesSubscriptionsHelper
  include SubIssuesReactHelper

  # note that this list also exists in ui/packages/issues-react/constants/queries.ts
  DEFAULT_QUERIES_BY_PATH = {
    "/issues" => { "title": "Issues", "query": "is:issue state:open archived:false assignee:@me sort:updated-desc" },
    "/issues/assigned" => { "title": "Assigned to me", "query": "is:issue state:open archived:false assignee:@me sort:updated-desc" },
    "/issues/mentioned" => { "title": "Mentioned", "query": "is:issue state:open archived:false mentions:@me sort:updated-desc" },
    "/issues/created" => { "title": "Created by me", "query": "is:issue state:open archived:false author:@me sort:updated-desc" },
    "/issues/recent" => { "title": "Recent activity", "query": "is:issue involves:@me updated:>@today-1w sort:updated-desc" },
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
    :issue_and_pulls_search_increase_timeout,
    :issues_react_perf_test,
    :issues_react_helper_logging,
    :issues_react_helper_logging_timing_data,
    :persisted_tracer_mode,
    :persisted_tracer_debug_mode,
    :new_pulls_dashboard,
    :optimize_single_repo_filter,
    :platform_authorization_log_authz_decision,
    :secure_user_to_server_search,
    :skip_open_graph_url_encoding,
    :graphql_track_allocated_objects,
    :issues_elastic_search_client_error_differentiation,
    :global_health_files_repository_loader_new_fetch_implementation,
    :copilot_swe_agent_disallow,
    :elasticsearch_semantic_indexing_issues, # Semantic indexing POC
    :elasticsearch_semantic_indexing_issues_semantic_search, # Semantic indexing POC
    :elasticsearch_semantic_indexing_issues_show_dupes, # Semantic indexing POC
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
    :issues_react_helper_logging,
    :issues_react_helper_logging_timing_data,
    :persisted_tracer_mode,
    :persisted_tracer_debug_mode,
    :owner_scoped_github_apps,
    :platform_authorization_log_authz_decision,
    :slash_commands,
    :copilot_swe_agent_disallow,
    :graphql_track_allocated_objects,
  ]

  REACT_SERVER_SHOW_FEATURE_LIST = [
    :adaptive_card_markdown_parsing,
    :azure_exp_staffbar,
    :cache_public_resource_resource,
    :command_palette_commands,
    :disable_react_ssr,
    :early_hints,
    :goomba_tlb_filter_first,
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
    :issues_react_perf_test,
    :issues_react_helper_logging,
    :issues_react_helper_logging_timing_data,
    :new_pulls_dashboard,
    :secure_user_assets_auth_check,
    :tasklist_block_input_validation,
    :tasklist_block_markdown_at_rest,
    :tasklist_block_nested_html_pipeline,
    :tasklist_block_precache,
    :projects_classic_sunset_override,
    :graphql_track_allocated_objects,
    :issues_react_create_milestone,
    :copilot_swe_agent_disallow,
    :elasticsearch_semantic_indexing_issues, # Semantic indexing POC
    :elasticsearch_semantic_indexing_issues_semantic_search, # Semantic indexing POC
    :elasticsearch_semantic_indexing_issues_show_dupes, # Semantic indexing POC
  ]

  REACT_CLIENT_FEATURE_LIST = [
    :use_pull_request_subscriptions_enabled,
    :pull_request_single_subscription,
    :disable_issues_react_ssr,
    :issue_dependencies,
    :issue_dependencies_internal_dev,
    :issue_fields,
    :copilot_natural_language_github_search,
    :private_avatars,
    :reserved_domain,
    :projects_classic_sunset_override,
    :issues_react_bypass_es_limits,
    :notifyd_issue_watch_activity_notify,
    :notifyd_enable_issue_thread_subscriptions,
    :timeline_best_effort_count_optimization,
    :copilot_auto_assign_metadata,
    :issues_react_create_milestone,
    :copilot_workspace_cross_repo_selection,
    :copilot_agent_mode,
    :issues_react_duplicate_issue,
    :issues_react_force_turbo_nav,
    :copilot_swe_agent,
    :copilot_plan_brainstorm_with_blackbird,
    :copilot_find_relevant_files,
    :copilot_find_relevant_files_debug,
    :issues_react_create_issue_with_copilot_cta,
    :copilot_immersive_issue_creation_cta,
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
            name: ISSUE_INDEX_SECONDARY_QUERY_NAME,
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
    ["/issues", "/issues/assigned", "/issues/mentioned", "/issues/created", "/issues/recent"].each do |path|
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

    # milestone#show
    ["/:owner/:repo/milestone/:number"].each do |path|
      subscription_hash[path] = ->(query_id, result) {
        IssuesSubscriptionsHelper.compute_subscriptions_for_milestone_show_query(query_id, result)
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
  DEFAULT_ISSUE_MILESTONE_PAGE_SIZE = 25
  DEFAULT_ISSUE_LABEL_PAGE_SIZE = 30

  def get_variable_overwrite_hash
    variable_hash = {
      "/issues/assigned" => ->(variables) {
        variables[:query] = params[:q].blank? ? DEFAULT_QUERIES_BY_PATH["/issues/assigned"][:query] : replace_today_macro(params[:q])
        set_page_variables(variables)
      },
      "/issues/mentioned" => ->(variables) {
        variables[:query] = params[:q].blank? ? DEFAULT_QUERIES_BY_PATH["/issues/mentioned"][:query] : replace_today_macro(params[:q])
        set_page_variables(variables)
      },
      "/issues/created" => ->(variables) {
        variables[:query] = params[:q].blank? ? DEFAULT_QUERIES_BY_PATH["/issues/created"][:query] : replace_today_macro(params[:q])
        set_page_variables(variables)
      },
      "/issues/recent" => ->(variables) {
        variables[:query] = replace_today_macro(params[:q].blank? ? DEFAULT_QUERIES_BY_PATH["/issues/recent"][:query] : params[:q])
        set_page_variables(variables)
      },
      "/:owner/:repo/issues/:number" => ->(variables) {
        variables[:id] = "repository"
        variables
      },
      "/:owner/:repo/milestone/:number" => ->(variables) {
        variables[:id] = "repository"
        # variables = set_page_variables(variables)

        variables[:owner] = scoped_repository[:owner]
        variables[:name] = scoped_repository[:name]
        variables[:number] = Integer(request&.path_parameters&.dig(:number), exception: false)

        show_closed = params[:closed] == "1"
        variables[:query] = "state:#{show_closed ? 'closed' : 'open'} milestone-number:#{variables[:number]} archived:false sort:milestone_prio-desc"
        variables[:first] = DEFAULT_ISSUE_MILESTONE_PAGE_SIZE

        if params[:page].present? && (Integer(params[:page], exception: false)) && params[:page].to_i > 1
          variables[:skip] = (params[:page].to_i - 1) * DEFAULT_ISSUE_MILESTONE_PAGE_SIZE
        else
          variables[:skip] = 0
        end
        variables
      },
      "/:owner/:repo/milestones" => ->(variables) {
        variables[:owner] = scoped_repository[:owner]
        variables[:name] = scoped_repository[:name]
        show_closed = params[:state] == "closed"
        variables[:state] = show_closed ? "CLOSED" : "OPEN"
        sort = params[:sort]
        direction = params[:direction]
        if sort && direction
          if sort == "due_date"
            variables[:orderField] = "DUE_DATE"
          elsif sort == "completeness"
            variables[:orderField] = "COMPLETED"
          elsif sort == "title"
            variables[:orderField] = "ALPHABETICAL"
          elsif sort == "count"
            variables[:orderField] = "ISSUES"
          end

          if direction == "asc"
            variables[:orderDirection] = "ASC"
          else
            variables[:orderDirection] = "DESC"
          end
        end
        variables
      },
      "/:owner/:repo/milestones/new" => ->(variables) {
        variables[:owner] = scoped_repository[:owner]
        variables[:name] = scoped_repository[:name]
        variables
      },
      "/:owner/:repo/milestones/:number/edit" => ->(variables) {
        variables[:owner] = scoped_repository[:owner]
        variables[:name] = scoped_repository[:name]
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
        if !!discussion_number
          variables[:discussionNumber] = discussion_number
          variables[:includeDiscussion] = true
        end

        if params[:type].present?
          variables[:type] = params[:type]
          variables[:withType] = true
        end

        if params[:template].present?
          variables[:templateFilter] = params[:template]
          variables[:withTemplate] = true
        end

        variables[:withTriagePermission] = variables[:withType] || variables[:withProjects] || false

        variables
      },
      "/:owner/:name/issues/new/choose" => ->(variables) {
        variables
      },
      "/issues/:id" => ->(variables) {
        if !params[:q].blank?
          variables[:query] = replace_today_macro(params[:q])
          variables[:includeReactions] = query_contains_reactions?(variables[:query])
        elsif !@custom_shortcut.nil?
          variables[:query] = replace_today_macro(@custom_shortcut.query)
          variables[:includeReactions] = query_contains_reactions?(variables[:query])
        end
        variables
      },
    }

    [
      "/:owner/:repo/labels",
      "/:owner/:repo/issues/labels",
    ].each do |url|
      variable_hash[url] = ->(variables) {
        variables[:owner] = scoped_repository[:owner]
        variables[:name] = scoped_repository[:name]
        # sort is a param that combines the field and the direction
        # for example: name-asc or name-desc
        sort_param = params[:sort]
        if sort_param
          sort = sort_param.split("-").first
          direction = sort_param.split("-").last
          if sort == "name"
            variables[:orderField] = "NAME"
            if direction == "asc"
              variables[:orderDirection] = "ASC"
            else
              variables[:orderDirection] = "DESC"
            end
          elsif sort == "count"
            variables[:orderField] = "ISSUE_COUNT"
            variables[:orderDirection] = direction == "asc" ? "ASC" : "DESC"
          end
        end

        variables[:first] = DEFAULT_ISSUE_LABEL_PAGE_SIZE

        if params[:page].present? && (Integer(params[:page], exception: false)) && params[:page].to_i > 1
          variables[:skip] = (params[:page].to_i - 1) * DEFAULT_ISSUE_LABEL_PAGE_SIZE
        else
          variables[:skip] = 0
        end
        variables
      }
    end

    [
      "/:owner/:repo/issues",
      "/:owner/:repo/issues/created_by/:author",
      "/:owner/:repo/issues/created_by/app/:author",
      "/:owner/:repo/issues/assigned/:assignee",
      "/:owner/:repo/issues/mentioned/:mentioned",
      "/:owner/:repo/labels/:label",
    ].each do |url|
      variable_hash[url] = ->(variables) {
        current_query = if params[:q].nil? || !params[:q].is_a?(String)
          "is:issue state:open"
        else
          params[:q]
        end

        current_query = get_custom_query(current_query, params)
        # For /:owner/:repo/labels/:label, append label filter if not present
        if url == "/:owner/:repo/labels/:label" && params[:label_name].present?
          label_filter = "label:#{params[:label_name]}"
          unless current_query.include?(label_filter)
            current_query = current_query.strip + " " + label_filter
          end
        end

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
    return query if !params[:q].nil? && params[:q].is_a?(String)

    query += " author:#{params[:creator]}" if params[:creator]
    query += " assignee:#{params[:assignee]}" if params[:assignee]
    query += " mentions:#{params[:mentioned]}" if params[:mentioned]

    query
  end

  # Get a query to execute from a user input query and an optional scoped repository
  # Warning, this function must stay in sync with its counterpart in the frontend
  # see ui/packages/list-view-items-issues-prs/utils/query.ts#get_query
  def get_repo_query(query:, owner:, name:)
    query = replace_today_macro(query)
    parsed_query = Search::Queries::IssueQuery.parse(query)
    deduplicated_query = remove_duplicate_values(parsed_query)

    sort_qualifier_specified = deduplicated_query.map { |e| e.is_a?(Array) && e[0] }.compact.include?(:sort)
    sort_qualifier = sort_qualifier_specified ? "" : " sort:created-desc"

    # This implementation aims for functional equivalency with the *non* feature-flagged implementation with one main
    # exception: it does *not* reorder the query to move search terms to the front of the string. This is to support
    # the addition of Boolean operators in the query itself (which would be rendered useless by reordering).
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

    # Replace any whitespace between the search qualifiers with a single space
    query.gsub!(/("[^"]*")|[ \t\r\n]+/) do
      $1 ? $1 : " " # If inside double quotes ($1), preserve; otherwise replace with a single space
    end

    query = query.strip
    query += " " if query.size > 0

    "#{query}repo:#{owner}/#{name}#{sort_qualifier}" # rubocop:disable GitHub/DoNotAllowLogin
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

  memoize def pr_react_dashboard_enabled?
    user_feature_enabled?(:new_pulls_dashboard)
  end

  memoize def issue_react_enabled?
    # Give us the ability to disable react for specific orgs
    return false if (owner.is_a?(Organization) && owner.feature_enabled?(:issues_react_disabled)) || current_user&.feature_enabled?(:issues_react_disabled)
    return false if GitHub.issues_react_ghes_disabled?

    if logged_in?
      true
    else
      # do not use issues react for robot until we have clarified how this could impact SEO
      # for an experiment, we allow splitting certain bot traffic to Issues React
      if robot?
        FeatureFlag.vexi.enabled?(:issues_react_split_bot_traffic, default: false) && org_in_seo_experiment_bucket?
      else
        true
      end
    end
  end

  memoize def emoji_skin_tone_preference
    return nil unless logged_in?
    current_user&.profile_settings.preferred_emoji_skin_tone
  end

  def org_in_seo_experiment_bucket?
    if request&.path&.start_with?("/_view_fragments/issues/show/")
      request&.path&.match?(/^\/_view_fragments\/issues\/show\/[a-m]/)
    else
      request&.path&.match?(/^\/[a-m]/)
    end
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
    controller_name == "issues" && action_name == "index" && params[:milestone_name]
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
    clean_author = author.gsub(ActionController::Redirecting::ILLEGAL_HEADER_VALUE_REGEX, "")
    "/#{scoped_repository[:owner]}/#{scoped_repository[:name]}/issues/created_by/#{clean_author}"
  end

  def render_issue_react_index_opt_in?
    is_issue_index_path? && !(params && params[:pulls_only] == true)
  end

  def render_issue_react_create_opt_in?
    is_issue_create_path?
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

    preload_labels(preloaded_records)

    preloaded_records
  end

  sig { returns(T.nilable(String)) }
  memoize def copilot_api_url_for_issues
    if current_user&.feature_enabled?(:copilot_plan_brainstorm_with_blackbird) || current_user&.feature_enabled?(:copilot_find_relevant_files)
      Copilot::SKUIsolation.for_user(current_user).api.endpoint
    else
      nil
    end
  end

  def render_app(app_name: "issues-react", catalog_service:, url_override: nil, path_override: nil, skip_layout: false, origin: nil)
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

      # Redirect to /new if path is new/choose and template is specified
      if scoped_repository && params[:template].present? && request&.path&.ends_with?("/new/choose")
        new_path = request&.path&.sub("/choose", "")
        safe_redirect_to safe_url_for("#{new_path}?#{request&.query_string}")
        return
      end

      # Redirect to /new if path is new or new/choose and the repository contains only one template and we are not creating from a discussion
      if scoped_repository && !params[:template].present? && !params[:created_from_discussion_number].present? && request&.path&.match?(/\/new(\/choose)?$/) && single_issue_template
        new_path = request&.path&.sub("/choose", "")
        safe_redirect_to safe_url_for("#{new_path}?template=#{single_issue_template.filename}")
        return
      end

      # Redirect to /new if path is new/choose and the repository has no templates
      if scoped_repository && request&.path&.ends_with?("/new/choose") && repo_has_no_templates?
        new_path = request&.path&.sub("/choose", "")
        safe_redirect_to safe_url_for("#{new_path}")
        return
      end

      # Redirect to /new/choose if path is /new and the repository has blank issues disabled without a template param
      if scoped_repository &&
        controller_name == "issues" &&
        action_name == "new" &&
        !repo_has_blank_issues? &&
        !repo_has_no_templates? &&
        !params[:template].present? &&
        !params[:created_from_discussion_number].present?
        new_path = "#{request&.path}/choose"
        safe_redirect_to safe_url_for("#{new_path}")
        return
      end

      custom_tags << "referrer_controller_action:#{controller}##{action_name}"
      preload_pull_requests = current_user&.feature_enabled?(:pull_request_single_subscription)

      enabled_flags = T.let([], T::Array[T.untyped])
      add_client_feature_flag(
        REACT_CLIENT_FEATURE_LIST,
        entity: org,
      )

      # This is a bit of a hack since I was unsure how else to plumb through the value of `copilot_workspace_can_grant_auto_access?` to the React app
      add_client_feature_flag(
        [:copilot_workspace],
        entity: org
      ) do |_feature_name, organization|
        feature_enabled_globally_or_for_current_user_or_entity?(:copilot_workspace, organization) || current_user&.copilot_workspace_can_grant_auto_access?
      end

      add_client_feature_flag(
        [:tasklist_block],
        entity: org,
      ) do |_feature_name, organization|
        tb_enabled = FeatureFlag.vexi.enabled_or_raise?(:tasklist_block, organization) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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
        [:issue_dependencies],
        entity: owner
      ) do |_feature_name, _owner|
        IssueDependenciesFeature.enabled?(current_repository, actor: current_user)
      end
      add_client_feature_flag(
        [:issue_dependencies_internal_dev],
        entity: owner
      ) do |_feature_name, _owner|
        IssueDependenciesFeature.enabled_internally_for_user?(current_user)
      end

      add_client_feature_flag(
        [:issue_fields],
        entity: owner
      ) do |_feature_name, _owner|
        current_repository && IssueFieldsFeature.enabled?(current_repository, actor: current_user)
      end

      add_client_feature_flag(
        [:copilot_swe_agent],
        entity: current_repository
      ) do |_feature_name, current_repository|
        current_repository&.copilot_swe_agent_enabled?(current_user)
      end

      if logged_in? && (is_issue_show_path? || is_issue_index_path? && !is_issue_index_author_path?)
        # The repository must be enabled for semantic indexing for feature related to issues semantic search
        issues_semantic_index_available = ::Search::Queries::IssueSemanticHelper.ingest_enabled?(repository: current_repository)

        add_client_feature_flag(
          [:elasticsearch_semantic_indexing_issues_show_dupes],
          entity: current_repository
        ) do |_feature_name, _current_repository|
          issues_semantic_index_available && current_user&.feature_enabled?(:elasticsearch_semantic_indexing_issues_show_dupes)
        end

        issues_semantic_search_preview_enabled = feature_enabled_for_current_user?(
          feature_name: :elasticsearch_semantic_indexing_issues_semantic_search
        )

        add_client_feature_flag(
          [:issues_semantic_search_preview_opt_in],
          entity: current_repository
        ) do |_feature_name, _current_repository|
          next false unless issues_semantic_index_available
          next false unless issues_semantic_search_preview_enabled
          !current_user&.feature_preview_enabled?(:elasticsearch_semantic_indexing_issues_semantic_search)
        end

        add_client_feature_flag(
          [:issues_semantic_search_preview_enabled],
          entity: current_repository
        ) do |_feature_name, _current_repository|
          next false unless issues_semantic_index_available
          next false unless issues_semantic_search_preview_enabled
          current_user&.feature_preview_enabled?(:elasticsearch_semantic_indexing_issues_semantic_search)
        end
      end

      # TODO find a better way to verify when to preload issue view secondary query
      if params[:id].to_i > 0 && request&.path&.include?("/issues/")
        set_preload_header([
          GraphQLRequest.new(
            name: ISSUE_VIEWER_SECONDARY_VIEW_QUERY_NAME,
            variables: {
              owner: current_repository.owner.display_login,
              repo: current_repository.name,
              number: params[:id].to_i,
              markAsRead: true,
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
          {
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
              copilot_show_functionality: current_user&.settings&.get(:copilot_show_functionality) || false
            },
            paste_url_link_as_plain_text: logged_in? ? current_user&.paste_url_link_as_plain_text? : false,
            base_avatar_url: GitHub.alambic_avatar_url,
            help_url: GitHub.help_url,
            sso_organizations: action_name == "dashboard" ? sso_organizations : nil,
            multi_tenant: GitHub.multi_tenant_enterprise?,
            tracing: tracing_enabled?,
            tracing_flamegraph: tracing_flamegraph_enabled?,
            catalog_service: catalog_service,
            scoped_repository: scoped_repository,
            copilot_api_url: copilot_api_url_for_issues,
          }
        },
        stats: stats,
        turbo: turbo,
        layout: layout,
        variable_overwrite_fns: get_variable_overwrite_hash,
        precompute_subscription_fns: get_precompute_subscription_hash(preload_pull_requests:),
        query_callback_fns: get_query_callbacks,
        add_query_time_tags_fn: get_sub_issues_add_query_time_tags_fn,
        disable_ssr: tracing_enabled? || !is_using_ssr,
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
        log_errors = feature_enabled_globally_or_for_user?(feature_name: :issues_react_helper_logging_errors)
        if log_errors
          log_data["errors_in_preloaded_queries"] = stats[:errors_in_preloaded_queries]
        end
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

    # using Platform::ORIGIN_INTERNAL under the assumption that authorization happens in the controller flow
    render_app(
      catalog_service: "github/issues",
      origin: Platform::ORIGIN_INTERNAL,
      url_override: url_override,
      path_override: path_override,
      skip_layout: skip_layout,
    )
    true
  end

  def issue_react_milestone_show_handler
    return false unless issue_react_enabled?

    GitHub::TaggingHelper.override_action_tag(env: env, action: "milestone_show_react")
    GitHub.current_span&.set_attribute(GitHub::TaggingHelper::ACTION_TAG, "milestone_show_react")

    # using Platform::ORIGIN_INTERNAL under the assumption that authorization happens in the controller flow
    render_app(
      catalog_service: "github/issues",
      origin: Platform::ORIGIN_INTERNAL,
      # url_override: url_override,
      # path_override: path_override,
      # skip_layout: skip_layout,
    )
    true
  end

  def issue_react_milestone_index_handler
    return false unless issue_react_enabled?

    GitHub::TaggingHelper.override_action_tag(env: env, action: "milestone_index_react")
    GitHub.current_span&.set_attribute(GitHub::TaggingHelper::ACTION_TAG, "milestone_index_react")


    # using Platform::ORIGIN_INTERNAL under the assumption that authorization happens in the controller flow
    render_app(
      catalog_service: "github/issues",
      origin: Platform::ORIGIN_INTERNAL,
    )
    true
  end

  def issue_react_milestone_new_handler
    return false unless issue_react_enabled?

    GitHub::TaggingHelper.override_action_tag(env: env, action: "milestone_create_react")
    GitHub.current_span&.set_attribute(GitHub::TaggingHelper::ACTION_TAG, "milestone_create_react")

    render_app(
      catalog_service: "github/issues",
      origin: Platform::ORIGIN_INTERNAL,
    )
    true
  end

  def issue_react_milestone_edit_handler
    return false unless issue_react_enabled?

    GitHub::TaggingHelper.override_action_tag(env: env, action: "milestone_edit_react")
    GitHub.current_span&.set_attribute(GitHub::TaggingHelper::ACTION_TAG, "milestone_edit_react")

    render_app(
      catalog_service: "github/issues",
      origin: Platform::ORIGIN_INTERNAL,
    )
    true
  end

  def issue_react_label_index_handler
    return false unless issue_react_enabled?
    is_enabled = if owner.is_a?(Organization) && owner.feature_enabled?(:issues_react_label_index) || current_user&.feature_enabled?(:issues_react_label_index) || FeatureFlag.vexi.enabled_or_raise?(:issues_react_label_index) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      true
    else
      false
    end

    return false if !is_enabled
    GitHub::TaggingHelper.override_action_tag(env: env, action: "label_index_react")
    GitHub.current_span&.set_attribute(GitHub::TaggingHelper::ACTION_TAG, "label_index_react")


    # using Platform::ORIGIN_INTERNAL under the assumption that authorization happens in the controller flow
    render_app(
      catalog_service: "github/issues",
      origin: Platform::ORIGIN_INTERNAL,
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
      catalog_service: "github/issues",
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
    render_app(catalog_service: "github/issues", url_override: url_override, path_override: path_override, skip_layout: skip_layout, origin: Platform::ORIGIN_INTERNAL)
    true
  end

  def issue_react_dashboard_handler
    if is_issue_dashboard_path?
      GitHub::TaggingHelper.override_action_tag(env: env, action: "dashboard_react")
      GitHub.current_span&.set_attribute(GitHub::TaggingHelper::ACTION_TAG, "dashboard_react")
      render_app(catalog_service: "github/issues", origin: Platform::ORIGIN_INTERNAL)

      return true
    end

    # Render React /pulls page if :new_pulls_dashboard feature flag is enabled
    if pr_react_dashboard_enabled? && is_pr_dashboard_path?
      GitHub::TaggingHelper.override_controller_tag(env: env, controller: "pull_requests_react")
      GitHub.current_span&.set_attribute(GitHub::TaggingHelper::CONTROLLER_TAG, "pull_requests_react")
      render_app(app_name: "pulls-dashboard", catalog_service: "github/pull_requests", origin: Platform::ORIGIN_INTERNAL)
      true
    end
  end

  def issue_create_handler
    return false unless logged_in? && request&.method == "POST" && scoped_repository

    # We're handling all the flags here in order to not enable POST routes for #new, #index #choose
    if params[:new_issues_experience].present?
      if params[:new_issues_experience] == "true"
        redirect_to "/#{scoped_repository[:owner]}/#{scoped_repository[:name]}/issues"
        return true
      elsif params[:new_issues_experience] == "false"
        redirect_to "/#{scoped_repository[:owner]}/#{scoped_repository[:name]}/issues"
        return true
      end
    end

    # Similar to how we did for new issues experience, handling feature preview opt-in here in order to not enable POST routes for #new, #index #choose
    semantic_search_opt_in = params[:issues_semantic_search]
    unless semantic_search_opt_in.nil?
      if feature_enabled_for_current_user?(feature_name: :elasticsearch_semantic_indexing_issues_semantic_search)
        if semantic_search_opt_in == "true"
          current_user&.enable_feature_preview(:elasticsearch_semantic_indexing_issues_semantic_search)
        elsif semantic_search_opt_in == "false"
          current_user&.disable_feature_preview(:elasticsearch_semantic_indexing_issues_semantic_search)
        end
      end

      # No matter the action, redirect back to the issues page
      redirect_to "/#{scoped_repository[:owner]}/#{scoped_repository[:name]}/issues"
      return true
    end

    if params[:new_create_experience].present?
      if params[:new_create_experience] == "true"
        redirect_to "/#{scoped_repository[:owner]}/#{scoped_repository[:name]}/issues/new"
        return true
      elsif params[:new_create_experience] == "false"
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
    true
  end

  def active_experiment
    if FeatureFlag.vexi.enabled_or_raise?(:persisted_tracer_debug_mode, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      "persisted_tracer_debug_mode"
    else
      "no_active_experiment"
    end
  end

  def preload_labels(preloaded_records)
    begin
      # don't preload in show for logged out traffic since they can't use the picker anyway
      return if !logged_in? && is_issue_show_path?
      repo_id = current_repository&.global_relay_id
      return if !repo_id
      label_count = current_repository.labels.count
      return if !label_count || !(100..1000).cover?(label_count)

      ref = "client:#{repo_id}:labels"
      preloaded_records[repo_id] = {
        __id: repo_id,
        labels: {
          __ref: ref,
        },
      }

      # If, for some reason, labels are not eagerly loaded, this can throw. This is the reason
      # for the rescue block (shouldn't happen, but we don't want this to potentially introduce an error).
      labels = current_repository.labels.take(1000).as_json(
        root: false, only: %i[id name color description], methods: %i[global_relay_id name_html url]
      ).map do |label|
        label["id"] = label["global_relay_id"]
        label["__id"] = label["id"]
        label["nameHTML"] = label["name_html"]
        label["__typename"] = "Label"
        label.delete("global_relay_id")
        label.delete("name_html")
        label
      end

      labels.each do |label|
        preloaded_records[label["__id"]] = label
      end

      preloaded_records[ref] = {
        __id: ref,
        __typename: "LabelConnection",
        totalCount: label_count,
        nodes: {
          __refs: labels.map { |l| l["__id"] }
        }
      }
    end
  rescue => err
    # The code above is a performance optimization and should not cause the page to fail if it fails
    Failbot.report(err, catalog_service: "github/issues", tags: { source: "preload_labels" })
  end

  def single_issue_template
    return nil if current_repository.security_policy.exists?

    preferred_templates = current_repository.preferred_issue_templates
    return nil if preferred_templates.nil?

    config = preferred_templates.issue_template_config
    return nil if config.blank_issues_enabled? || config.contact_links.any?

    valid_templates = preferred_templates.valid_templates.reject(&:structured?)
    valid_forms = preferred_templates.valid_yaml_templates.select(&:structured?)

    results = (valid_templates + valid_forms).each { |template| template.current_repository = self }
    results.size == 1 ? results.first : nil
  end

  def repo_has_no_templates?
    return false if current_repository.security_policy.exists?

    preferred_templates = current_repository.preferred_issue_templates

    config = preferred_templates.issue_template_config
    return false if config.contact_links.any?

    !preferred_templates.any?
  end

  def repo_has_blank_issues?
    preferred_templates = current_repository.preferred_issue_templates
    return true if preferred_templates.nil?

    config = preferred_templates.issue_template_config
    config.blank_issues_enabled?
  end
end
