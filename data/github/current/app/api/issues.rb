# typed: true
# frozen_string_literal: true

class Api::Issues < Api::App
  include ReceiveSchemaWithOpenApi
  include Scientist
  include Api::App::UsersDependency

  module EnsureIssuesEnabled
    extend T::Helpers

    requires_ancestor { Api::App::ErrorDependency }

    # Checks repository after access control to ensure issues
    # are enabled for this repository.
    def ensure_issues_enabled!(repo)
      unless repo.has_issues?
        deliver_error!(410,
          message: "Issues are disabled for this repo",
          documentation_url: "/v3/issues/")
      end
    end

    # Halts with a 410 if the issue is not a Pull and the repo
    # has disabled issues
    def ensure_issues_enabled_or_pr!(repo, issue)
      return if !issue || repo.has_issues? || issue.pull_request_id
      ensure_issues_enabled!(repo)
    end

    def set_context_controller_action(issue, operation_id)
      populate_context_with_controller_action(
        (issue.pull_request? ? "pr/" : "issue/") + operation_id
      )
    end
  end

  module EnsureIssuesTypesEnabled
    extend T::Helpers

    requires_ancestor { Api::App::ErrorDependency }
    requires_ancestor { Api::Issues }

    # Checks owner and issue type name to see if the issue type is valid and enabled for the current user.
    def deliver_error_or_get_issue_type(owner, issue_type_name, documentation_url, repo = nil)
      issue_type = Issues.domain.issue_types.by_organization_and_name(owner, issue_type_name)

      if !issue_type
        deliver_issue_type_error(issue_type_name, documentation_url)
        return
      end

      if !issue_type.enabled?
        deliver_error! 422,
          message: "Issue type #{issue_type_name} is not enabled",
          documentation_url: documentation_url
      end

      issue_type
    end

    def deliver_issue_type_error(value, documentation_url)
      deliver_error! 422,
        errors: [api_error(:Issue, :type, :invalid, value: value)],
        documentation_url:
    end
  end

  module HandleIssueNotFound
    extend T::Helpers

    requires_ancestor { Api::App::ErrorDependency }
    requires_ancestor { Api::Issues::EnsureIssuesEnabled }

    def handle_issue_not_found(resource_url_suffix = nil)
      repo = current_repo
      if issue_transfer = IssueTransfer.find_from(repository: repo, number: int_id_param!(key: :issue_number)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        transferred_issue = issue_transfer.new_issue

        # Ensure we can see issues in the old repo
        control_access :list_issues,
          repo: repo,
          allow_integrations: true,
          allow_user_via_granular_actor: true

        new_repo = transferred_issue.repository
        ensure_issues_enabled_or_pr!(new_repo, transferred_issue)

        if access_allowed?(:list_issues, repo: new_repo, allow_integrations: true, allow_user_via_granular_actor: true)
          redirect_url = api_url("/repos/#{new_repo.name_with_display_owner}/issues/#{transferred_issue.number}")
          redirect_url = "#{redirect_url}#{resource_url_suffix}" if resource_url_suffix
          deliver_redirect!(redirect_url, status: 301)
        else
          deliver_redirect!("", status: 301)
        end
      elsif DeletedIssue.where(repository_id: repo.id, number: int_id_param!(key: :issue_number)).exists? &&
        access_allowed?(:list_issues, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true)
        deliver_error!(410, message: "This issue was deleted")
      else
        deliver_error!(404)
      end
    end
  end

  module Preload

    # Use this to preload data for an array of issues
    def prefill_for_multiple_issues(issues, preload_issue_edits:, updated_issue_prefillers_enabled: false)
      current_user = T.unsafe(self).current_user
      if updated_issue_prefillers_enabled
        IssuePrefiller.optimized_prefill(issues, current_user: current_user, preload_issue_edits: preload_issue_edits) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        Reaction::Summary.prefill(issues)
        Repository.prefill_associations(issues.map(&:repository), internal: true)
      else
        IssuePrefiller.prefill(issues, current_user: current_user)
        Repository.prefill_associations(issues.map(&:repository))
        Reaction::Summary.prefill(issues)
        preload_author_associations(issues)
      end
    end

    def preload_issue_edits?(options)
      params = options[:mime_params]
      params.include?(:html) || params.include?(:full) || params.include?(:text)
    end

    def preload_author_associations(issues)
      promises = issues.map do |associable|
        CommentAuthorAssociation.new(comment: associable, viewer: T.unsafe(self).current_user).async_to_sym.then do |sym|
          associable.preload_attr(:author_association_symbol, sym)
        end
      end
      Promise.all(promises).sync
    end
  end

  module Limits
    # 500K which is the Vitess total limit, divided by current number of shards (16): 31250.
    # Add some extra padding for better sleep, down to 30K.
    ISSUES_PULL_REQUESTS_PAGINATION_LIMIT = 30_000
  end

  include Api::Labels::Helpers, Api::Issues::EnsureIssuesEnabled, Api::Issues::EnsureIssuesTypesEnabled, Scientist, Api::Issues::HandleIssueNotFound, Api::Issues::Limits, Api::Issues::Preload
  include Api::App::DatabaseConnectionHelper

  STATE      = "state".freeze
  ASSIGNEE   = "assignee".freeze
  ASSIGNEES  = "assignees".freeze
  MILESTONE  = "milestone".freeze
  CREATOR    = "creator".freeze
  MENTIONED  = "mentioned".freeze
  LABELS     = "labels".freeze
  ISSUE_TYPE = "type".freeze
  COLLAB_ONLY_ATTRIBUTES = [ASSIGNEE, ASSIGNEES, LABELS, MILESTONE, ISSUE_TYPE]

  def filter_issues_for_repos_without_programmatic_access_if_needed(repo_ids)
    if ProgrammaticActor::RepositoryFilter.applicable?(current_user)
      filter_issues_for_repos_without_programmatic_access(repo_ids)
    else
      Issue.for_repository_ids(repo_ids)
    end
  end

  # Internal: filter issues given a list of repositories to restrict by.
  #
  # repo_ids - an array of Repository IDs.
  #
  # Returns a scope to filter Issues based on request parameters and the
  # list or scope of repositories.
  #
  #
  def filter_issues(repo_ids, org: nil)
    issue_type = nil

    if params[ISSUE_TYPE]
      if org && org.issue_types_enabled?
        issue_type = deliver_error_or_get_issue_type(org, params[ISSUE_TYPE], @documentation_url)
      else
        deliver_issue_type_error(params[ISSUE_TYPE], @documentation_url)
      end
    end
    scope = filter_issues_for_repos_without_programmatic_access_if_needed(repo_ids)
    scope = scope.filter_spam_for(current_user)

    unauthorized_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations)

    # Any `unauthorized_sso_org_ids` will already be included in `unauthorized_org_ids`
    # We simply re-query only the SSO orgs to the return header payload.
    unauthorized_sso_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)

    repo_ids_with_issues = []
    repo_ids_without_issues = []

    filtered_scope = Repository.where(id: repo_ids, user_hidden: false)
    if unauthorized_org_ids.any?
      filtered_scope = filtered_scope.where.not(organization_id: unauthorized_org_ids).or(filtered_scope.where(organization_id: nil))
    end
    filtered_scope.pluck(:id, :has_issues).each do |(repo_id, has_issues)|
      if has_issues
        repo_ids_with_issues << repo_id
      else
        repo_ids_without_issues << repo_id
      end
    end

    scopes = []
    scopes << scope.where(repository_id: repo_ids_with_issues) if repo_ids_with_issues.any?
    scopes << scope.where(repository_id: repo_ids_without_issues).where.not(pull_request_id: nil) if repo_ids_without_issues.any?

    scope = if scopes.any?
      scopes.reduce(:or)
    else
      scope.none
    end

    set_sso_partial_results_header(unauthorized_sso_org_ids) if unauthorized_sso_org_ids.any?

    scope =
      case params[:filter]
      when "created"
        # login used to filter issues therefore safe to use here.
        scope.created_by(current_user.login) # rubocop:disable GitHub/DoNotAllowLogin
      when "subscribed"
        lists = repo_ids.map { |id| Newsies::List.new(Repository.name, id) }
        threads_response = GitHub.newsies.subscribed_threads(current_user, lists, "Issue")
        if threads_response.failed?
          deliver_notifications_unavailable!
        end
        scope.from_ids(threads_response.map(&:thread_id))
      when "mentioned"
        scope.mentioning(current_user)
      when "repos", "all"
        # we're already filtered by repos
        scope
      when "assigned", nil
        # login used to filter issues therefore safe to use here.
        scope.assigned_to(current_user.login) # rubocop:disable GitHub/DoNotAllowLogin
      else
        deliver_error! 422,
          errors: [api_error(:Issue, :filter, :invalid, value: params[:filter])],
          documentation_url: "/v3/issues/"
      end

    # filter by state
    scope = case params[:state]
    when /close/ then scope.closed_issues
    when /all/   then scope
    else         scope.open_issues
    end

    # filter by labels
    if (labels = params[:labels]).present?
      scope = scope.labeled(labels.split(","))
    end

    # filter by issue type
    if issue_type
      scope = scope.for_issue_type(issue_type)
    end

    # filter by updated_at
    if (since = time_param!(:since)).present?
      scope = scope.since(since.getlocal)
    end

    scope = filter_dash_scope(scope)

    # specify sort
    # .unscope(:order) to remove the default sorting by id
    scope = scope.unscope(:order).sorted_by(params[:sort], params[:direction])

    if scope.null_relation?
      paginate_rel(scope) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    else
      order_by_field = Issue.sorted_by_field(params[:sort])
      pagination_scope = scope.select(:id, order_by_field).paginate(page: pagination[:page], per_page: pagination[:per_page])

      scope = Issue.where("`issues`.`id` IN (SELECT id FROM (?) subquery_for_limit)", pagination_scope).sorted_by(params[:sort], params[:direction])

      # Copy over pagination attributes
      scope = scope.extending(WillPaginate::ActiveRecord::RelationMethods)
      scope = T.unsafe(scope).per_page(pagination_scope.per_page)
      scope.current_page = pagination_scope.current_page
      scope.total_entries = pagination_scope.total_entries # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      scope
    end
  end

  # From a given Issue scope and an array of unauthorized organization IDs,
  # returns an array of repository IDs of issues in the scope:
  #
  # - excluding PRs,
  # - excluding issues by spammy users,
  # - excluding repositories with issues disabled and
  # - excluding repositories from unauthorized organizations.
  #
  def filter_repo_ids_for_issues(scope, unauthorized_org_ids)
    repo_ids = scope.where(pull_request_id: nil).select(:repository_id).distinct.pluck(:repository_id)
    filtered_scope = Repository.with_issues_enabled.where(id: repo_ids, user_hidden: false)

    if unauthorized_org_ids.any?
      filtered_scope = filtered_scope.where.not(organization_id: unauthorized_org_ids).or(filtered_scope.where(organization_id: nil))
    end

    filtered_scope.pluck(:id)
  end

  # From a given Issue scope and an array of unauthorized organization IDs,
  # returns an array of repository IDs of pull requests in the scope:
  #
  # - excluding PRs by spammy users and
  # - excluding repositories from unauthorized organizations.
  #
  def filter_repo_ids_for_prs(scope, unauthorized_org_ids)
    repo_ids = scope.where.not(pull_request_id: nil).select(:repository_id).distinct.pluck(:repository_id)
    filtered_scope = Repository.where(id: repo_ids, user_hidden: false)

    if unauthorized_org_ids.any?
      filtered_scope = filtered_scope.where.not(organization_id: unauthorized_org_ids).or(filtered_scope.where(organization_id: nil))

    end

    filtered_scope.pluck(:id)
  end

  # List issues for the current user across all organization, owned, and member repositories
  get "/issues", operation_id: "issues/list", resolve_tenant_context: :resolve_tenant_from_user do
    resource = Platform::DashboardResource.new(current_user)
    control_access :dashboard, resource: resource, allow_integrations: false, allow_user_via_granular_actor: true

    cap_paginated_entries!(ISSUES_PULL_REQUESTS_PAGINATION_LIMIT)

    private_access_allowed = access_allowed?(:private_dashboard, resource: resource, allow_integrations: false, allow_user_via_granular_actor: true)

    repo_ids = current_user.associated_repository_ids # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    if private_access_allowed
      repo_ids = Repository.where(id: repo_ids).active.pluck(:id)
    else
      repo_ids = Repository.where(id: repo_ids).active.public_scope.pluck(:id)
    end

    # ensure we filter by repos this user owns or is a collab on
    issues = filter_issues repo_ids
    updated_issue_prefillers_enabled = FeatureFlag.vexi.enabled?(:updated_issue_prefillers, default: false)
    preload_issue_edits = if updated_issue_prefillers_enabled
      preload_issue_edits?(Api::SerializerOptions.fill(default_options))
    else
      false
    end
    prefill_for_multiple_issues(issues, preload_issue_edits: preload_issue_edits, updated_issue_prefillers_enabled: updated_issue_prefillers_enabled)

    deliver :issue_hash, issues, repositories: true
  end

  # List issues for repositories under a specific organizations
  get "/organizations/:organization_id/issues", operation_id: "issues/list-for-org" do
    org = find_org!
    resource = Platform::DashboardResource.new(org)
    control_access :org_issue_dashboard, resource: Platform::InternalDashboardResource.new(resource: resource), allow_integrations: false, allow_user_via_granular_actor: true

    cap_paginated_entries!(ISSUES_PULL_REQUESTS_PAGINATION_LIMIT)

    repos = org.visible_repositories_for(current_user)

    unless access_allowed?(:private_dashboard, resource: resource, allow_integrations: false, allow_user_via_granular_actor: true)
      repos = repos.public_scope
    end

    issues = []

    if org.issue_types_enabled?
      issues = filter_issues(repos.pluck(:id), org: org)
    else
      issues = filter_issues repos.pluck(:id)
    end

    updated_issue_prefillers_enabled = FeatureFlag.vexi.enabled?(:updated_issue_prefillers, default: false)

    preload_issue_edits = if updated_issue_prefillers_enabled
      preload_issue_edits?(Api::SerializerOptions.fill(default_options))
    else
      false
    end
    prefill_for_multiple_issues(issues, preload_issue_edits: preload_issue_edits, updated_issue_prefillers_enabled: updated_issue_prefillers_enabled)
    deliver :issue_hash, issues, repositories: true, full: true
  end

  # List issues for the current user across all owned and member repositories
  get "/user/issues", operation_id: "issues/list-for-authenticated-user" do
    resource = Platform::DashboardResource.new(current_user)
    control_access :dashboard, resource: resource, allow_integrations: false, allow_user_via_granular_actor: true

    cap_paginated_entries!(ISSUES_PULL_REQUESTS_PAGINATION_LIMIT)

    owned_repos = current_user.repositories
    member_repos = current_user.member_repositories

    unless access_allowed?(:private_dashboard, resource: resource, allow_integrations: false, allow_user_via_granular_actor: true)
      owned_repos = owned_repos.public_scope
      member_repos = member_repos.public_scope
    end

    owned_repo_ids = owned_repos.pluck(:id)
    member_repo_ids = member_repos.pluck(:id)

    repo_ids = owned_repo_ids | member_repo_ids

    issues = filter_issues repo_ids
    GitHub.dogstats.distribution_time "api.prefill", tags: ["action:user_issues_list"] do
      updated_issue_prefillers_enabled = FeatureFlag.vexi.enabled?(:updated_issue_prefillers, default: false)
      preload_issue_edits = if updated_issue_prefillers_enabled
        preload_issue_edits?(Api::SerializerOptions.fill(default_options))
      else
        false
      end
      prefill_for_multiple_issues(issues, preload_issue_edits: preload_issue_edits, updated_issue_prefillers_enabled: updated_issue_prefillers_enabled)
    end
    GitHub.dogstats.distribution_time "api.deliver", tags: ["action:user_issues_list"] do
      deliver :issue_hash, issues, repositories: true
    end
  end

  # List issues for this Repository
  get "/repositories/:repository_id/issues", operation_id: "issues/list-for-repo" do
    control_access :list_issues,
      repo: repo = current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Check if state is invalid
    if params[:state] && !%w(open closed all).include?(params[:state])
      deliver_error! 422,
        errors: [api_error(:Issue, :state, :invalid, value: params[:state])],
        documentation_url: "/v3/issues/#list-issues"
    end

    # Check if labels are invalid
    if params[:labels].present? && !(params[:labels].is_a?(String) && params[:labels].force_encoding("utf-8").valid_encoding?)
      deliver_error! 422,
        errors: [api_error(:Issue, :labels, :invalid, value: params[:labels])],
        documentation_url: "/v3/issues/#list-issues"
    end

    with_es_search = repo.feature_enabled?(:issues_api_es_search_enabled) || current_user&.feature_enabled?(:issues_api_es_search_enabled)

    if with_es_search
      after_or_before = params[:after].present? ? :after : :before

      cursor = params[after_or_before]

      if cursor.present?
        begin
          Search::Responses::PropertyEncoder.resolve(cursor)
        rescue Platform::Errors::Cursor
          deliver_error! 422,
          errors: [api_error(:Issue, after_or_before, :invalid, value: cursor)]
        end
      end
    end

    query = search_param_mapping(params)

    # Bring in labels and split them if it's a comma,delimited,string
    if (labels = params[:labels]).present? && labels.respond_to?(:split)
      if with_es_search
        labels.split(",").each do |label_string|
          query << [:label, label_string]
        end
      else
        query << [:label, labels.split(",")]
      end
    end

    # Scope to a particular sort
    if params[:sort] || params[:direction]
      sort = params[:sort] || "created"
      direction = params[:direction] || "desc"
      query << [:sort, "#{sort}-#{direction}"]
    end

    # Default sort is "open"
    if !params[:state]
      query << [:state, "open"]
    end

    # Scope to a milestone
    if params[MILESTONE]
      milestone_filter(repo, query, params[MILESTONE])
    end

    # Scope to an assignee
    if params[ASSIGNEE]
      assignee_filter(query, params[ASSIGNEE])
    end

    if params[ISSUE_TYPE]
      if repo.owner && repo.owner.issue_types_enabled?
        issue_type_filter(repo, query, params[ISSUE_TYPE], with_es_search)
      else
        deliver_issue_type_error(params[ISSUE_TYPE], @documentation_url)
      end
    end

    # Scope mentions
    if params[MENTIONED]
      mention_filter(query, params[MENTIONED])
    end

    # Scope type
    #
    # | I | Issues   | pr :read | issues :read | Force type | Comment                    |
    # |---|----------|----------|--------------|------------|----------------------------|
    # | 1 | Enabled  | Yes      | Yes          | N/A        | No filtering needed        |
    # | 2 | Enabled  | Yes      | No           | pr         |                            |
    # | 3 | Enabled  | No       | Yes          | issues     |                            |
    # | 4 | Enabled  | No       | No           | N/A        | No access to this endpoint |
    # | 5 | Disabled | No       | No           | N/A        | No access to this endpoint |
    # | 6 | Disabled | No       | Yes          | pr         |                            |
    # | 7 | Disabled | Yes      | No           | pr         |                            |
    # | 8 | Disabled | Yes      | Yes          | pr         |                            |
    #

    # 5-8 Filter to PRs only if issues are disabled for the repo
    force_type = if !repo.has_issues?
      :pull_requests
    else
      pr_read = repo.resources.pull_requests.readable_by?(current_user)
      issue_read = repo.resources.issues.readable_by?(current_user)

      case
      # 2
      when pr_read && !issue_read
        :pull_requests
      # 3
      when !pr_read && issue_read
        :issues
      # 1,4,5
      else
        nil
      end
    end

    scope = if with_es_search
      query << since_filter_es("issues") if params[:since]

      page = pagination[:page]
      per_page = (pagination[:per_page] || DEFAULT_PER_PAGE).to_i

      kwargs = if params[:after]
        { after: params[:after],
          page: nil,
          first: per_page,
          use_cursor_pagination: true }
      elsif params[:before]
        { before: params[:before],
          page: nil,
          last: per_page,
          use_cursor_pagination: true }
      elsif page
        { page: page,
          per_page: per_page,
          use_cursor_pagination: true }
      else
        { per_page: per_page,
          use_cursor_pagination: true }
      end
      scope = Issue::EsSearch.search(
        **kwargs.with_defaults({
          query: query,
          repo: repo,
          current_user: current_user,
          force_pulls: !repo.has_issues?,
          context: "api-repositories-issues",
        })
      )

      if scope[:offset_error]
        deliver_error! 422,
            message: "Pagination with the page parameter is not supported for large datasets, please use cursor based pagination (after/before)",
            documentation_url: @documentation_url
      end

      cursor = scope[:cursor]

      next_page = page + 1
      prev_page = page - 1

      if prev_page == 0 && cursor && cursor[:prev_cursor]
        # at this point we probably got called without a page param but weren't at the first page
        next_page = nil
        prev_page = nil
      end

      @links.add_current({ after: cursor[:next_cursor], before: nil, per_page: (pagination[:per_page] || DEFAULT_PER_PAGE).to_i, page: next_page }, rel: "next") if cursor && cursor[:next_cursor]
      @links.add_current({ before: cursor[:prev_cursor], after: nil, per_page: (pagination[:per_page] || DEFAULT_PER_PAGE).to_i, page: prev_page }, rel: "prev") if cursor && cursor[:prev_cursor]

      scope
    else
      scope = filter_issues_for_repos_without_programmatic_access_if_needed [repo.id]

      # Build a custom initial scope if there's a since filter
      # This is deliberately not adding an initial scope if it's
      # not needed to ensure the query hints in MysqlSearch work.
      if params[:since]
        scope = since_filter(scope)
      end

      Issue::MysqlSearch.search(
        query: query,
        repo: repo,
        current_user: current_user,
        page: (pagination[:page] || 1).to_i,
        per_page: (pagination[:per_page] || 30).to_i,
        initial_scope: scope,
        force_pulls: !repo.has_issues?,
        force_type: force_type,
        show_spam_to_staff: true
      )
    end

    issues = scope[:issues]
    GitHub.dogstats.distribution_time "api.prefill", tags: ["action:repository_issues_list"] do
      # We do not use the prefill_for_multiple_issues method here because
      # this is the only List issues endpoint that does not return a repository object
      # in it's response. In it's place, we prefill the data that we specifically need.
      if FeatureFlag.vexi.enabled?(:updated_issue_prefillers, default: false)
        options = Api::SerializerOptions.fill(default_options)
        IssuePrefiller.optimized_prefill(issues, repository: repo, current_user: current_user, preload_issue_edits: preload_issue_edits?(options)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        Reaction::Summary.prefill(issues)
      else
        IssuePrefiller.prefill(issues, repository: repo, current_user: current_user)
        Reaction::Summary.prefill(issues)
        preload_author_associations(issues)
      end
    end

    GitHub.dogstats.distribution_time "api.deliver", tags: ["action:repository_issues_list"] do
      if repo.feature_enabled?(:disable_issues_graph_in_list_for_repo) || current_user&.feature_enabled?(:disable_issues_graph_in_list_for_repo)
        deliver :issue_hash, issues, full: true, disable_issues_graph: true
      else
        deliver :issue_hash, issues, full: true
      end
    end
  end

  # Create an Issue
  post "/repositories/:repository_id/issues", operation_id: "issues/create" do
    repo = T.let(nil, T.untyped)
    attributes = T.let(nil, T.nilable(Issues::CreateIssueAttributes))

    replica_clusters = T.let([ApplicationRecord::IamAbilities, ApplicationRecord::Collab, ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      with_replica_clusters([ApplicationRecord::Repositories]) do
        control_access :open_issue,
          repo: repo = current_repo,
          enforce_oauth_app_policy: current_repo.private?,
          allow_integrations: true,
          allow_user_via_granular_actor: true

        ensure_issues_enabled!(repo)
        ensure_not_blocked! current_user, repo.owner_id
        authorize_content(repo, :create)

        data = receive_with_schema("issue", "create-legacy")

        # Don't let non collabs set these
        unless access_allowed?(:set_collab_only_attributes_on_new_issue, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true)
          data.delete_if { |key, _value| COLLAB_ONLY_ATTRIBUTES.include?(key) }
        end

        attributes = Issues::CreateIssueAttributes.new(
          repository: repo,
          title: data["title"].to_s,
          body: data["body"].to_s,
        )

        if data["labels"]
          if current_user.feature_enabled?(:issues_rest_api_verify_label_permissions)
            attributes.labels = labels_for(repo, Array(data["labels"]), current_user)
          else
            attributes.labels = labels_for(repo, Array(data["labels"]))
          end
        end

        if id = data[MILESTONE]
          milestone = repo.milestones.find_by_number(id.to_i) if valid_milestone_id?(id)
          if milestone
            attributes.milestone = milestone
          else
            deliver_error! 422,
              errors: [api_error(:Issue, :milestone, :invalid, value: id)],
              documentation_url: @documentation_url
          end
        end

        if data[ISSUE_TYPE].present? && repo.owner.issue_types_enabled?
          issue_type = Issues.domain.issue_types.by_organization_and_name(repo.owner, data[ISSUE_TYPE])

          if issue_type&.enabled?
            attributes.issue_type = issue_type
          else
            deliver_error! 422,
            errors: [api_error(:Issue, :type, :invalid, value: data[ISSUE_TYPE])],
            documentation_url: @documentation_url
          end
        end

        assignee_keys = [ASSIGNEE, ASSIGNEES].select { |key| data.key?(key) }
        if assignee_keys.length == 2
          deliver_error! 422, message: "You cannot pass both `assignee` and `assignees`. Only one may be provided."
        end
        if assignee_keys.present?
          attributes.assignees = prepare_assignees(repo: repo, assignee_keys: assignee_keys, data: data, documentation_url: @documentation_url, author: current_user, issue: nil)
        end
      end

      result = Issues.domain.create(
        T.must(attributes),
        current_user,
        integration: integration_user_request? ? current_integration : nil,
        skip_permission_checks: true,
      )
      case result
      when GH::Result::Ok
        issue = result.value
        GitHub.dogstats.increment("issue", tags: ["via:api", "action:create", "valid:true"])
        if FeatureFlag.vexi.enabled?(:updated_issue_prefillers, default: false)
          options = Api::SerializerOptions.fill(default_options)
          IssuePrefiller.optimized_prefill([issue], repository: repo, current_user: current_user, only_prefill: [:assignees], preload_issue_edits: preload_issue_edits?(options))
        else
          IssuePrefiller.prefill([issue], repository: repo, current_user: current_user, only_prefill: [:assignees])
        end

        deliver :issue_hash, issue, status: 201, repo: repo, full: true
      when GH::Result::Error::LockedForRebalance
        deliver_error! 503,
          message: "This issue's milestone is temporarily locked for maintenance. Please try again.",
          documentation_url: @documentation_url
      when GH::Result::Error::Validation
        GitHub.dogstats.increment("issue", tags: ["via:api", "action:create", "valid:false"])

        deliver_error 422,
          errors: result.model.errors,
          documentation_url: @documentation_url
      end
    end
  end

  # Get a single Issue
  get "/repositories/:repository_id/issues/:issue_number", operation_id: "issues/get" do
    repo  = current_repo
    issue = repo && Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)

    if issue
      control_access :show_issue,
        resource: issue,
        repo: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      ensure_issues_enabled_or_pr!(repo, issue)

      deliver_error!(404) unless issue_visible_to_user?(issue)
      set_context_controller_action(issue, "get")
      if FeatureFlag.vexi.enabled?(:updated_issue_prefillers, default: false)
        options = Api::SerializerOptions.fill(default_options)
        IssuePrefiller.optimized_prefill([issue], repository: repo, current_user: current_user, preload_issue_edits: preload_issue_edits?(options)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      else
        IssuePrefiller.prefill([issue], repository: repo, current_user: current_user)
      end
      Reaction::Summary.prefill([issue])

      deliver :issue_hash, issue,
        repo: repo,
        full: true,
        last_modified: calc_last_modified_for_object(issue)
    else
      handle_issue_not_found
    end
  end

  verbs :patch, :post, "/repositories/:repository_id/issues/:issue_number", operation_id: "issues/update" do
    replica_clusters = T.let([ApplicationRecord::Repositories, ApplicationRecord::IamAbilities, ApplicationRecord::Collab, ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      repo = current_repo
      unless issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)
        return handle_issue_not_found
      end
      issue = T.cast(issue, Issue)

      set_context_controller_action(
        issue, "edit-issue"
      )

      control_access :edit_issue,
        resource: issue,
        repo: repo,
        challenge: repo.public?,
        # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
        # Therefore, we could leave off the integration-related key/value pairs in this call.
        # However, that would count against our linter, so for completeness, we are adding them.
        forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: repo.private?

      ensure_not_blocked! current_user, repo.owner_id
      ensure_issue_visible!(repo, issue)
      authorize_content(repo, :update)

      data = receive_with_schema("issue", "update-legacy")

      # Don't let non collabs set these
      unless access_allowed?(:set_collab_only_attributes_on_new_issue, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true)
        data.delete_if { |key, _value| COLLAB_ONLY_ATTRIBUTES.include?(key) }
      end

      if data.include?(ISSUE_TYPE)
        if repo.owner.issue_types_enabled?
          if data[ISSUE_TYPE].present?
            issue_type = Issues.domain.issue_types.by_organization_and_name(repo.owner, data[ISSUE_TYPE])

            if issue_type&.enabled?
              issue.issue_type_id = issue_type.id
            else
              deliver_error! 422,
              errors: [api_error(:Issue, :type, :invalid, value: data[ISSUE_TYPE])],
              documentation_url: @documentation_url
            end
          else
            issue.issue_type_id = nil
          end
        end

        data.delete(ISSUE_TYPE)
      end

      assignee_keys = [ASSIGNEE, ASSIGNEES].select { |key| data.key?(key) }
      if assignee_keys.length == 2
        deliver_error! 422, message: "You cannot pass both `assignee` and `assignees`. Only one may be provided."
      end

      assignee_data = {}
      update_issue_orchestration = T.let(nil, T.nilable(IssueOrchestration))

      if assignee_keys.present?
        assignees = prepare_assignees(repo: repo, assignee_keys: assignee_keys,
          data: data, documentation_url: @documentation_url, author: issue.user, issue: issue)
        assignee_ids = assignees.map(&:id)
        assignee_data[:user_assignee_ids] = assignee_ids
        data["user_assignee_ids"] = assignee_ids
      end

      if (id = data[MILESTONE]).present?
        milestone = repo.milestones.find_by_number(id.to_i) if valid_milestone_id?(id)
        if milestone
          issue.milestone = milestone
          data["milestone_id"] = milestone.id
        else
          deliver_error! 422,
            errors: [api_error(:Issue, :milestone, :invalid, value: id)],
            documentation_url: @documentation_url
        end
      elsif data.include?(MILESTONE) && data[MILESTONE].blank?
        issue.milestone = nil
        data["milestone_id"] = nil
      end

      if data["labels"]
        if current_user.feature_enabled?(:issues_rest_api_verify_label_permissions)
          labels = labels_for(repo, Array(data["labels"]), current_user, issue)
        else
          labels = labels_for(repo, Array(data["labels"]))
        end
        data["label_ids"] = labels&.map(&:id)
      end

      if integration_user_request?
        issue.modifying_integration = current_integration
        data["integration_id"] = current_integration.id
      end

      if data.key?("state_reason")
        data.delete("state_reason") if data["state_reason"] == "completed"
        # the duplicate state reason it not exposed yet in the api
        data.delete("state_reason") if data["state_reason"] == "duplicate"
        unless reason_is_valid?(data["state_reason"])
          deliver_error! 422, message: "Please specify a valid state reason.", documentation_url: @documentation_url
        end
      end

      errors = nil
      saved = T.let(false, T::Boolean)

      begin
        issue.skip_hydro_update_event_instrumentation = true
        attributes = attr(data, :title)
        previous_title = issue.title
        previous_body = issue.body

        wanted_state_reason = data["state_reason"]
        state_reason_changing = wanted_state_reason != issue.state_reason

        IssueOrchestration.transaction do # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
          issue.skip_update_issue_orchestration = true
          saved = if data["state"] =~ /\Aclose/i && (issue.open? || state_reason_changing)
            if issue.closed? && state_reason_changing && !issue.reopenable_by?(current_user)
              # if the issue is closed and current_user cannot reopen it they also aren't allowed to update the state_reason
              # because performing that would subsequently allow them to reopen the issue
              deliver_error! 403, message: "Insufficient permissions to update the state_reason.", documentation_url: @documentation_url
            end

            close_attributes = attr(data, :title)
            close_attributes.merge!(attr(data, :state_reason))

            issue.close(current_user, attributes: close_attributes) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
          elsif data["state"] =~ /\Aopen/i && issue.closed?
            issue.reopen!(current_user, attributes) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
          else
            issue.update(attributes) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
          end

          if data.key?("body")
            issue.update_body(data["body"], current_user)
          end

          if saved
            update_issue_orchestration = IssueOrchestration.update_issue!(actor: current_user, issue: issue)
            update_issue_orchestration.data[:assignee_data] = assignee_data
          end
        end

        if saved
          issue.instrument_hydro_update_event(
            previous_title: previous_title,
            previous_body: previous_body,
          )
          issue.replace_labels(labels) unless labels.nil? # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)

          update_issue_orchestration.execute! if update_issue_orchestration
        else
          errors = issue.errors
        end
      rescue GitHub::Prioritizable::Context::LockedForRebalance
        deliver_error! 503,
          message: "This issue's milestone is temporarily locked for maintenance. Please try again.",
          documentation_url: @documentation_url
      end

      if saved
        if FeatureFlag.vexi.enabled?(:updated_issue_prefillers, default: false)
          options = Api::SerializerOptions.fill(default_options)
          IssuePrefiller.optimized_prefill([issue], repository: repo, current_user: current_user, preload_issue_edits: preload_issue_edits?(options))
        else
          IssuePrefiller.prefill([issue], repository: repo, current_user: current_user)
        end
        Reaction::Summary.prefill([issue])

        deliver :issue_hash, issue, repo: repo, full: true
      else
        deliver_error 422,
          errors: errors,
          documentation_url: @documentation_url
      end
    end
  end

  LockIssueQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($issueId: ID!, $lockReason: LockReason, $clientMutationId: String!) {
      lockLockable(input: {
        lockableId: $issueId,
        lockReason: $lockReason,
        clientMutationId: $clientMutationId
      }) {
        lockedRecord {
          locked
        }
      }
    }
  GRAPHQL

  put "/repositories/:repository_id/issues/:issue_number/lock", operation_id: "issues/lock" do
    replica_clusters = T.let([ApplicationRecord::Repositories, ApplicationRecord::Collab, ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      repo = current_repo
      issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)

      record_or_404(issue)
      issue = T.cast(issue, Issue)

      set_context_controller_action(issue,  "lock")
      @accepted_scopes = repo.public? ? %w[public_repo repo] : %w[repo]

      control_access :lock_issue,
        resource: issue,
        repo: repo,
        challenge: repo.public?,
        # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
        # Therefore, we could leave off the integration-related key/value pairs in this call.
        # However, that would count against our linter, so for completeness, we are adding them.
        forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true

      data = receive_with_schema("issue-lock", "close-legacy")
      lock_reason = data["lock_reason"]

      input_variables = {
        "issueId"          => issue.global_relay_id,
        "clientMutationId" => request_id,
        "enterprise"       => GitHub.enterprise?,
      }
      input_variables["lockReason"] = Platform::Enums::Base.convert_string_to_enum_value(lock_reason) if lock_reason.present?

      results = platform_execute(LockIssueQuery, variables: input_variables)

      if results.errors.all.any?
        errors = results.errors.all.details["data"]
        error_types = errors.map { |err| err["type"] }
        if !(error_types & %w(NOT_FOUND UNAUTHENTICATED)).empty?
          deliver_error! 404, message: "Not Found"
        elsif error_types.any? { |err| err == "FORBIDDEN" }
          deliver_error! 403, message: "Forbidden"
        elsif error_types.any? { |err| err == "REPOSITORY_MIGRATION" }
          deliver_error! 403, message: "Repository has been locked for migration."
        elsif error_types.any? { |err| err == "REPOSITORY_ARCHIVED" }
          deliver_error! 403, message: "Repository was archived so is read-only."
        elsif error_types.any? { |err| err == "ISSUES_DISABLED" }
          deliver_error! 410, message: "Issues are disabled for this repo", documentation_url: "/v3/issues/"
        else
          deliver_error! 422, errors: results.errors.values.flatten
        end
      end

      deliver_empty(status: 204)
    end
  end

  UnlockIssueQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($issueId: ID!, $clientMutationId: String!) {
      unlockLockable(input: {
        lockableId: $issueId,
        clientMutationId: $clientMutationId
      }) {
        unlockedRecord {
          locked
        }
      }
    }
  GRAPHQL

  # Unlock an Issue's conversation
  delete "/repositories/:repository_id/issues/:issue_number/lock", operation_id: "issues/unlock" do
    # Introducing strict validation of the issue-lock.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("issue-lock", "delete", skip_validation: true)

    replica_clusters = T.let([ApplicationRecord::Repositories, ApplicationRecord::Collab, ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      repo = current_repo
      issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)

      record_or_404(issue)
      issue = T.cast(issue, Issue)

      set_context_controller_action(issue, "unlock")
      @accepted_scopes = repo.public? ? %w[public_repo repo] : %w[repo]

      control_access :unlock_issue,
        resource: issue,
        repo: repo,
        challenge: repo.public?,
        # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
        # Therefore, we could leave off the integration-related key/value pairs in this call.
        # However, that would count against our linter, so for completeness, we are adding them.
        forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true

      input_variables = {
        "issueId"          => issue.global_relay_id,
        "clientMutationId" => request_id,
        "enterprise"       => GitHub.enterprise?,
      }

      results = platform_execute(UnlockIssueQuery, variables: input_variables)

      if has_graphql_system_errors?(results)
        deprecated_deliver_graphql_error! errors: results.errors, resource: "Issue"
      elsif has_graphql_mutation_errors?(results)
        deliver_graphql_mutation_errors! results, input_variables: input_variables, resource: "Issue"
      end

      deliver_empty(status: 204)
    end
  end

  get "/repositories/:repository_id/assignees", operation_id: "issues/list-assignees" do
    control_access :list_assignees,
      repo: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    assignees = paginate_rel(get_assignees)
    deliver :user_hash, assignees
  end

  get "/repositories/:repository_id/assignees/:username", operation_id: "issues/check-user-can-be-assigned" do
    control_access :list_assignees, repo: current_repo, allow_integrations: true, allow_user_via_granular_actor: true
    assignees = get_assignees

    if assignees.pluck(:display_login).include?(params[:username])
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  def resolve_tenant_from_user
    return unless current_user.present?
    Business.find_by(id: current_user.business_id)
  end

  private

  def ensure_issue_visible!(repo, issue)
    ensure_repo_writable!(repo)
    ensure_issues_enabled_or_pr!(repo, issue)
    deliver_error!(404) unless issue_visible_to_user?(issue)
  end

  def issue_visible_to_user?(issue)
    issue.present? && !issue.hide_from_user?(current_user)
  end

  def valid_milestone_id?(id)
    id.is_a?(Numeric) || (id.is_a?(String) && id =~ /\A\d+\z/)
  end

  def reason_is_valid?(reason)
    Issue.state_reasons.include?(reason) || reason.nil?
  end

  def filter_dash_scope(scope)
    if explicitly_false(params[:collab])
      scope = scope.excluding_repository_ids(@member_repo_ids)
    end

    if explicitly_false(params[:orgs])
      scope = scope.excluding_repository_ids(@org_repo_ids)
    end

    if explicitly_false(params[:owned])
      scope = scope.excluding_repository_ids(@owned_repo_ids)
    end

    if explicitly_false(params[:pulls])
      scope = scope.without_pull_requests
    end

    scope
  end

  # Helper to check if a String is present yet falsey
  #
  # value - The param value
  #
  # Returns a Boolean
  def explicitly_false(value)
    value.present? && !parse_bool(value)
  end

  def filter_issues_for_repos_without_programmatic_access(repo_ids)
    public_repository_ids = Repository.where(id: repo_ids).public_scope.pluck(:id)
    if public_repository_ids.count == repo_ids.uniq.count
      return Issue.for_repository_ids(public_repository_ids)
    end

    private_repository_ids = repo_ids - public_repository_ids
    issues_filtered_ids = ProgrammaticActor::RepositoryFilter.perform(
      actor: current_user,
      repository_ids: private_repository_ids,
      resource: "issues",
    )

    pr_filtered_ids = ProgrammaticActor::RepositoryFilter.perform(
      actor: current_user,
      repository_ids: private_repository_ids,
      resource: "pull_requests",
    )

    if issues_filtered_ids.none? && pr_filtered_ids.none?
      return Issue.for_repository_ids(public_repository_ids)
    end

    scopes = []

    scopes << Issue.where(repository_id: public_repository_ids) if public_repository_ids.any?

    both = issues_filtered_ids.intersection(pr_filtered_ids)
    scopes << Issue.where(repository_id: both) if both.any?

    pr_filtered_ids = pr_filtered_ids.difference(issues_filtered_ids)
    scopes << Issue.where(repository_id: pr_filtered_ids).
                where("issues.pull_request_id IS NOT NULL") if pr_filtered_ids.any?

    issues_filtered_ids = issues_filtered_ids.difference(pr_filtered_ids)
    scopes << Issue.where(repository_id: issues_filtered_ids).
                where("issues.pull_request_id IS NULL") if issues_filtered_ids.any?

    return Issue.none if scopes.empty?

    scopes.inject(:or)
  end

  def get_assignees
    current_repo.visible_available_assignees_for(current_user).order("users.login").filter_spam_for(current_user)
  end

  # Takes a given assignee passed in by the client, parses it for keywords (like
  # "*", "none", and so on), and correctly scopes the database query
  # accordingly.
  #
  # query - The query components Array to pass on to Issue::MysqlSearch.
  # login - The String login from the client that we want to use to filter.
  #
  # Returns a modified `query` object.
  def assignee_filter(query, login)
    case login
    when "*"
      query << [:assignee, login]
    when "none"
      query << [:no, "assignee"]
    else
      assignee = User.find_by_login(login)

      if assignee
        # login used for mysql search therefore safe to use here.
        query << [:assignee, assignee.login] # rubocop:disable GitHub/DoNotAllowLogin
      else
        deliver_error! 422,
          errors: [api_error(:Issue, :assignee, :invalid, value: login)],
          documentation_url: "/v3/issues/#list-issues"
      end
    end
  end

  # Filters the issue query to the user that's mentioned.
  #
  # query - The query components Array to pass on to Issue::MysqlSearch.
  # login - The String login from the client that we want to use to filter.
  #
  # Returns a modified `query` object.
  def mention_filter(query, login)
    query << [:mentions, login]
  end

  # Takes a given milestone passed in by the client, parses it for keywords (like
  # "*", "none", and so on), and correctly scopes the database query
  # accordingly.
  #
  # repo  - The Repository whose issues we're filtering.
  # query - The query components Array to pass on to Issue::MysqlSearch.
  # text  - The String text from the client that we want to use to filter.
  #
  # Returns a modified `query` object.
  def milestone_filter(repo, query, text)
    case text
    when Search::Filter::WILDCARD, Search::Filter::ANY
      query << [:milestone, Search::Filter::WILDCARD]
    when Search::Filter::NONE
      query << [:no, "milestone"]
    when Array, Hash
      deliver_error! 422,
        errors: [api_error(:Issue, :milestone, :invalid, value: text)],
        documentation_url: "/v3/issues/#list-issues"
    else
      milestone = repo.milestones.find_by_number(text.to_i)

      if milestone
        query << [:milestone, milestone.title]
      else
        deliver_error! 422,
          errors: [api_error(:Issue, :milestone, :invalid, value: text)],
          documentation_url: "/v3/issues/#list-issues"
      end
    end
  end

  def issue_type_filter(repo, query, text, es_search = false)
    case text
    when Search::Filter::WILDCARD, Search::Filter::ANY
      query << (es_search ? [:has, "type"] : [:type, Search::Filter::WILDCARD])
    when Search::Filter::NONE
      query << [:no, "type"]
    when Array, Hash
      deliver_error! 422,
        errors: [api_error(:Issue, :type, :invalid, value: text)],
        documentation_url: "/v3/issues/#list-issues"
    else
      issue_type = deliver_error_or_get_issue_type(repo.owner, text, "/v3/issues/#list-issues", repo)
      query << [es_search ? :issue_type : :type, issue_type.name]
    end
  end

  # Maps API parameters to their search term syntax.
  SEARCH_PARAM_MAPPING = {
    STATE   => :state,
    CREATOR => :author,
  }

  # Takes the mappings above and prepopulates the query components from the
  # request params.
  def search_param_mapping(params)
    query = T.let([], T::Array[T.untyped])

    SEARCH_PARAM_MAPPING.each do |key, term|
      query += Array(params[key]).map { |value| [term, value] }
    end

    query
  end

  def authorize_content(authorizable, operation = :create)
    authorization = Issues::ContentAuthorizer.new(current_user, operation, repo: authorizable)
    deliver_content_authorization_denied!(authorization) if authorization.failed?
  end

  # Inspects the data for assignment via direct (single) assignment or multiple
  # assignment. Builds up a list of valid assignees, responding with a 422 on
  # the first invalid assignment.
  #
  #   repo - The Repository to check for assignability
  #   assignee_keys - Array of keys with values in the data hash
  #   data - The Hash of data parsed from the request
  #   author - The creator of the issue
  #   issue - The issue, if it already exists. Ignore during issue creation.
  #
  # Returns an Array of assignees
  def prepare_assignees(repo:, assignee_keys:, data:, documentation_url:, author:, issue: nil)
    assignees = T.let([], T::Array[User])

    assignee_keys.each do |key|
      assignee_logins = Array.wrap(data.fetch(key)).compact_blank.uniq

      users = User.with_logins(assignee_logins).index_by(&:display_login).transform_keys(&:downcase)
      assignee_logins.each do |login|
        user = users[login.downcase]
        if user && is_assignable_user(repo, user, author, issue)
          assignees << user
        else
          deliver_error! 422,
            errors: [api_error(:Issue, key.to_sym, :invalid, value: login)],
            documentation_url: documentation_url
        end
      end
    end

    assignees
  end

  # Internal: Determines whether the user can be an assignee on the issue in the given repository.
  #
  # repo  - A Repository.
  # login - A String username.
  # author - The creator of the issue.
  # issue - The issue, if it already exists. Can be nil during issue creation.
  #
  # Returns true if the user is assignable to the issue, false otherwise.
  def is_assignable_user(repo, user, author, issue)
    return true if user == author
    return true if repo.assignable_member?(user)
    return true if issue && issue.comments.pluck(:user_id).include?(user.id)

    false
  end

  def since_filter_es(table_name)
    time = Time.parse(time_param!(:since).to_s).getlocal.iso8601
    [:updated, ">=#{time}"]
  rescue ArgumentError
    docs_url = case table_name
    when "pull_requests"
      "/v3/pulls/#list-pull-requests"
    else
      "/v3/issues/#list-issues"
    end
    deliver_error! 422,
      message: "Invalid datetime for since",
      documentation_url: docs_url
  end
end
