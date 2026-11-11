# typed: true
# frozen_string_literal: true

class Api::Issues < Api::App
  include ReceiveSchemaWithOpenApi
  include Scientist
  include Api::App::UsersDependency
  include Api::App::Mysql1ReplicaAuth
  include GitHub::RateLimitable
  include Api::DatabaseResourceUpdateRateLimiting

  module EnsureIssuesEnabled
    extend T::Helpers

    requires_ancestor { Api::App::ErrorDependency }

    DEFAULT_SEMANTIC_SIMILAR_ISSUE_LIMIT = 3

    # Checks repository after access control to ensure issues
    # are enabled for this repository.
    def ensure_issues_enabled!(repo)
      unless repo.has_issues?
        deliver_error!(410,
          message: "Issues are disabled for this repo",
          documentation_url: "/v3/issues/")
      end
    end

    # Checks repository after access control to ensure pull requests
    # are enabled for this repository.
    def ensure_pull_requests_enabled!(repo)
      unless repo.has_pull_requests?
        deliver_error!(410,
          message: "Pull requests are disabled for this repo",
          documentation_url: "/v3/pulls/")
      end
    end

    # Halts with a 410 if the issue is not a Pull and the repo has disabled issues, or
    # if it is a Pull and the repo has disabled pull requests
    def ensure_issues_enabled_or_pr!(repo, issue)
      return if !issue
      if issue.pull_request_id
        ensure_pull_requests_enabled!(repo)
      else
        ensure_issues_enabled!(repo)
      end
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
        documentation_url: documentation_url
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
          resource: repo,
          repo: repo,
          allow_integrations: true,
          allow_user_via_granular_actor: true

        new_repo = transferred_issue.repository
        ensure_issues_enabled_or_pr!(new_repo, transferred_issue)

        new_repo_access_options = { resource: new_repo, repo: new_repo, allow_integrations: true, allow_user_via_granular_actor: true }
        allowed = if use_authzd_ctrl_access?(:list_issues, new_repo_access_options)
          access_allowed_remote?(:list_issues, new_repo_access_options, serving_prod_traffic: true)
        else
          access_allowed?(:list_issues, new_repo_access_options) # rubocop:disable GitHub/AllowUserViaGranularActor, GitHub/AllowIntegrations
        end

        if allowed
          redirect_url = api_url("/repos/#{new_repo.name_with_display_owner}/issues/#{transferred_issue.number}")
          redirect_url = "#{redirect_url}#{resource_url_suffix}" if resource_url_suffix
          deliver_redirect!(redirect_url, status: 301)
        else
          deliver_redirect!("", status: 301)
        end
      elsif DeletedIssue.where(repository_id: repo.id, number: int_id_param!(key: :issue_number)).exists?
        deleted_issue_access_options = { resource: repo, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true }
        allowed_deleted = if use_authzd_ctrl_access?(:list_issues, deleted_issue_access_options)
          access_allowed_remote?(:list_issues, deleted_issue_access_options, serving_prod_traffic: true)
        else
          access_allowed?(:list_issues, deleted_issue_access_options) # rubocop:disable GitHub/AllowUserViaGranularActor, GitHub/AllowIntegrations
        end
        if allowed_deleted
          deliver_error!(410, message: "This issue was deleted")
        else
          deliver_error!(404)
        end
      else
        deliver_error!(404)
      end
    end
  end

  module IssueCopilotAssigneeHelper
    extend T::Helpers

    requires_ancestor { Api::App::ErrorDependency }

    # Checks if Copilot bot is assigned in the given list of users.
    def copilot_assigned?(users)
      users.any? { |user| user.is_a?(Bot) && user.copilot_swe_agent? }
    end

    # Checks if any bot is assigned in the given list of users.
    def bot_assigned?(users)
      users.any? { |user| user.is_a?(Bot) }
    end

    # Checks if the Copilot assignment REST API feature is enabled for the current user.
    def copilot_assignment_rest_api_support_enabled?
      T.unsafe(self).current_user&.feature_flag_enabled?(:issues_copilot_assignment_rest_api_support, default: false) || false
    end

    # Delivers an error when Copilot assignment is not allowed.
    def deliver_copilot_assignment_not_allowed_error!(copilot_removed: nil)
      errors = [api_error(:Issue, :assignees, :invalid,
        message: "Copilot cannot be #{copilot_removed ? "unassigned" : "assigned"} without proper access rights",
        value: [Apps::Privileged::CopilotSWEAgent::SLUG])]

      deliver_error! 422, errors: errors, documentation_url: @documentation_url
    end

    # GitHub App installation tokens cannot assign agents because agent
    # assignment requires a user token that can be passed to the agent runtime.
    def validate_rest_api_agent_assignment_allowed_by_token!
      return unless integration_bot_request?

      deliver_error! 403,
        message: "Assigning agents is not supported with GitHub App installation tokens. Use a user token (personal access token or OAuth token) instead."
    end

    # Helper method to look up assignees (users and bots) by their login.
    def lookup_assignees_by_login(logins)
      string_logins = Array(logins).grep(String)
      bot_logins, user_logins = string_logins.partition { |login| login.ends_with?(Bot::LOGIN_SUFFIX) }

      regular_users = user_logins.any? ? Users.domain.by_logins(user_logins) : []
      bots = bot_logins.any? ? Bot.with_slugs(bot_logins).to_a : []

      regular_users + bots
    end

    # Processes agent_assignment data and returns a copilot context for orchestration.
    def process_copilot_agent_assignment(data, current_repo)
      agent_assignment = data["agent_assignment"] || {}
      target_repo = if agent_assignment["target_repo"]
        Repository.with_name_with_owner(agent_assignment["target_repo"])
      end

      # Validate target_repo exists if explicitly provided
      if agent_assignment["target_repo"].present? && target_repo.nil?
        deliver_error! 404, message: "Target repository not found"
      end

      target_repo ||= current_repo

      if target_repo.archived?
        deliver_error! 422, message: "Cannot assign Copilot to issues in archived repositories."
      end

      cap_unauthorized = if FeatureFlag.vexi.enabled?(:copilot_assignment_cap_target_repo_check, current_user, default: false)
        cap_filter.unauthorized_resource_ids([target_repo]).include?(target_repo.id)
      else
        false
      end
      if target_repo != current_repo && (!target_repo.writable_by?(current_user) || !target_repo.writable? || cap_unauthorized)
        deliver_error! 404, message: "Target repository not found"
      end

      base_ref = agent_assignment["base_branch"].presence || target_repo.default_branch
      custom_instructions = agent_assignment["custom_instructions"]
      custom_agent = agent_assignment["custom_agent"]
      model = if FeatureFlag.vexi.enabled?(:coding_agent_model_selection, current_user, default: false)
        agent_assignment["model"]
      end

      copilot_attributes = Issues::AgentAssignmentNewAttributes.new(
        target_repository: target_repo,
        base_ref: base_ref,
        custom_instructions: custom_instructions,
        custom_agent: custom_agent,
        remote_ip: remote_ip,
        model: model
      )

      request_token_value = request_credentials.token&.to_s
      viewer_using_pat = current_user.using_personal_access_token? || current_user.using_auth_via_user_programmatic_access?
      should_mint = viewer_using_pat && FeatureFlag.vexi.enabled?(:copilot_mint_token_for_api_requests, current_user, default: false)

      token = if request_token_value.present? && !should_mint
        GitHub.encrypt_and_encode_capi_token(request_token_value)
      elsif request_token_value.present?
        begin
          CopilotSessions::CopilotApiToken.get_encrypted(
            user: current_user,
            entry_point: :issues_api_copilot_assignment,
            user_session: nil,
            force_cache_miss: true,
          )
        rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError
          nil
        end
      end

      T.let({
        request_token: token.to_s,
        attributes: copilot_attributes,
      }, IssueOrchestration::CopilotContext)
    end
  end

  module IssueFieldValuesHelper
    extend T::Helpers

    include Api::App::ErrorDependency

    def get_issue_field_update_attributes(current_issue_field_ids, issue_field_values, mode)
      new_issue_field_ids = issue_field_values.map { |issue_field_value| issue_field_value["field_id"] }.compact
      issue_field_ids_to_delete = []
      if mode == "set"
        issue_field_ids_to_delete = current_issue_field_ids - new_issue_field_ids
      elsif mode == "add"
        issue_field_ids_to_delete = issue_field_values.size == 0 ? current_issue_field_ids : []
      end

      update_attributes = []
      issue_field_ids_to_delete.each do |issue_field_id|
        update_attributes << Issues::IssueFieldDeleteAttributes.new(field_id: T.must(issue_field_id))
      end
      issue_fields_by_id = IssueField.where(id: new_issue_field_ids).index_by(&:id)
      new_issue_field_ids.each do |issue_field_id|
        issue_field = issue_fields_by_id[issue_field_id]
        if issue_field.nil?
          deliver_error! 422, message: "Issue field with id #{issue_field_id} not found"
        end

        issue_field_value = issue_field_values.find { |v| v["field_id"] == issue_field_id }
        value = issue_field_value["value"]

        # Delegate the raw_value -> typed attributes conversion (and the coarse
        # type checking that goes with it) to IssueField#build_value_attributes
        # so the REST endpoint, the apply-suggestion mutation, and any future
        # call site stay in lock-step on what shapes are accepted.
        begin
          update_attributes << issue_field.build_value_attributes(value)
        rescue ::IssueField::InvalidValueError => e
          deliver_error! 422, message: e.message
        end
      end
      update_attributes
    end

    # Validates a user-supplied input value for an IssueField by delegating to
    # both layers of validation that the value will eventually face:
    #   1. IssueField#build_value_attributes: the coarse type/conversion check
    #      shared with the apply-suggestion mutation and the REST update path.
    #   2. The IssueFieldValue subclass validations: the deeper rules (number
    #      format and int32 bounds, ISO 8601 date parsing, etc.) that run when
    #      the value is persisted.
    # Going through both layers ensures suggestions can't be stored in a shape
    # the apply step would later reject.
    #
    # Returns nil when valid, or a human-readable error message describing the
    # first validation failure.
    sig { params(issue_field: IssueField, value: T.untyped).returns(T.nilable(String)) }
    def validate_field_value_input(issue_field, value)
      attributes = issue_field.build_value_attributes(value)

      raw_value =
        case attributes
        when Issues::IssueFieldTextValueAttributes then attributes.text_value
        when Issues::IssueFieldSingleSelectValueAttributes then attributes.option_id
        when Issues::IssueFieldMultiSelectValueAttributes then attributes.option_ids
        when Issues::IssueFieldNumberValueAttributes then attributes.number_value
        when Issues::IssueFieldDateValueAttributes then attributes.date_value
        end

      transient = IssueFieldValue.sti_class_for(issue_field.data_type).new(issue_field: issue_field, value: raw_value)
      transient.valid?
      transient.errors[:value].first
    rescue ::IssueField::InvalidValueError => e
      e.message
    end

    # Returns true when an existing issue field value already matches the
    # user-supplied input. Used to skip suggestions whose proposed value is
    # already applied in the REST `PATCH /repos/:owner/:repo/issues/:number`
    # handler.
    #
    # Routes the input through `issue_field.build_value_attributes` (same call
    # used by validate_field_value_input) so input ↔ stored comparison shares a
    # single canonical form per data_type
    sig { params(existing: IssueFieldValue, issue_field: IssueField, input: T.untyped).returns(T::Boolean) }
    def field_value_matches_input?(existing, issue_field, input)
      attributes = issue_field.build_value_attributes(input)
      case attributes
      when Issues::IssueFieldTextValueAttributes
        existing.is_a?(IssueFieldTextValue) && existing.value == attributes.text_value
      when Issues::IssueFieldSingleSelectValueAttributes
        existing.is_a?(IssueFieldSingleSelectValue) && existing.option&.id == attributes.option_id
      when Issues::IssueFieldMultiSelectValueAttributes
        existing.is_a?(IssueFieldMultiSelectValue) && existing.options.map(&:id).sort == Array(attributes.option_ids).sort
      when Issues::IssueFieldNumberValueAttributes
        existing.is_a?(IssueFieldNumberValue) && BigDecimal(existing.value.to_s) == attributes.number_value
      when Issues::IssueFieldDateValueAttributes
        existing.is_a?(IssueFieldDateValue) && existing.value == attributes.date_value
      end
    rescue ::IssueField::InvalidValueError
      false
    end
  end

  module Preload
    # Use this to preload data for an array of issues
    def prefill_for_multiple_issues(issues, options:)
      current_user = T.unsafe(self).current_user
      IssuePrefiller.optimized_prefill(
        issues,
        current_user: current_user,
        mime_param: mime_param(options),
      ) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      Reaction::Summary.prefill(issues)
      Repository.prefill_associations(issues.map(&:repository), internal: true)
    end

    def preload_issue_edits?(options)
      params = options[:mime_params]
      params.include?(:html) || params.include?(:full) || params.include?(:text)
    end

    def mime_param(options)
      params = options[:mime_params]

      return :html if params.include?(:html)

      return :full if params.include?(:full)

      :text if params.include?(:text)
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

  include Api::Labels::Helpers, Api::Issues::EnsureIssuesEnabled, Api::Issues::EnsureIssuesTypesEnabled, Scientist, Api::Issues::HandleIssueNotFound, Api::Issues::Limits, Api::Issues::Preload, Api::Issues::IssueFieldValuesHelper, Api::Issues::IssueCopilotAssigneeHelper
  include Api::App::DatabaseConnectionHelper

  STATE = "state".freeze
  STATE_REASON = "state_reason".freeze
  ASSIGNEE   = "assignee".freeze
  ASSIGNEES  = "assignees".freeze
  MILESTONE  = "milestone".freeze
  CREATOR    = "creator".freeze
  MENTIONED  = "mentioned".freeze
  LABELS     = "labels".freeze
  ISSUE_TYPE = "type".freeze
  ISSUE_FIELD_VALUES = "issue_field_values".freeze
  COLLAB_ONLY_ATTRIBUTES = [ASSIGNEE, ASSIGNEES, LABELS, MILESTONE, ISSUE_TYPE, ISSUE_FIELD_VALUES]
  MILESTONE_LOCKED_FOR_REBALANCE = "This issue's milestone is temporarily locked for maintenance. Please try again."

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
    replica_clusters = T.let([ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::Collab, ApplicationRecord::IamAbilities, ApplicationRecord::IssuesPullRequests], T::Array[T.class_of(ApplicationRecord::Base)])
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters, current_user: current_user, feature_flag: :issues_rest_gets_replica_reads) do
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
      options = Api::SerializerOptions.fill(default_options)
      prefill_for_multiple_issues(issues, options: options)

      deliver :issue_hash, issues, repositories: true
    end
  end

  # List issues for repositories under a specific organizations
  get "/organizations/:organization_id/issues", operation_id: "issues/list-for-org" do
    replica_clusters = T.let([ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::Collab, ApplicationRecord::IamAbilities, ApplicationRecord::IssuesPullRequests], T::Array[T.class_of(ApplicationRecord::Base)])
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters, current_user: current_user, feature_flag: :issues_rest_gets_replica_reads) do
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

      options = Api::SerializerOptions.fill(default_options)

      prefill_for_multiple_issues(issues, options: options)
      deliver :issue_hash, issues, repositories: true, full: true
    end
  end

  # List issues for the current user across all owned and member repositories
  get "/user/issues", operation_id: "issues/list-for-authenticated-user" do
    replica_clusters = T.let([ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::Collab, ApplicationRecord::IamAbilities, ApplicationRecord::IssuesPullRequests], T::Array[T.class_of(ApplicationRecord::Base)])
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters, current_user: current_user, feature_flag: :issues_rest_gets_replica_reads) do
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
        options = Api::SerializerOptions.fill(default_options)

        prefill_for_multiple_issues(issues, options: options)
      end
      GitHub.dogstats.distribution_time "api.deliver", tags: ["action:user_issues_list"] do
        deliver :issue_hash, issues, repositories: true
      end
    end
  end

  # List issues for this Repository
  get "/repositories/:repository_id/issues", operation_id: "issues/list-for-repo" do
    with_replica_clusters([ApplicationRecord::Mysql1]) do
      repo = current_repo
      control_access :list_issues,
        resource: repo,
        repo: repo,
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

      query = search_param_mapping(params)

      # Bring in labels and split them if it's a comma,delimited,string
      if (labels = params[:labels]).present? && labels.respond_to?(:split)
        labels.split(",").each do |label_string|
          query << [:label, label_string]
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
          issue_type_filter(repo, query, params[ISSUE_TYPE])
        else
          deliver_issue_type_error(params[ISSUE_TYPE], @documentation_url)
        end
      end

      # Scope mentions
      if params[MENTIONED]
        mention_filter(query, params[MENTIONED])
      end

      # Scope issue field values
      if params[ISSUE_FIELD_VALUES]
        if IssueFieldsFeature.enabled?(repo, actor: current_user)
          issue_field_values_filter(repo, query, params[ISSUE_FIELD_VALUES])
        else
          deliver_error! 422,
            errors: [api_error(:Issue, :issue_field_values, :invalid, value: params[ISSUE_FIELD_VALUES])],
            documentation_url: "/v3/issues/#list-issues"
        end
      end

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

      issues = scope[:issues]

      disable_issues_graph = repo.feature_flag_enabled_or_raise?(:disable_issues_graph_in_list_for_repo) || current_user&.feature_flag_enabled_or_raise?(:disable_issues_graph_in_list_for_repo) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

      GitHub.dogstats.distribution_time "api.prefill", tags: ["action:repository_issues_list"] do
        # We do not use the prefill_for_multiple_issues method here because
        # this is the only List issues endpoint that does not return a repository object
        # in it's response. In it's place, we prefill the data that we specifically need.
        options = Api::SerializerOptions.fill(default_options)
        IssuePrefiller.optimized_prefill(issues, repository: repo, current_user: current_user, mime_param: mime_param(options), disable_issues_graph: disable_issues_graph) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        Reaction::Summary.prefill(issues)
      end

      GitHub.dogstats.distribution_time "api.deliver", tags: ["action:repository_issues_list"] do
        if disable_issues_graph
          deliver :issue_hash, issues, full: true, disable_issues_graph: true
        else
          deliver :issue_hash, issues, full: true
        end
      end
    end
  end

  # Create an Issue
  post "/repositories/:repository_id/issues", operation_id: "issues/create" do
    replica_clusters = T.let([ApplicationRecord::IamAbilities, ApplicationRecord::Collab, ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters) do
      with_replica_clusters([ApplicationRecord::Repositories]) do
        control_access :open_issue,
          repo: current_repo,
          enforce_oauth_app_policy: current_repo.private?,
          allow_integrations: true,
          allow_user_via_granular_actor: true
      end
    end

    attributes = T.let(nil, T.nilable(Issues::CreateIssueAttributes))
    copilot_context = T.let(nil, IssueOrchestration::CopilotContext)

    replica_clusters = T.let([ApplicationRecord::IamAbilities, ApplicationRecord::Collab, ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters) do
      with_replica_clusters([ApplicationRecord::Repositories]) do
        data = receive_with_schema("issue", "create-legacy")

        issue_type = if current_repo.owner.organization?
          find_or_error!(data[ISSUE_TYPE], ISSUE_TYPE) do |type|
            Issues.domain.issue_types.by_organization_and_name(T.cast(current_repo.owner, Organization), type || "")
          end
        end

        if changeset_active?(:remove_singular_assignee_from_issues_and_pull_requests)
          assignee_keys = [ASSIGNEES].select { |key| data.key?(key) }
        else
          assignee_keys = [ASSIGNEE, ASSIGNEES].select { |key| data.key?(key) }
          if assignee_keys.length == 2
            deliver_error! 422, message: "You cannot pass both `assignee` and `assignees`. Only one may be provided."
          end
        end

        users = T.cast(nil, T.nilable(T::Array[Users::IUser]))
        assignees = T.cast(nil, T.nilable(T::Array[Users::IUser]))
        assignee = T.cast(nil, T.nilable(Users::IUser))

        if (assignee_key = assignee_keys.first)
          users = find_or_error!(data[assignee_key], assignee_key.to_sym) do |assignees_data|
            raw_logins = Array.wrap(assignees_data || []).filter(&:present?)
            potential_logins = raw_logins.map { |login| login.to_s.downcase }

            actual_users = lookup_assignees_by_login(potential_logins)

            # Return only if we found all requested users/bots
            actual_users if actual_users.length == potential_logins.length
          end

          assignee_key == ASSIGNEE ? assignee = users.first : assignees = users
        end

        milestone = find_or_error!(data[MILESTONE], :milestone) do |id|
          current_repo.milestones.find_by_number(id.to_i) if id.is_a?(Numeric) || (id.is_a?(String) && id =~ /\A\d+\z/)
        end

        labels = labels_for(
          current_repo,
          Array(data["labels"]),
          current_user.feature_flag_enabled?(:issues_rest_api_verify_label_permissions, default: false) ? current_user : nil
        )

        issue_field_attributes = if data[ISSUE_FIELD_VALUES].present? && current_repo.owner.organization? && IssueFieldsFeature.enabled?(current_repo.owner, actor: current_user)
          if !data[ISSUE_FIELD_VALUES].is_a?(Array)
            deliver_error! 422, message: "Invalid request: issue_field_values must be an array"
          end
          get_issue_field_update_attributes([], data[ISSUE_FIELD_VALUES], "add")
        end

        attributes = Issues::CreateIssueAttributes.new(
          repository: current_repo,
          title: data["title"].to_s,
          body: data["body"].to_s,
          milestone: milestone,
          issue_type: issue_type,
          labels: labels,
          assignee: assignee,
          assignees: assignees,
          issue_fields: issue_field_attributes,
        )

        # Check if Copilot bot is being assigned
        # we accept both parameters, singular and plural
        all_assignees = [assignee, *assignees].compact

        # GitHub App installation tokens cannot assign bots/agents.
        validate_rest_api_agent_assignment_allowed_by_token! if bot_assigned?(all_assignees)

        copilot_assigned = copilot_assigned?(all_assignees)

        # When Copilot is assigned but feature flag is disabled, reject the assignment
        if copilot_assigned && !copilot_assignment_rest_api_support_enabled?
          deliver_copilot_assignment_not_allowed_error!
        elsif copilot_assigned && copilot_assignment_rest_api_support_enabled?
          copilot_context = process_copilot_agent_assignment(data, current_repo)
        end
      end

      result = Issues.domain.create(
        T.must(attributes),
        T.must(resolve_actor(current_repo)),
        viewer: current_user,
        integration: integration_user_request? ? current_integration : nil,
        fail_on_invalid_assignees: true,
        copilot_context: copilot_context,
      )
      case result
      when GH::Result::Ok
        issue = result.value
        GitHub.dogstats.increment("issue", tags: ["via:api", "action:create", "valid:true"])
        options = Api::SerializerOptions.fill(default_options)
        IssuePrefiller.optimized_prefill([issue], repository: current_repo, current_user: current_user, only_prefill: [:assignees], mime_param: mime_param(options))

        deliver :issue_hash, issue, status: 201, repo: current_repo, full: true
      when GH::Result::Error::LockedForRebalance
        deliver_error! 503, message: MILESTONE_LOCKED_FOR_REBALANCE, documentation_url: @documentation_url
      when GH::Result::Error::Validation
        GitHub.dogstats.increment("issue", tags: ["via:api", "action:create", "valid:false"])
        errors = result.model.errors.map do |error|
          api_error(:Issue, error.attribute, :invalid, message: error.full_message.downcase, value: error.options[:value])
        end

        deliver_error 422, errors: errors, documentation_url: @documentation_url
      when GH::Result::Error::AccessDenied
        deliver_error 403, message: result.message
      when GH::Result::Error::ContentAuthorizationError
        deliver_content_authorization_denied!(result.authorization)
      when GH::Result::Error::Forbidden
        deliver_error 404, message: result.message
      when GH::Result::Error::ServiceRateLimited
        unless GitHub.enterprise?
          @meta ||= {}
          @meta[GitHub::Limiters::Middleware::HEADER_SECONDARY_RATE_LIMITED] = "true"
        end
        error_data = parse_rate_limit_error({}, klass: Issue)
        deliver_error 403, **error_data
      when GH::Result::Error::Gone
        deliver_error 410, message: result.message
      end
    end
  end

  # Get a single Issue
  get "/repositories/:repository_id/issues/:issue_number", operation_id: "issues/get" do
    with_replica_clusters([ApplicationRecord::Mysql1]) do
      repo  = current_repo
      issue = repo && Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok

      if issue
        control_access :show_issue,
          resource: issue,
          repo: repo,
          allow_integrations: true,
          allow_user_via_granular_actor: true

        ensure_issues_enabled_or_pr!(repo, issue)

        deliver_error!(404) unless issue_visible_to_user?(issue)
        set_context_controller_action(issue, "get")
        options = Api::SerializerOptions.fill(default_options)
        IssuePrefiller.optimized_prefill([issue], repository: repo, current_user: current_user, mime_param: mime_param(options)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        Reaction::Summary.prefill([issue])

        deliver :issue_hash, issue,
          repo: repo,
          full: true,
          last_modified: calc_last_modified_for_object(issue)
      else
        handle_issue_not_found
      end
    end
  end

  verbs :patch, :post, "/repositories/:repository_id/issues/:issue_number", operation_id: "issues/update" do
    replica_clusters = T.let([ApplicationRecord::Repositories, ApplicationRecord::IamAbilities, ApplicationRecord::Collab, ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters) do
      repo = current_repo
      unless issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok
        return handle_issue_not_found
      end
      issue = T.cast(issue, Issue)

      set_context_controller_action(
        issue, "edit-issue"
      )

      # Minimum access permission for this endpoint
      control_access :custom_role_update_issue,
        resource: issue,
        repo: repo,
        challenge: repo.public?,
        forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: repo.private?

      ensure_not_blocked! current_user, repo.owner_id
      ensure_issue_visible!(repo, issue)
      authorize_content(repo, :update)

      check_database_resource_update_rate_limit!(resource: issue, repo: repo, current_user: current_user)
      data = receive_with_schema("issue", "update-legacy")

      # Filter the keys based on permissions, i.e. collab, FGP, etc.
      keys = data.keys
      # Don't let non collabs set these - however we allow FGP users past this point
      collab_access = access_allowed?(:set_collab_only_attributes_on_new_issue, repo: repo, resource: issue, allow_integrations: true, allow_user_via_granular_actor: true)
      unless collab_access
        keys.delete_if { |key| COLLAB_ONLY_ATTRIBUTES.include?(key) }
      end

      # Check if user is FGP limited (has FGP access but not full triage access)
      # FGP limited users can only modify fields they have specific FGP permissions for
      is_fgp_limited = !access_allowed?(:triage_issue, resource: issue, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true, enforce_oauth_app_policy: repo.private?)
      if is_fgp_limited
        keys = filter_keys_for_fgp_user(issue, current_user)
      end

      # Title/body updates require write access or being the author
      unless can_edit_content?(issue, repo)
        keys.delete("title")
        keys.delete("body")
      end

      # Filter the keys down to the allowed set
      data.delete_if { |key, _value| !keys.include?(key) }

      # Block flagged/spammy accounts from creating suggestions or rationale text
      # on issues. The suggestion/rationale path persists user-supplied text into
      # `Pending*Suggestion`, `Issues::UpdateIntent`, and `Issues::EventAnnotation`
      # records — none of which include the `Spammable` mixin, so a flagged account
      # (or its agent operating on a flagged account's repo) would otherwise be
      # able to inject rationale text that bypasses the usual `user_hidden`
      # filtering applied to issues and comments.
      if request_includes_suggestions_or_rationale?(data)
        ensure_actor_not_flagged_for_suggestions!(repo)
      end

      # Collects rationale and confidence keyed by [kind, target_id].
      # Populated during parsing; stored after save.
      intents = T.let({}, T::Hash[[String, Integer], Issues::EventAnnotation::Intent])

      # Evaluated once per request and reused by the type, field-values, and
      # labels suggestion blocks below. The flag's inputs don't change during a
      # single request, so re-evaluating it would just duplicate work.
      suggestion_flag_enabled = FeatureFlag.vexi.enabled?(:update_issue_suggestions, current_user, repo.owner, repo, default: false)

      # Storage backend swap from legacy Pending*Suggestion KV models to
      # Issues::UpdateIntent.
      intent_migration_enabled = FeatureFlag.vexi.enabled?(:issues_intent_model_migration, default: false)

      # Confidence-based routing requires both the suggestion infrastructure and its own flag.
      confidence_routing_enabled = suggestion_flag_enabled &&
        FeatureFlag.vexi.enabled?(:update_issue_confidence_routing, current_user, repo.owner, repo, default: false)

      # Whether confidence levels should be persisted on Pending*Suggestion records.
      # Gated independently of routing so we can ship persistence without changing
      # routing semantics.
      confidence_persist_enabled = suggestion_flag_enabled &&
        FeatureFlag.vexi.enabled?(:update_issue_confidence, current_user, repo.owner, repo, default: false)

      # Fetch the threshold once per request to avoid repeated KV/flag reads.
      repo_threshold = T.let(
        confidence_routing_enabled ? Issues::ConfidenceThreshold.get_threshold(repo) : nil,
        T.nilable(Integer),
      )

      if data.include?(ISSUE_TYPE)
        if repo.owner.issue_types_enabled?
          type_input = data[ISSUE_TYPE]
          type_name = T.let(nil, T.nilable(String))
          type_rationale = T.let(nil, T.nilable(String))
          type_confidence = T.let(nil, T.nilable(Issues::ConfidenceThreshold::Level))

          type_suggest = T.let(false, T::Boolean)

          if type_input.is_a?(Hash)
            type_name = type_input["value"]
            type_rationale = type_input["rationale"]
            type_suggest = !!type_input["suggest"]
            type_confidence = confidence_level(type_input["confidence"])
          else
            type_name = type_input
          end

          if type_name.present?
            issue_type = Issues.domain.issue_types.by_organization_and_name(repo.owner, type_name)

            if issue_type&.enabled?
              should_suggest_type = suggestion_flag_enabled && (
                type_suggest || (
                  repo_threshold && type_confidence && type_confidence.score < repo_threshold
                )
              )

              if should_suggest_type
                if intent_migration_enabled
                  # Skip silently when the issue already has this type.
                  unless issue.issue_type_id == issue_type.id
                    Issues::UpdateIntent.create_or_supersede(
                      issue_id: issue.id,
                      repository_id: repo.id,
                      action: "set_type",
                      actor_id: current_user.id,
                      rationale: type_rationale,
                      target_value: issue_type.name,
                      confidence: confidence_persist_enabled ? type_confidence : nil,
                    )
                  end
                else
                  begin
                    Issues::PendingTypeSuggestion.create(
                      repository_id: repo.id,
                      issue_id: issue.id,
                      issue_type_id: T.must(issue_type.id),
                      rationale: type_rationale || "",
                      actor_id: current_user.id,
                      confidence: confidence_persist_enabled ? type_confidence : nil,
                    )
                  rescue Issues::PendingTypeSuggestion::LimitExceeded,
                         Issues::PendingTypeSuggestion::DuplicateSuggestion => e
                    deliver_error! 422,
                      errors: [api_error(:Issue, :type, :unprocessable, message: e.message)],
                      documentation_url: @documentation_url
                  end
                end
              else
                issue.issue_type_id = issue_type.id
                # Only record an applied-path rationale intent here. Suggested types
                # carry their rationale on the `set_type` UpdateIntent record itself;
                # populating `intents` for them would generate a stray pending
                # `action: "type"` row (via `store_rationale_annotations`) that has
                # no corresponding type-changed event and gets misread as a field
                # suggestion downstream.
                if type_rationale.present?
                  intents[[Issues::EventAnnotation::KIND_TYPE, T.must(issue_type.id)]] = Issues::EventAnnotation::Intent.new(rationale: type_rationale, confidence: type_confidence)
                end
              end
            else
              deliver_error! 422,
              errors: [api_error(:Issue, :type, :invalid, value: type_name)],
              documentation_url: @documentation_url
            end
          else
            issue.issue_type_id = nil
          end
        end

        data.delete(ISSUE_TYPE)
      end
      if data.include?(ISSUE_FIELD_VALUES)
        if IssueFieldsFeature.enabled?(repo.owner, actor: current_user)
          if !data[ISSUE_FIELD_VALUES].is_a?(Array)
            deliver_error! 422, message: "Invalid request: issue_field_values must be an array"
          end

          # Partition field values into those flagged with `suggest: true` (stored as
          # pending suggestions for human review) and those that should be applied
          # directly. Suggestions are only honored when the suggestions feature flag
          # is enabled; otherwise they fall through to direct application.
          suggested_field_values, applied_field_values = data[ISSUE_FIELD_VALUES].partition do |field_value|
            next false unless suggestion_flag_enabled && field_value.is_a?(Hash)

            field_level = confidence_level(field_value["confidence"])
            !!field_value["suggest"] || (repo_threshold && field_level && field_level.score < repo_threshold)
          end

          # Extract intents for values that will be applied directly; suggested
          # values carry their rationale into the PendingFieldSuggestion record.
          applied_field_values.each do |field_value|
            if field_value.is_a?(Hash) && field_value["rationale"].present? && field_value["field_id"]
              intents[[Issues::EventAnnotation::KIND_FIELD, field_value["field_id"]]] = Issues::EventAnnotation::Intent.new(
                rationale: field_value["rationale"],
                confidence: confidence_level(field_value["confidence"]),
              )
            end
          end

          # Fetch the issue's current field values once. Used by the
          # already-applied skip check below, and by the "set" semantics for
          # the applied field values further down. Same query as pre-swap,
          # just hoisted earlier.
          current_issue_field_values = Issues.domain.issue_fields.get_issue_field_values_from_issues([issue.id], repository_ids: [issue.repository_id])[issue.id]
          current_field_values_by_field_id = T.must(current_issue_field_values).index_by { |v| v.issue_field&.id }

          if suggested_field_values.any?
            suggested_field_ids = suggested_field_values.map { |fv| fv["field_id"] }.compact
            suggested_fields_by_id = Issues.domain.issue_fields
              .by_organization_and_field_ids(ids: suggested_field_ids, org: repo.owner)
              .select { |field| field.viewable_by?(viewer: current_user, repository_id: repo.id) }
              .index_by(&:id)

            suggested_field_values.each do |field_value|
              field_id = field_value["field_id"]
              issue_field = suggested_fields_by_id[field_id] if field_id.is_a?(Integer)
              if issue_field.nil?
                deliver_error! 422,
                  errors: [api_error(:Issue, :issue_field_values, :invalid, value: field_value)],
                  documentation_url: @documentation_url
              end

              # Validate the suggested value matches the field's data_type so we
              # don't persist garbage that will only fail at apply time. Delegates
              # to the domain validations on IssueFieldValue so the rules stay in
              # sync with what `update` will accept later.
              value = field_value["value"]
              if (validation_error = validate_field_value_input(issue_field, value))
                deliver_error! 422, message: validation_error
              end

              if intent_migration_enabled
                # Skip silently when the field already has this value.
                existing_value = current_field_values_by_field_id[field_id]
                next if existing_value && field_value_matches_input?(existing_value, T.must(issue_field), value)

                Issues::UpdateIntent.create_or_supersede(
                  issue_id: issue.id,
                  repository_id: repo.id,
                  action: "set_field",
                  actor_id: current_user.id,
                  rationale: field_value["rationale"],
                  target_id: T.must(field_id),
                  target_value: value&.to_json,
                  confidence: confidence_persist_enabled ? confidence_level(field_value["confidence"]) : nil,
                )
              else
                begin
                  Issues::PendingFieldSuggestion.create(
                    repository_id: repo.id,
                    issue_id: issue.id,
                    issue_field_id: T.must(field_id),
                    value: value,
                    rationale: field_value["rationale"] || "",
                    actor_id: current_user.id,
                    confidence: confidence_persist_enabled ? confidence_level(field_value["confidence"]) : nil,
                  )
                rescue Issues::PendingFieldSuggestion::LimitExceeded,
                       Issues::PendingFieldSuggestion::DuplicateSuggestion => suggestion_error
                  deliver_error! 422,
                    errors: [api_error(:Issue, :issue_field_values, :unprocessable, message: suggestion_error.message)],
                    documentation_url: @documentation_url
                end
              end
            end
          end

          # Preserve existing "set" semantics for the applied field values.
          # Suggested values are tracked separately as pending suggestions and
          # must NOT influence what ends up on the issue — the presence of a
          # suggestion shouldn't change the semantics for the applied values.
          # Suggestion-only payloads skip the set so existing values aren't wiped.
          suggestion_only_field_payload = suggested_field_values.any? && applied_field_values.empty?
          unless suggestion_only_field_payload
            current_issue_field_ids = current_field_values_by_field_id.keys.compact
            update_attributes = get_issue_field_update_attributes(current_issue_field_ids, applied_field_values, "set")
            if update_attributes.any?
              issue_attributes = Issues::UpdateIssueAttributes.new(issue_fields: update_attributes)
              result = Issues.domain.update(issue, issue_attributes, current_user)

              if result.is_a?(GH::Result::Error)
                deliver_error! 422, message: "Failed to update issue field values: #{result.message}"
              end
            end
          end
        end
        data.delete(ISSUE_FIELD_VALUES)
      end

      if changeset_active?(:remove_singular_assignee_from_issues_and_pull_requests)
        assignee_keys = [ASSIGNEES].select { |key| data.key?(key) }
      else
        assignee_keys = [ASSIGNEE, ASSIGNEES].select { |key| data.key?(key) }
        if assignee_keys.length == 2
          deliver_error! 422, message: "You cannot pass both `assignee` and `assignees`. Only one may be provided."
        end
      end

      assignee_data = {}
      update_issue_orchestration = T.let(nil, T.nilable(IssueOrchestration))
      copilot_context = T.let(nil, T.nilable(IssueOrchestration::CopilotContext))

      if assignee_keys.present?
        # Store previous assignee IDs before updating (needed for eyes emoji cleanup)
        previous_assignee_ids = issue.assignees.map(&:id)

        assignees = prepare_assignees(repo: repo, assignee_keys: assignee_keys,
          data: data, documentation_url: @documentation_url, author: issue.user, issue: issue)
        assignee_ids = assignees.map(&:id)
        assignee_data[:user_assignee_ids] = assignee_ids
        data["user_assignee_ids"] = assignee_ids

        # GitHub App installation tokens cannot assign bots/agents.
        validate_rest_api_agent_assignment_allowed_by_token! if bot_assigned?(assignees)

        # Check if Copilot bot is being assigned
        copilot_assigned = copilot_assigned?(assignees)

        # Check if Copilot was previously assigned
        copilot_previously_assigned = copilot_assigned?(issue.assignees)

        # Only handle agent_assignment if Copilot is newly being assigned (not already assigned)
        if copilot_assigned && !copilot_previously_assigned
          # When Copilot is assigned but feature flag is disabled, reject the assignment
          if !copilot_assignment_rest_api_support_enabled?
            deliver_copilot_assignment_not_allowed_error!
          else
            copilot_context = process_copilot_agent_assignment(data, repo)
          end
        end
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

      label_rationale_names = T.let({}, T::Hash[String, String])
      label_suggested_names = T.let(Set.new, T::Set[String])
      label_suggest_rationale_names = T.let({}, T::Hash[String, String])
      label_confidence_levels = T.let({}, T::Hash[String, T.nilable(Issues::ConfidenceThreshold::Level)])
      if data["labels"]
        raw_labels = Array(data["labels"])

        label_names = raw_labels.map do |label_input|
          if label_input.is_a?(Hash)
            name = label_input["name"]
            if label_input["rationale"].present?
              label_rationale_names[name.to_s.downcase] = label_input["rationale"]
            end
            label_confidence_levels[name.to_s.downcase] = confidence_level(label_input["confidence"])
            if suggestion_flag_enabled && !!label_input["suggest"]
              label_suggested_names << name.to_s.downcase
              label_suggest_rationale_names[name.to_s.downcase] = label_input["rationale"].to_s
            end
            name
          else
            label_input
          end
        end

        if current_user.feature_flag_enabled_or_raise?(:issues_rest_api_verify_label_permissions) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          labels = labels_for(repo, label_names, current_user, issue)
        else
          labels = labels_for(repo, label_names)
        end

        suggested_labels, applied_labels = (labels || []).partition do |label|
          label_level = label_confidence_levels[label.name.downcase]
          label_suggested_names.include?(label.name.downcase) || (
            repo_threshold && label_level && label_level.score < repo_threshold
          )
        end

        suggested_labels.each do |label|
          if intent_migration_enabled
            # Skip silently when the label is already applied.
            next if issue.labels.exists?(id: label.id)

            Issues::UpdateIntent.create_or_supersede(
              issue_id: issue.id,
              repository_id: repo.id,
              action: "set_labels",
              actor_id: current_user.id,
              rationale: label_suggest_rationale_names[label.name.downcase] || label_rationale_names[label.name.downcase],
              target_id: T.must(label.id),
              confidence: confidence_persist_enabled ? label_confidence_levels[label.name.downcase] : nil,
            )
          else
            begin
              Issues::PendingLabelSuggestion.create(
                repository_id: repo.id,
                issue_id: issue.id,
                label_id: T.must(label.id),
                rationale: label_suggest_rationale_names[label.name.downcase] || label_rationale_names[label.name.downcase] || "",
                actor_id: current_user.id,
                confidence: confidence_persist_enabled ? label_confidence_levels[label.name.downcase] : nil,
              )
            rescue Issues::PendingLabelSuggestion::LimitExceeded,
                   Issues::PendingLabelSuggestion::DuplicateSuggestion => suggestion_error
              deliver_error! 422,
                errors: [api_error(:Issue, :labels, :unprocessable, message: suggestion_error.message)],
                documentation_url: @documentation_url
            end
          end
        end

        # Preserve existing "replace" semantics for the applied labels. Suggested
        # labels are tracked separately as pending suggestions and must NOT
        # influence what ends up on the issue — `labels: [A, B(suggest)]` should
        # leave the issue with exactly `[A]`, same as `labels: [A]` would.
        # Suggestion-only payloads set `labels = nil` so the later
        # `replace_labels(labels) unless labels.nil?` is skipped, avoiding
        # wiping existing labels.
        suggestion_only_labels_payload = suggested_labels.any? && applied_labels.empty?
        if suggestion_only_labels_payload
          labels = nil
        else
          labels = applied_labels
          data["label_ids"] = applied_labels.map(&:id)
        end

        # Now that we have resolved label objects, populate intents with label IDs
        # for labels being applied (not suggested — suggestion intents live with
        # the pending suggestion itself).
        if label_rationale_names.present? && applied_labels.present?
          applied_labels.each do |label|
            text = label_rationale_names[label.name.downcase]
            if text.present?
              intents[[Issues::EventAnnotation::KIND_LABEL, label.id]] = Issues::EventAnnotation::Intent.new(
                rationale: text,
                confidence: label_confidence_levels[label.name.downcase],
              )
            end
          end
        end
      end

      if integration_user_request?
        issue.modifying_integration = current_integration
        data["integration_id"] = current_integration.id
      end

      if data.key?("state_reason")
        data.delete("state_reason") if data["state_reason"] == "completed"
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

        # TODO consider removing this retry, since it may not be safe
        # See https://thehub.github.com/epd/engineering/products-and-services/dotcom/deadlocked-transactions/
        IssueOrchestration.retry_on_deadlock(max_retry_count: 3, backoff: 0.1) do
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
              update_issue_orchestration = IssueOrchestration.update_issue!(
                actor: current_user,
                issue: issue,
                copilot_context: copilot_context
              )
              update_issue_orchestration.data[:assignee_data] = assignee_data
              # Store previous assignee IDs for eyes emoji cleanup when assignees change
              update_issue_orchestration.data[:previous_assignee_ids] = previous_assignee_ids if defined?(previous_assignee_ids) && previous_assignee_ids
            end
          end
        end

        if saved
          issue.instrument_hydro_update_event(
            previous_title: previous_title,
            previous_body: previous_body,
          )
          issue.replace_labels(labels) unless labels.nil? # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)

          update_issue_orchestration.execute! if update_issue_orchestration

          store_rationale_annotations( # domain-isolation-query-violation:ignore:packages/issues (INSERT)
            issue: issue,
            repo: repo,
            actor: current_user,
            intents: intents,
          )
        else
          errors = issue.errors
        end
      rescue GitHub::Prioritizable::Context::LockedForRebalance
        deliver_error! 503,
          message: MILESTONE_LOCKED_FOR_REBALANCE,
          documentation_url: @documentation_url
      end

      if saved
        options = Api::SerializerOptions.fill(default_options)
        IssuePrefiller.optimized_prefill([issue], repository: repo, current_user: current_user, mime_param: mime_param(options))
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
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters) do
      repo = current_repo
      issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok

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

      check_database_resource_update_rate_limit!(resource: issue, repo: repo, current_user: current_user)

      data = receive_with_schema("issue-lock", "close-legacy")
      lock_reason = data["lock_reason"]

      input_variables = {
        "issueId"          => issue.global_relay_id,
        "clientMutationId" => request_id,
        "enterprise"       => GitHub.enterprise?,
      }
      input_variables["lockReason"] = Platform::Enums::Base.convert_string_to_enum_value(lock_reason) if lock_reason.present?

      # Intentionally omitting enforce_conditional_access_via_graphql: true:
      # control_access :lock_issue above already enforces CAP for the user
      # against the resource, so passing it here would be redundant.
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
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters) do
      repo = current_repo
      issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok

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

      # Intentionally omitting enforce_conditional_access_via_graphql: true:
      # control_access :unlock_issue above already enforces CAP for the user
      # against the resource, so passing it here would be redundant.
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
    replica_clusters = T.let([ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::Collab, ApplicationRecord::IamAbilities], T::Array[T.class_of(ApplicationRecord::Base)])
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters, current_user: current_user, feature_flag: :issues_rest_gets_replica_reads) do
      control_access :list_assignees,
        repo: current_repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      assignees = paginate_rel(get_assignees)
      deliver :user_hash, assignees
    end
  end

  get "/repositories/:repository_id/assignees/:username", operation_id: "issues/check-user-can-be-assigned" do
    replica_clusters = T.let([ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::Collab, ApplicationRecord::IamAbilities], T::Array[T.class_of(ApplicationRecord::Base)])
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters, current_user: current_user, feature_flag: :issues_rest_gets_replica_reads) do
      control_access :list_assignees, repo: current_repo, allow_integrations: true, allow_user_via_granular_actor: true
      assignees = get_assignees

      if assignees.pluck(:display_login).include?(params[:username])
        deliver_empty(status: 204)
      else
        deliver_error 404
      end
    end
  end

  def resolve_tenant_from_user
    return unless current_user.present?
    Business.find_by(id: current_user.business_id)
  end

  # Get issues and/or pull requests semantically similar to a specific issue
  get "/repositories/:repository_id/issues/:issue_number/semantically_similar", operation_id: "issues/search-semantically-similar" do
    # Don't reveal the endpoint exists until we verify the feature flag
    @documentation_url = :internal
    repo = current_repo

    deliver_error!(404) if !is_similar_issues_api_enabled_for?(actor: current_user)

    # Feature flag is enabled, restore normal documentation URL from operation
    @documentation_url = build_documentation_url(@operation)

    issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok
    return handle_issue_not_found unless issue

    control_access :list_issues,
      resource: issue,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_issues_enabled_or_pr!(repo, issue)
    deliver_error!(404) unless issue_visible_to_user?(issue)

    set_context_controller_action(issue, "search-semantically-similar")

    # Global kill switch: return 503 when semantic is unavailable
    unless Issues::SemanticSearchEligibility.semantic_available?
      deliver_error!(503, message: "Semantic similarity search is temporarily unavailable")
    end

    target_type = params[:target_types]

    if FeatureFlag.vexi.enabled?(:issues_rest_semantic_search_domain, current_user, default: false)
      result = Issues.domain.semantic_search.similar_to(
        issue: issue,
        current_user: current_user,
        page: (params[:page] || 1).to_i,
        per_page: (params[:per_page] || DEFAULT_SEMANTIC_SIMILAR_ISSUE_LIMIT).to_i,
        threshold: params[:threshold]&.to_f,
        target_type: target_type,
      )

      if result.ok?
        similar_issues = result.unwrap!.map(&:issue)
      else
        error = T.must(result.error)
        case error
        when GH::Result::Error::Forbidden
          deliver_error!(404)
        else
          deliver_error!(422, message: error.message)
        end
      end
    else
      if target_type && !Search::Queries::SemanticSimilarIssueQuery::VALID_TARGET_TYPES.include?(target_type)
        deliver_error!(422, message: "Invalid target_types '#{target_type}'. Must be one of: #{Search::Queries::SemanticSimilarIssueQuery::VALID_TARGET_TYPES.join(', ')}")
      end

      # Use semantic search to find similar issues and/or pull requests
      similar_issue_results = Search::Queries::SemanticSimilarIssueQuery.find_similar_to(
        issue:,
        current_user:,
        page: (params[:page] || 1).to_i,
        per_page: (params[:per_page] || DEFAULT_SEMANTIC_SIMILAR_ISSUE_LIMIT).to_i,
        threshold: params[:threshold]&.to_f,
        target_type: target_type
      )

      # Extract issues from results (query returns SimilarIssueResult structs but REST API only exposes issues)
      similar_issues = similar_issue_results.map(&:issue)
    end

    options = Api::SerializerOptions.fill(default_options)

    prefill_for_multiple_issues(similar_issues, options: options)

    GitHub.dogstats.distribution_time "api.deliver", tags: ["action:semantically_similar_issues"] do
      deliver :issue_hash, similar_issues, repositories: true
    end
  end

  private

  # Stores rationale annotations for type, label, and field changes.
  # - Types & fields: stored as pending (consumed by async Hydro jobs).
  # - Labels: attached directly to the just-created IssueEvent (synchronous).
  #
  # intents is a Hash keyed by [kind, target_id] => Issues::EventAnnotation::Intent.
  def store_rationale_annotations(issue:, repo:, actor:, intents:)
    return if intents.empty?
    return unless FeatureFlag.vexi.enabled?(:update_issue_rationale, actor, repo.owner, repo, default: false)

    confidence_flag_enabled = FeatureFlag.vexi.enabled?(:update_issue_confidence, actor, repo.owner, repo, default: false)
    intents.each do |(kind, target_id), annotation|
      rationale_text = annotation.rationale
      confidence = confidence_flag_enabled ? annotation.confidence : nil
      begin
        log_data = {
          "code.namespace" => "Api::Issues",
          "repository_id" => repo.id,
          "issue_id" => issue.id,
          "owner_id" => repo.owner_id,
          "user_id" => actor.id,
          "kind" => kind,
          "target_id" => target_id,
          "has_rationale" => rationale_text.present?,
          "rationale_length" => rationale_text.present? ? rationale_text.length : 0,
          "confidence" => confidence&.serialize,
        }
        if FeatureFlag.vexi.enabled?(:update_issue_rationale_log, actor, repo.owner, repo, default: false)
          log_data["rationale"] = rationale_text
        end
        GitHub.logger.info("issues.update.rationale_annotation", log_data)

        case kind
        when Issues::EventAnnotation::KIND_LABEL
          # Labels create events synchronously — attach directly to the existing event.
          # NOTE(spike): This query has a small race window if the same user labels the same
          # issue concurrently, and incurs an extra DB round-trip. In a production
          # implementation we'd return created events from replace_labels and use them
          # directly, avoiding both issues.
          label_event = issue.events
            .joins(:issue_event_detail)
            .where(event: "labeled", actor_id: actor.id, issue_event_details: { label_id: target_id })
            .order(id: :desc).first
          next unless label_event

          Issues::EventAnnotation.create(
            repository_id: repo.id,
            issue_id: issue.id,
            issue_event_id: label_event.id,
            rationale: rationale_text,
            actor_id: actor.id,
            confidence: confidence,
            action: Issues::EventAnnotation::KIND_LABEL,
          )
        else
          # Types and fields create events asynchronously via Hydro jobs — store pending.
          Issues::EventAnnotation.store_pending(
            repository_id: repo.id,
            issue_id: issue.id,
            kind: kind,
            target_id: target_id,
            rationale: rationale_text,
            actor_id: actor.id,
            confidence: confidence,
          )
        end
      rescue => e
        GitHub.logger.error("issues.update.rationale_store_failed", {
          "code.namespace" => "Api::Issues",
          "issue_id" => issue.id,
          "repository_id" => repo.id,
          "kind" => kind,
          "target_id" => target_id,
          "error" => e.message,
        })
      end
    end
  end

  # Parses a confidence level string ("low", "medium", "high") into a Level enum.
  # Returns nil if the value is not a recognized level.
  sig { params(value: T.untyped).returns(T.nilable(Issues::ConfidenceThreshold::Level)) }
  def confidence_level(value)
    Issues::ConfidenceThreshold::Level.try_parse(value)
  end

  # Filters update keys to only include fields the FGP user has permission to modify.
  # FGP (fine-grained permission) users have limited access and can only modify specific fields.
  #
  # - issue: The issue being updated
  # - user: The current user making the request
  #
  # Returns a Hash containing only the fields the user has permission to modify
  def filter_keys_for_fgp_user(issue, user)
    can_change_state = (issue.open? && issue.closable_by?(user)) ||
                       (issue.closed? && issue.reopenable_by?(user))
    can_set_milestone = issue.can_set_milestone?(user)

    allowed_fields = []
    allowed_fields += [STATE, STATE_REASON] if can_change_state
    allowed_fields << MILESTONE if can_set_milestone

    allowed_fields
  end

  # Check if the current user can edit the content (title/body) of an issue.
  # This requires either being the author or having write access.
  #
  # - issue: The issue being updated
  # - repo: The repository containing the issue
  #
  # Returns true if the user can edit content, false otherwise
  def can_edit_content?(issue, repo)
    issue.user_id == current_user&.id ||
      access_allowed?(:edit_issue, resource: issue, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true, enforce_oauth_app_policy: repo.private?)
  end

  # Resolves the actor for the current request, it can be a bot, a user, an fgp, installation etc.
  #
  # returns Actor
  def resolve_actor(repo)
    if current_integration_installation.present?
      current_integration_installation.bot
    elsif current_integration.present?
      current_integration.installations.not_suspended.with_repository(repo).first&.bot
    elsif current_user.programmatic_access.present?
      grant = current_user.programmatic_access.grant
      grant.bot || Platform::Loaders::BotByUserProgrammaticAccessGrant.load(grant).sync
    else
      current_user
    end
  end

  # Validates and returns a value if it passes the validation, else returns a validation error
  # - value      - The value to pass to the validation block
  # - error_sym  - The key to assoicate the validation error against if it fails
  #
  # returns result (value post validation)
  #
  sig do
    params(value: T.untyped, error_sym: T.any(Symbol, String), block: T.proc.params(value: T.untyped).returns(T.untyped))
    .returns(T.untyped)
  end
  def find_or_error!(value, error_sym, &block)
    result = yield(value)
    if value && result.nil?
      deliver_error! 422,
        errors: [api_error(:Issue, error_sym.to_sym, :invalid, value: value)],
        documentation_url: @documentation_url
    end
    result
  end

  def ensure_issue_visible!(repo, issue)
    ensure_repo_writable!(repo)
    ensure_issues_enabled_or_pr!(repo, issue)
    deliver_error!(404) unless issue_visible_to_user?(issue)
  end

  def issue_visible_to_user?(issue)
    issue.present? && !issue.hide_from_user?(current_user)
  end

  def is_similar_issues_api_enabled_for?(actor: nil)
    Issues::SemanticSearchEligibility.can_search_issues_index?(
      user: actor,
    )
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

  def issue_type_filter(repo, query, text)
    case text
    when Search::Filter::WILDCARD, Search::Filter::ANY
      query << [:has, "type"]
    when Search::Filter::NONE
      query << [:no, "type"]
    when Array, Hash
      deliver_error! 422,
        errors: [api_error(:Issue, :type, :invalid, value: text)],
        documentation_url: "/v3/issues/#list-issues"
    else
      issue_type = deliver_error_or_get_issue_type(repo.owner, text, "/v3/issues/#list-issues", repo)
      query << [:issue_type, issue_type.name]
    end
  end

  # Maximum number of issue field value filters accepted per request.
  # Repos generally have only a handful of issue fields; this guards
  # against amplified DB/ES lookups from oversized or repeated filters.
  MAX_ISSUE_FIELD_VALUE_FILTERS = 20

  # Filters the issue query by issue field values.
  #
  # repo         - The Repository whose issues we're filtering.
  # query        - The query components Array to pass on to Issue::EsSearch.
  # param_string - The String param from the client in "slug:value,slug:value" format.
  #
  # Returns a modified `query` object.
  def issue_field_values_filter(repo, query, param_string)
    pairs = param_string.to_s.split(",").map(&:strip).reject(&:empty?).uniq

    if pairs.size > MAX_ISSUE_FIELD_VALUE_FILTERS
      deliver_error! 422,
        errors: [api_error(:Issue, :issue_field_values, :invalid, message: "must contain no more than #{MAX_ISSUE_FIELD_VALUE_FILTERS} field filters")],
        documentation_url: "/v3/issues/#list-issues"
    end

    values_by_slug = {}

    pairs.each do |pair|
      slug, value = pair.split(":", 2)
      slug = slug.to_s.strip
      value = value.to_s.strip

      if slug.blank? || value.blank?
        deliver_error! 422,
          errors: [api_error(:Issue, :issue_field_values, :invalid, value: pair)],
          documentation_url: "/v3/issues/#list-issues"
      end

      field = Issues::Domain::IssueFields.issue_field_by_name_slug_and_repo_owner(slug, repo)

      if field.nil? || !field.viewable_by?(viewer: current_user)
        deliver_error! 422,
          errors: [api_error(:Issue, :issue_field_values, :invalid, value: pair)],
          documentation_url: "/v3/issues/#list-issues"
      end

      (values_by_slug[slug] ||= []) << value
    end

    # Group values by slug so repeating the same slug ORs the values within
    # that field, while distinct slugs continue to AND across fields.
    values_by_slug.each do |slug, values|
      query << [:"field.#{slug}", values.size == 1 ? values.first : values]
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

  # Returns true when the update-issue request body carries any rationale text
  # or `suggest:true` markers — i.e. when handling the request would persist
  # AI-generated suggestion content into `Pending*Suggestion`,
  # `Issues::UpdateIntent`, or `Issues::EventAnnotation` records.
  #
  # Used to gate the spammy-actor check so it only fires for the suggestion
  # path and does not change behavior for plain field/label/type updates.
  def request_includes_suggestions_or_rationale?(data)
    suggestion_shaped = lambda do |entry|
      entry.is_a?(Hash) && (entry["rationale"].present? || entry["suggest"])
    end

    return true if suggestion_shaped.call(data[ISSUE_TYPE])

    field_values = data[ISSUE_FIELD_VALUES]
    return true if field_values.is_a?(Array) && field_values.any?(&suggestion_shaped)

    labels = data["labels"]
    return true if labels.is_a?(Array) && labels.any?(&suggestion_shaped)

    false
  end

  # Refuses suggestion/rationale writes originating from accounts flagged as
  # spammy. Mirrors the protection that `Spam::Spammable#set_user_hidden`
  # gives to regular issue and comment writes, but applied as a hard guard
  # because the suggestion/rationale records (`Pending*Suggestion`,
  # `Issues::UpdateIntent`, `Issues::EventAnnotation`) do not include
  # `Spammable` — their `user_hidden` column is never set and they would
  # otherwise be visible regardless of the actor's spam status.
  #
  # Blocks the directly authenticated user (PAT/OAuth), the case where the
  # request comes from a GitHub App installation operating on a flagged
  # account's repository (where `current_user` is the installation bot, not
  # the flagged underlying account), and the case where the App itself is
  # owned by a flagged account (different from the repo owner).
  def ensure_actor_not_flagged_for_suggestions!(repo)
    return unless GitHub.spamminess_check_enabled?

    reason = if current_user&.spammy?
      "current_user"
    elsif repo.owner&.spammy?
      "repo_owner"
    elsif current_integration&.owner&.spammy?
      "app_owner"
    end

    return unless reason

    GitHub.dogstats.increment(
      "issues.suggestions.spammy_actor_blocked",
      tags: ["reason:#{reason}"],
    )

    deliver_error! 403,
      message: "Suggestions and rationale are disabled for accounts that have been flagged.",
      documentation_url: @documentation_url
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
      potential_logins = assignee_logins.map { |login| login.to_s.downcase }

      # When Copilot REST API support is enabled, handle bot assignees
      if copilot_assignment_rest_api_support_enabled?
        # Separate bot logins from regular user logins.
        bot_logins, user_logins = potential_logins.partition { |login| login.ends_with?(Bot::LOGIN_SUFFIX) }

        regular_users = user_logins.any? ? User.with_logins(user_logins) : []
        regular_users_by_login = regular_users.index_by { |u| u.display_login.downcase }

        bots = bot_logins.any? ? Bot.with_slugs(bot_logins).to_a : []
        bots_by_login = bots.index_by { |b| "#{b.slug}#{Bot::LOGIN_SUFFIX}".downcase }

        # Combine all users and bots
        all_users_by_login = regular_users_by_login.merge(bots_by_login)
      else
        all_users_by_login = User.with_logins(assignee_logins).index_by(&:display_login).transform_keys(&:downcase)
      end

      assignee_logins.each do |login|
        user = all_users_by_login[login.downcase]
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
    # Allow assignable bots (like Copilot SWE Agent) if they have the :is_assignable capability
    # Only check bot capability when Copilot REST API support is enabled
    if copilot_assignment_rest_api_support_enabled?
      if user.is_a?(Bot) && user.integration.present?
        return true if Apps::Privileged.capable?(:is_assignable, app: user.integration)
      end
    end

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
