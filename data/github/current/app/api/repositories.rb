# typed: true
# frozen_string_literal: true

require "cache_key_logging_denylist"
require "json"
require "set"

class Api::Repositories < Api::App
  include ReceiveSchemaWithOpenApi
  include SecurityAnalysisSettingsHelper

  include Api::App::DiffContentsDependency
  include Repositories::Domain::Provider

  USER_REPOS_TTL = 1.minute.freeze
  ALLOWED_AFFILIATIONS = %w[
    owner
    collaborator
    organization_member
  ].freeze

  ALLOWED_VISIBILITIES = [
    "all",
    Repository::PUBLIC_VISIBILITY,
    Repository::PRIVATE_VISIBILITY,
  ].freeze

  DEFAULT_AFFILIATION_STRING = ALLOWED_AFFILIATIONS.join(",").freeze

  ORG_ADMIN_ROLE = :"org-admin"
  ORG_SECURITY_MANAGER_ROLE = :"org-security-manager"
  ORG_MEMBER_ROLE = :"org-member"

  map_to_service :teams, only: [ # rubocop:todo GitHub/MapToService
    "GET /repositories/:repository_id/teams"
  ]

  # List repositories for the authenticated user.
  get "/user/repos", operation_id: "repos/list-for-authenticated-user" do
    control_access :list_repos,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    if params["type"] && (params["visibility"] || params["affiliation"])
      deliver_error!(422,
        message: "If you specify visibility or affiliation, you cannot specify type.",
        documentation_url: "/rest/reference/repos#list-repositories-for-the-authenticated-user",
      )
    end

    default_sort = :full_name
    type = params.delete("type")
    metric_type = type
    legacy = true

    case type
    when "all"
      params["affiliation"] = DEFAULT_AFFILIATION_STRING
      params["visibility"]  = "all"
    when "owner"
      default_sort = :name
      params["affiliation"] = "owner"
      params["visibility"]  = "all"
    when Repository::PUBLIC_VISIBILITY
      params["affiliation"] = DEFAULT_AFFILIATION_STRING
      params["visibility"]  = Repository::PUBLIC_VISIBILITY
    when Repository::PRIVATE_VISIBILITY
      default_sort = :name
      params["affiliation"] = DEFAULT_AFFILIATION_STRING
      params["visibility"]  = Repository::PRIVATE_VISIBILITY
    when "member"
      params["affiliation"] = "collaborator"
      params["visibility"]  = "all"
    else
      metric_type = "other"
      legacy = false
      params["affiliation"] ||= DEFAULT_AFFILIATION_STRING
    end

    visibility = params["visibility"] || "all"
    visibility = "all" unless ALLOWED_VISIBILITIES.include?(visibility)

    affiliation = ALLOWED_AFFILIATIONS & params["affiliation"].split(",").map(&:strip)

    GitHub.dogstats.time "user", tags: ["action:#{legacy ? "legacy_repos" : "user_repos"}", "type:#{metric_type}"] do
      # Build a cache keyed by:
      #   * Namespace
      #   * User ID
      #   * token used for auth, can affect output by org safelisting
      #   * when user has performed writes to expire when creating/deleting
      #   * combination of visibility and affiliation specified in request
      #   * current_integration_id (can change results)
      #   * unauthorized_org_ids (ditto)
      #   * the attribute used for sorting
      #   * the direction of the sort
      unauthorized_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations)
      unauthorized_sso_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)

      cache_key = [
        CacheKeyLoggingDenylist::API_REPOS_PREFIX,
        current_user.id,
        current_user.try(:oauth_access).try(:id),
        last_write_timestamp_for_current_user,
        affiliation.join(","),
        visibility,
        (current_integration&.id || "0"),
        unauthorized_org_ids.sort.join(","),
        (current_user_programmatic_access&.id || "0"),
        params[:sort],
        params[:direction],
      ].join(":")

      repo_ids = GitHub.cache.fetch(cache_key, ttl: USER_REPOS_TTL, stats_key: "api.cache.user-repos.#{metric_type}") do
        include_org_owned_repos = access_allowed?(:list_associated_public_org_owned_repos,
                                                 resource: current_user,
                                                 allow_integrations: false,
                                                 allow_user_via_granular_actor: true)

        including = []
        including << :owned    if affiliation.include?("owner")
        including << :direct   if affiliation.include?("collaborator")
        including << :indirect if affiliation.include?("organization_member") && include_org_owned_repos

        # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
        associated_repository_ids = current_user.associated_repository_ids(including: including, include_indirect_forks: false)
        # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
        scope = Repository.active.where(ActiveRecord::Base.sanitize_sql(["repositories.id IN (?)", associated_repository_ids]))

        if include_org_owned_repos
          if unauthorized_org_ids.any?
            set_sso_partial_results_header(unauthorized_sso_org_ids) if unauthorized_sso_org_ids.any?
            scope = scope.where("repositories.organization_id NOT IN (?) OR repositories.organization_id IS NULL", unauthorized_org_ids)
          end
        else
          scope = scope.user_owned
        end

        if ProgrammaticActor::RepositoryFilter.applicable?(current_user)
          if visibility == Repository::PUBLIC_VISIBILITY
            scope = scope.public_scope
          elsif visibility == "all" || visibility == Repository::PRIVATE_VISIBILITY
            accessible_repo_ids = ProgrammaticActor::RepositoryFilter.perform(
              actor: current_user, repository_ids: scope.private_scope.pluck(:id)
            )

            scope = if visibility == "all"
              scope.where(ActiveRecord::Base.sanitize_sql(["public is true or id IN (?)", accessible_repo_ids]))
            else
              scope.private_scope.where(id: accessible_repo_ids)
            end
          else
            deliver_error! 422, message: "Invalid visibility specified."
          end
        else
          if visibility == Repository::PRIVATE_VISIBILITY
            scope = scope.private_scope
          elsif visibility == Repository::PUBLIC_VISIBILITY
            scope = scope.public_scope
          end

          scope = scope.public_scope unless access_allowed?(:list_private_repos, resource: current_user, allow_integrations: false, allow_user_via_granular_actor: false)
        end

        filter_and_sort(scope, default_sort).pluck(:id)
      end

      repos = repo_ids.paginate(pagination)

      repo_records = Repository.active.where(id: repos).index_by(&:id)
      repos.replace(repos.map { |id| repo_records[id] }.compact)

      # prefill most_capable_user_role_for_actor to prevent querying roles for each repo when serializing
      GitHub::PrefillAssociations.prefill_batch_method(repos, :most_capable_user_role_for_actor, current_user)

      Repository.prefill_associations(repos, internal: true)

      prefill_repository_reference_keys(repos)

      deliver :repository_hash, repos
    end
  end

  # List public repositories for a user.
  get "/user/:user_id/repos", operation_id: "repos/list-for-user" do
    user = find_user!
    control_access :list_public_repos,
                   resource: Platform::PublicResource.new(resource: user),
                   enforce_oauth_app_policy: false,
                   allow_integrations: true,
                   allow_user_via_granular_actor: true

    default_sort = T.let(nil, T.nilable(Symbol))
    type = params[:type] || "owner"

    metric_type = type
    metric_type = "other" unless %w(all member owner).include?(metric_type)

    GitHub.dogstats.time "user", tags: ["via:api", "action:repos", "type:#{metric_type}"] do
      scope = case type
      when /all/i
        Repository.active.where({
          id: user.associated_repository_ids(including: [:owned, :direct]),
        })
      when /member/i
        user.member_repositories
      when /owner/i
        default_sort = :name
        user.repositories
      end

      scope = if scope
        scope.public_scope
      else
        default_sort = :name
        user.public_repositories
      end

      scope = filter_and_sort(scope, default_sort)

      repos = paginate_rel(scope)

      # prefill most_capable_user_role_for_actor to prevent querying roles for each repo when serializing
      GitHub::PrefillAssociations.prefill_batch_method(repos, :most_capable_user_role_for_actor, current_user) if logged_in?
      Repository.prefill_associations(repos)

      deliver :repository_hash, repos
    end
  end

  # List repositories for an organization.
  get "/organizations/:organization_id/repos", operation_id: "repos/list-for-org" do
    org = find_org!
    type = params[:type] || "all"
    user = current_user || User.new

    metric_type = type
    metric_type = "other" unless %w(all public private internal member fork source).include?(metric_type)

    control_access :apps_audited,
      resource: Platform::PublicResource.new(resource: org),
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: false # we aren't enforcing it here because the filters underneath are.

    programmatic_actor = ProgrammaticActor::RepositoryFilter.applicable?(current_user)

    GitHub.dogstats.time "organization", tags: ["via:api", "action:repos", "type:#{metric_type}", "programmatic_actor:#{programmatic_actor}"] do
      repo_scope = Repository.active
      public_only = false

      unless current_integration.present?
        unless access_allowed?(:list_private_repos, resource: org, allow_integrations: true,
                               allow_user_via_granular_actor: true)
          repo_scope = repo_scope.public_scope
          public_only = true
        end
      end

      repos = case type
      when /public/i
        add_pagination_scopes(org.org_repositories.public_scope.merge(repo_scope))
      when /private/i
        if logged_in? && access_allowed?(:list_private_repos, resource: org, allow_integrations: true, allow_user_via_granular_actor: true)
          repository_ids = ProgrammaticActor::RepositoryFilter.perform(
            actor: current_user,
            target: org,
            repository_ids: Repository.active.owned_by(org).private_not_internal_scope.pluck(:id)
          )

          repository_ids = user.associated_repository_ids(repository_ids: repository_ids)

          add_pagination_scopes(repo_scope.where(id: repository_ids))
        else
          Repository.none
        end
      when /internal/i
        if logged_in? && org.business && current_user.is_business_member?(org.business.id, valid_license: true)
          add_pagination_scopes(org.internal_repositories)
        else
          Repository.none
        end
      when /member/i
        if logged_in? && access_allowed?(:list_member_repositories, resource: org, allow_integrations: true, allow_user_via_granular_actor: true)
          repository_ids = ProgrammaticActor::RepositoryFilter.perform(
            actor: current_user,
            target: org,
            repository_ids: Repository.active.owned_by(org).pluck(:id)
          )

          repository_ids = user.associated_repository_ids(repository_ids: repository_ids)
          add_pagination_scopes(repo_scope.where(id: repository_ids))
        else
          Repository.none
        end
      when /fork/i
        add_pagination_scopes(forked_org_constrained_accessible_repositories(user, org).merge(repo_scope))
      when /source/i
        add_pagination_scopes(source_org_constrained_accessible_repositories(user, org).merge(repo_scope))
      else # default to type 'all'
        all_org_constrained_accessible_repositories(organization: org, user:, public_only:)
      end

      repos_to_prefill = repos.is_a?(GH::Domain::OffsetCollection) ? repos.to_a : repos
      Configurable.preload_configuration(repos_to_prefill)
      # preload internal due to plan_supports in serializer:
      # has_wiki: repo.has_wiki? && repo.plan_supports?(:wikis)
      Repository.prefill_associations(repos_to_prefill, internal: true)
      Repository.preload_repository_permissions(repositories: repos_to_prefill, users: [user])

      prefill_repository_reference_keys(repos)

      options = {
        current_user: user,
      }

      options[:show_repo_security_settings] ||= {}

      start_time = GitHub::Dogstats.monotonic_time
      user_role = get_organization_security_and_analysis_role(org)
      is_org_admin_or_security_manager = [ORG_ADMIN_ROLE, ORG_SECURITY_MANAGER_ROLE].include?(user_role)
      can_access_any_security_settings = T.let(false, T::Boolean)
      repos.each do |repo|
        # Only perform allow_access validation on repos for non admin or security manager users
        can_access_security_settings = is_org_admin_or_security_manager || can_access_security_and_analysis?(repo)
        options[:show_repo_security_settings][repo.id] = can_access_security_settings
        can_access_any_security_settings ||= can_access_security_settings
      end
      GitHub.dogstats.distribution(
        "api.organization.repos.security_manager_access_check.duration",
        GitHub::Dogstats.duration(start_time),
        tags: ["type:#{metric_type}", "programmatic_actor:#{programmatic_actor}", "role:#{user_role}"]
      )
      # We only want to emit security manager metrics for an org once. Given that if a user is a security manager
      # that permission will apply to all repos, we can check against a single repo in the org to see what type of
      # user is making the request.
      emit_security_and_analysis_role(org, org_level_endpoint: true, role: user_role) if can_access_any_security_settings

      deliver :repository_hash, repos, options
    end
  end

  # get a single repository
  get "/repositories/:repository_id", operation_id: "repos/get", temporarily_exempt_from_tenant_context_requirement: "2024-04-01" do
    @accepted_scopes = %w(repo)

    repo = find_repo!
    # this is a data quality issue,
    # see https://github.com/github/github/issues/192475
    if repo.owner.nil?
      deliver_error!(404)
    end

    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    Repository.prefill_associations([repo])

    last_modified = calc_last_modified_for_object(repo)


    generate_temp_clone_token = access_allowed?(
      :get_temp_clone_token,
      resource: repo,
      current_repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: false
    )

    show_security_settings = can_access_security_and_analysis?(repo)
    options = {
      last_modified: last_modified,
      show_merge_settings: access_allowed?(GitHub.flipper[:merge_settings_perms].enabled? ? :view_merge_settings : :push, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
      show_template_repository: access_allowed?(:get_repo, resource: repo.template_repository, allow_integrations: true, allow_user_via_granular_actor: true),
      generate_temp_clone_token: generate_temp_clone_token,
      show_security_settings: show_security_settings
    }

    emit_security_and_analysis_role(repo.owner, org_level_endpoint: false) if show_security_settings

    # If generate_temp_clone_token and repo is private `temp_clone_token` will be generated.
    # If repo is public, temp_clone_token will be empty.
    if generate_temp_clone_token && repo.private?
      # Generate etag based on the full repository hash because it has a number of values that can change without updated_at changing
      body = Api::Serializer.serialize(:full_repository_hash, repo, Api::SerializerOptions.fill(options))
      options[:etag] = Digest::SHA256.hexdigest(encode_json(body))

      # Give Sinatra a chance to halt immediately if ETag matches.
      set_caching_headers!({ etag: options[:etag], last_modified: last_modified })
    end

    deliver :full_repository_hash, repo, options
  end

  # create a repository for the authenticated user
  post "/user/repos", operation_id: "repos/create-for-authenticated-user" do
    control_access :create_repo, resource: current_user, challenge: true, allow_integrations: false, allow_user_via_granular_actor: true

    # Introducing strict validation of the repository.create-for-user
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    # TODO: remove skip_validation once a rollout strategy is determined
    data = receive_with_schema("repository", "create-for-user", skip_validation: true, expected_type: Hash)

    # DEPRECATED: In v4, remove support for the public attribute. v4 should
    # *only* support the private attribute.
    if data.key?(Repository::PUBLIC_VISIBILITY) && data.key?(Repository::PRIVATE_VISIBILITY)
      deliver_error! 422, message: "Cannot send public and private attributes. Pick one."
    end

    data.transform_keys!(&:to_sym)

    visibility = if data.fetch(:public) { !data.fetch(:private, false) }
      Repositories::RepositoryVisibility::Public
    else
      Repositories::RepositoryVisibility::Private
    end

    attributes = Repositories::CreateRepositoryAttributes.new(
      # TODO: This is a required field. We need to enable schema validation instead. See https://github.com/github/ecosystem-api/issues/1555
      name: T.unsafe(coerce_string(data[:name])),
      visibility:,
      description: coerce_string(data[:description]),
      homepage: coerce_string(data[:homepage]),
      gitignore_template: coerce_string(data[:gitignore_template]),

      # no need to coerce here as the legacy implementation already 500s on invalid values
      license_template: data[:license_template],
      reflog_data: new_repository_reflog_data(current_user, data, "initial commit api"),
    )

    # coerce these string values into their enumerations
    update_commit_setting(attributes, data, :squash_merge_commit_message, Repositories::SquashCommitMessage)
    update_commit_setting(attributes, data, :squash_merge_commit_title, Repositories::SquashCommitTitle)
    update_commit_setting(attributes, data, :merge_commit_title, Repositories::MergeCommitTitle)
    update_commit_setting(attributes, data, :merge_commit_message, Repositories::MergeCommitMessage)

    # Optionally update these attributes so that we can fall through to the default when they are unspecified.
    update_repo_attributes(attributes, data, :has_issues)
    update_repo_attributes(attributes, data, :has_projects)
    update_repo_attributes(attributes, data, :has_wiki)
    update_repo_attributes(attributes, data, :has_downloads)
    update_repo_attributes(attributes, data, :has_discussions)
    update_repo_attributes(attributes, data, :auto_init)
    update_repo_attributes(attributes, data, :allow_merge_commit)
    update_repo_attributes(attributes, data, :allow_squash_merge)
    update_repo_attributes(attributes, data, :allow_rebase_merge)
    update_repo_attributes(attributes, data, :allow_auto_merge)
    update_repo_attributes(attributes, data, :delete_branch_on_merge)
    update_repo_attributes(attributes, data, :allow_update_branch)
    update_repo_attributes(attributes, data, :use_squash_pr_title_as_default)
    update_repo_attributes(attributes, data, :template, source_key: :is_template)

    authorize_content(:create)

    if attributes.visibility == Repositories::RepositoryVisibility::Private &&
        !access_allowed?(:create_private_repo, resource: current_user, allow_integrations: false, allow_user_via_granular_actor: true)
      deliver_create_private_repo_denied!
    end

    integration_context = build_current_integration_context(target: current_user, entry_point: :rest_api_create_repo_for_authenticated_user)
    result = repositories_domain.create(attributes, integration_context:)

    case result
    when GH::Result::Ok
      deliver :full_repository_hash, result.value, show_merge_settings: true, status: 201
    when GH::Result::Error::Validation
      if result.model.errors[:trade_controls_restricted_owner].present?
        status = changeset_active?(:change_create_repo_trade_compliance_response_status) ? 451 : 422
        deliver_error status,
          message: ::TradeControls::Notices.notice_as_plaintext(:api_access_restricted),
          documentation_url: GitHub.trade_controls_help_url
      elsif result.model.errors[:trade_controls_restricted_creator].present?
        status = changeset_active?(:change_create_repo_trade_compliance_response_status) ? 451 : 422
        deliver_error status,
          message: ::TradeControls::Notices.notice_as_plaintext(:api_access_restricted),
          documentation_url: GitHub.trade_controls_help_url
      else
        deliver_error 422,
          message: result.message,
          errors: result.model.errors,
          documentation_url: @documentation_url
      end
    when GH::Result::Error
      deliver_error 422,
      message: result.message,
      documentation_url: @documentation_url
    end
  end

  # create a repository for :org
  post "/organizations/:organization_id/repos", operation_id: "repos/create-in-org" do
    set_forbidden_message("You need admin access to the organization before adding a repository to it.")

    org = find_org!
    control_access :create_repo_for_org,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Introducing strict validation of the repository.create-for-organization
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("repository", "create-for-organization", skip_validation: true)

    # DEPRECATED: In v4, remove support for the public attribute. v4 should
    # *only* support the private attribute.
    if data.key?(Repository::PUBLIC_VISIBILITY) && data.key?(Repository::PRIVATE_VISIBILITY)
      deliver_error! 422, message: "Cannot send public and private attributes. Pick one."
    end

    attributes = attr(data,
      :name,
      :description,
      :homepage,
      :public,
      :private,
      :has_issues,
      :has_projects,
      :has_wiki,
      :has_downloads,
      :has_discussions,
      :gitignore_template,
      :license_template,
      :auto_init,
    )

    # when :private is set but :public isn't, make :public the inverse of :private
    attributes[:public] = attributes.fetch(:public) { !attributes.fetch(:private, false) }
    attributes.delete(:private)

    creating_public_repo = creating_public_repo?(data)

    if org.emu_creating_public_repo?(creating_public_repo ? Repository::PUBLIC_VISIBILITY : Repository::PRIVATE_VISIBILITY)
      deliver_error! 422, message: "Public repositories are not permitted for Enterprise Managed Organizations."
    end

    if data.has_key?("visibility")
      unless Repository::VISIBILITIES.include? data["visibility"]
        deliver_error! 422, message: "Invalid visibility. Valid visibilities are: #{Repository::VISIBILITIES.join(', ')}"
      end
      # If specified, visibility overrides public/private.
      attributes[:visibility] = data["visibility"]
      attributes.delete(:public)
      attributes.delete(:private)
    end

    if data.has_key?("auto_init")
      attributes["auto_init"] = parse_bool(data["auto_init"])
    end

    if data.has_key?("allow_merge_commit")
      attributes["allow_merge_commit"] = parse_bool(data["allow_merge_commit"])
    end

    if data.has_key?("allow_squash_merge")
      attributes["allow_squash_merge"] = parse_bool(data["allow_squash_merge"])
    end

    if data.has_key?("allow_rebase_merge")
      attributes["allow_rebase_merge"] = parse_bool(data["allow_rebase_merge"])
    end

    if data.has_key?("allow_auto_merge")
      attributes["allow_auto_merge"] = parse_bool(data["allow_auto_merge"])
    end

    if data.has_key?("delete_branch_on_merge")
      attributes["delete_branch_on_merge"] = parse_bool(data["delete_branch_on_merge"])
    end
    if data.has_key?("allow_update_branch")
      attributes["allow_update_branch"] = parse_bool(data["allow_update_branch"])
    end

    if data.has_key?("use_squash_pr_title_as_default")
      attributes["use_squash_pr_title_as_default"] = parse_bool(data["use_squash_pr_title_as_default"])
    end

    if data.has_key?("squash_merge_commit_message")
      attributes["squash_merge_commit_message"] = data["squash_merge_commit_message"]
    end

    if data.has_key?("squash_merge_commit_title")
      attributes["squash_merge_commit_title"] = data["squash_merge_commit_title"]
    end

    if data.has_key?("merge_commit_title")
      attributes["merge_commit_title"] = data["merge_commit_title"]
    end

    if data.has_key?("merge_commit_message")
      attributes["merge_commit_message"] = data["merge_commit_message"]
    end

    set_template_attribute(data, attributes)

    if team_id = data["team_id"]
      team = org.teams.find_by_id(team_id)

      if access_allowed?(:add_team_to_new_repo, resource: team, allow_integrations: true, allow_user_via_granular_actor: true)
        attributes[:team_id] = team_id
      else
        deliver_error! 422,
          message: "You need admin access to the team before adding a repository to it.",
          documentation_url: @documentation_url
      end
    end

    if creating_private_repo?(attributes) &&
      !access_allowed?(:create_private_repo_for_org, resource: org, allow_integrations: true, allow_user_via_granular_actor: true)

      deliver_create_private_repo_denied!
    end

    custom_properties = if data.has_key?("custom_properties")
      case data["custom_properties"]
      when Hash
        data["custom_properties"]
      else
        deliver_error! 422, message: "When provided, custom_properties must be an object", documentation_url: @documentation_url
      end
    end

    # login not used in response therefore safe to use here.
    result = Repository.handle_creation(
      current_user,
      org.login, # rubocop:disable GitHub/DoNotAllowLogin
      attributes,
      new_repository_reflog_data(org, data, "initial commit api"),
      custom_properties: custom_properties,
      current_integration_context: build_current_integration_context(target: org, entry_point: :rest_api_create_repo_for_organization)
    )

    if result.success
      deliver :full_repository_hash, result.repository, show_merge_settings: true, status: 201
    elsif !result.allowed
      deliver_error 403, message: forbidden_message
    elsif result.repository.errors[:trade_controls_restricted_owner].present?
      status = changeset_active?(:change_create_repo_trade_compliance_response_status) ? 451 : 422
      deliver_error status,
        message: ::TradeControls::Notices.notice_as_plaintext(:api_access_restricted),
        documentation_url: GitHub.trade_controls_help_url
    elsif result.repository.errors[:trade_controls_restricted_creator].present?
      status = changeset_active?(:change_create_repo_trade_compliance_response_status) ? 451 : 422
      deliver_error status,
        message: ::TradeControls::Notices.notice_as_plaintext(:api_access_restricted),
        documentation_url: GitHub.trade_controls_help_url
    elsif result.repository.errors[:visibility].present?
      deliver_error 422,
        message: result.repository.errors.full_messages.to_sentence,
        documentation_url: "https://github.com/pricing"
    else
      deliver_error 422,
        message: result.error_message,
        errors: result.repository.errors,
        documentation_url: @documentation_url
    end
  end

  # Clone a template repository to start a new repository
  post "/repositories/:template_repository_id/generate", operation_id: "repos/create-using-template" do
    repo = find_template_repo!

    control_access :get_repo,
      resource: repo,
      enforce_oauth_app_policy: repo.private?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_schema("repository", "generate-from-template")
    attributes = attr(data, :owner, :name, :description, :private, :include_all_branches)

    creating_public_repo = creating_public_repo?(data)

    owner = current_user
    owner = User.find_by_login(attributes[:owner]) if attributes[:owner]

    unless owner
      deliver_error! 404, message: "Invalid owner", documentation_url: @documentation_url
    end

    if owner.bot?
      deliver_error! 422, message: "Invalid owner. Owner must be a user or organization.", documentation_url: @documentation_url
    elsif owner.user?
      if owner.emu_creating_public_repo?(creating_public_repo ? Repository::PUBLIC_VISIBILITY : Repository::PRIVATE_VISIBILITY)
        deliver_error! 422, message: "Public repositories are not permitted for Enterprise Managed Users."
      end

      control_access :create_repo_from_template, resource: owner, challenge: true, allow_integrations: true,
      allow_user_via_granular_actor: true

      if creating_private_repo?(data) &&
        !access_allowed?(:create_private_repo_from_template,
                         resource: owner,
                         allow_integrations: true,
                         allow_user_via_granular_actor: true)

        deliver_create_private_repo_denied!
      end

      authorize_content(:create)
    elsif owner.organization?
      if owner.emu_creating_public_repo?(creating_public_repo ? Repository::PUBLIC_VISIBILITY : Repository::PRIVATE_VISIBILITY)
        deliver_error! 422, message: "Public repositories are not permitted for Enterprise Managed Organizations."
      end

      set_forbidden_message("You need admin access to the organization before adding a " \
                            "repository to it.")

      control_access :create_repo_for_org_from_template, resource: owner, challenge: true,
                      allow_integrations: true, allow_user_via_granular_actor: true, organization: owner


      if creating_private_repo?(attributes) &&
         !access_allowed?(:create_private_repo_for_org_from_template,
                          resource: owner,
                          allow_integrations: true,
                          allow_user_via_granular_actor: true,
                          organization: owner)

        deliver_create_private_repo_denied!
      end

      is_blocked_app = requestor_governed_by_oauth_application_policy? &&
        !owner.allows_oauth_application?(current_app_via_oauth)
      if is_blocked_app
        log_oap_restriction(oauth_app: current_app_via_oauth, org: owner)
        error_options = {
          message: "The OAuth application is not authorized for access to #{owner.display_login}.",
          documentation_url: @documentation_url,
        }
        deliver_error!(403, error_options)
      end
    else
      deliver_error! 404, message: "Invalid owner", documentation_url: @documentation_url
    end

    visibility = attributes[:private] ? Repository::PRIVATE_VISIBILITY : Repository::PUBLIC_VISIBILITY

    reflog_data = {
      real_ip: remote_ip,
      # login is ok when used for internal logs
      user_login: current_user.login, # rubocop:disable GitHub/DoNotAllowLogin
      user_agent: request.user_agent,
      from: GitHub.context[:from],
      via: "template repository clone",
    }

    new_repo, reason, message = repo.clone_template_to(owner,
      actor: current_user,
      name: attributes[:name],
      copy_branches: attributes[:include_all_branches],
      description: attributes[:description],
      visibility: visibility,
      reflog_data: reflog_data,
      current_integration_context: build_current_integration_context(target: owner, entry_point: :rest_api_clone_repo_from_template),
      allow_integrations: true
    )

    if reason == :forbidden
      deliver_error!(403, message: message, documentation_url: @documentation_url)
    end

    if reason == :unprocessable_entity
      deliver_error!(422, message: message, errors: [message])
    end

    deliver :full_repository_hash, new_repo, status: 201
  end

  # Transfer a repository
  post "/repositories/:repository_id/transfer", operation_id: "repos/transfer" do
    attributes = attr(receive_with_schema("repository-transfer", "transfer-legacy"), :new_owner, :team_ids, :new_name)

    new_owner = User.find_by(login: attributes[:new_owner])
    unless new_owner
      deliver_error! 422, message: "Invalid new_owner", documentation_url: @documentation_url
    end

    repository = find_repo
    control_access :transfer_repo, resource: repository, forbid: repository&.public?, new_owner: new_owner, challenge: true, allow_integrations: false, allow_user_via_granular_actor: true

    teams = new_owner.teams.where(id: attributes[:team_ids])

    variables = {
      repositoryId: repository.global_relay_id,
      newOwnerId: new_owner.global_relay_id,
      teamIds: teams.map(&:global_relay_id),
    }

    variables[:newName] = attributes[:new_name] if attributes[:new_name].present?

    results = platform_execute(TransferRepositoryQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error(
        errors: results.errors.all,
        resource: "Repository",
        documentation_url: @documentation_url,
      )
    else
      deliver :graphql_simple_repository_hash, results.data.transfer_repository.repository, status: 202
    end
  end


  verbs :patch, :post, "/repositories/:repository_id", operation_id: "repos/update" do
    data = receive(Hash)

    # If the request is attempting to only modify the security_and_analysis block
    # then we only need to verify that the user has the modify_security_products FGP
    # or edit_repo permissions.
    # Otherwise we only check that the user has edit repo rights as they will be modifying
    # values other than the security_and_analysis block.
    # This means if a security manager with no edit repo rights is trying to update
    # anything other than the security_and_analysis block they will get a 404.
    if security_and_analysis_only_access?(data)
      control_access :manage_repo_security_products, resource: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true
      if access_allowed?(:edit_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true)
        GitHub.dogstats.increment("repository.edited_by", tags: ["role:repo_administration_writer", "security_and_analysis_only:true"])
      else
        GitHub.dogstats.increment("repository.edited_by", tags: ["role:repo_security_products_manager", "security_and_analysis_only:true"])
      end
    else
      control_access :edit_repo, resource: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true
      GitHub.dogstats.increment("repository.edited_by", tags: ["role:repo_administration_writer", "security_and_analysis_only:false"])
    end

    authorize_content(:update, repo: repo, data: data)
    attributes = attr(data,
                  :description,
                  :homepage,
                  :has_issues,
                  :has_projects,
                  :has_wiki,
                  :has_downloads,
                  :has_discussions,)

    blocked_settings = BlockedSettings.new(repo.owner)

    if modifying_security_and_analysis?(data) && blocked_settings.any?
      GitHub.dogstats.increment(
        "settings.security_features.enablement.blocking",
        tags: blocked_settings.blockers.map { |b| "blocked_by:#{b}" } + ["location:repository_update_api"]
      )

      deliver_error! 422, message: blocked_settings.repo_message
    end

    set_template_attribute(data, attributes)
    updating_repo_to_public = updating_repo_to_public?(data)

    if repo.owner.emu_creating_public_repo?(updating_repo_to_public ? Repository::PUBLIC_VISIBILITY : Repository::PRIVATE_VISIBILITY)
      deliver_error! 422, message: "Public repositories are not permitted for Enterprise Managed Organizations."
    end

    repo.validate_description_length = attributes.has_key?("description")

    if attributes.has_key?("has_discussions")
      has_discussions = attributes.delete(:has_discussions)

      if has_discussions && !repo.discussions_on?
        repo.turn_on_discussions(actor: current_user)
      elsif !has_discussions && repo.discussions_on?
        repo.turn_off_discussions(actor: current_user)
      end
    end

    begin
      attributes.each do |key, value|
        repo.send "#{key}=", value
      end
    rescue Repository::ProjectsSettingsDependency::CannotEnableProjectsError
      deliver_error! 422,
        errors: [
          api_error(:Repository, :has_projects, :invalid,
            message: "This repository's organization has repository projects disabled, so projects cannot be enabled for this repository."),
        ],
        documentation_url: @documentation_url
    end

    saved = if data.has_key?("name") && repo.name != data["name"]
      repo.rename data["name"]
    elsif attributes.present?
      repo.save
    else
      true
    end

    if data.has_key?("visibility")
      data.delete(Repository::PRIVATE_VISIBILITY) # The presence of a visibility arg overrides the legacy private arg.
      begin
        case data["visibility"]
          # The fork-related visibility logic below should really be in the model
          # but for now, we set data["private"] here to preserve it.
        when Repository::PRIVATE_VISIBILITY
          data[Repository::PRIVATE_VISIBILITY] = true
          if repo.visibility != Repository::PRIVATE_VISIBILITY
            if repo.fork? && repo.matches_root_visibility?
              GitHub.logger.info("Making fork private",
                "gh.repo.id" => repo.id,
                "gh.user.id" => current_user.id,
                "gh.repo.visibility" => repo.visibility,
                "gh.repo.network.root.id" => repo.network.root.id,
                "gh.repo.network.root.visibility" => repo.network.root.visibility,
              )
            end
            saved = repo.set_visibility(actor: current_user, visibility: Repository::PRIVATE_VISIBILITY)
          end
        when Repository::PUBLIC_VISIBILITY
          data[Repository::PRIVATE_VISIBILITY] = false
        when Repository::INTERNAL_VISIBILITY
          if repo.visibility != Repository::INTERNAL_VISIBILITY
            saved = repo.set_visibility(actor: current_user, visibility: Repository::INTERNAL_VISIBILITY)
          end
        end
      rescue ArgumentError, Repositories::Error::VisibilityLocked => e
        deliver_error! 422, message: e.message, documentation_url: @documentation_url
      end
    end

    if data.keys.include?(Repository::PRIVATE_VISIBILITY)
      # If private is true and it's public OR if private is false and it's already private
      if (parse_bool(data[Repository::PRIVATE_VISIBILITY]) && repo.public?) || (!parse_bool(data[Repository::PRIVATE_VISIBILITY]) && !repo.public?)
        if repo.fork? && repo.matches_root_visibility?
          current, attempted = repo.public? ? [Repository::PUBLIC_VISIBILITY, Repository::PRIVATE_VISIBILITY] : [Repository::PRIVATE_VISIBILITY, Repository::PUBLIC_VISIBILITY]
          repo.errors.add(:base, "#{current.capitalize} forks can't be made #{attempted}")
          deliver_error! 422,
            errors: repo.errors,
            documentation_url: @documentation_url
        else
          begin
            # Attempt to toggle visibility of this repository. Authz checking is
            # performed by the model based on the current user.
            saved = repo.toggle_visibility(actor: current_user)
          rescue Repositories::Error::VisibilityLocked => e
            deliver_error! 422, message: e.message, documentation_url: @documentation_url
          end
        end
      end
    end

    if data.keys.include?("archived")
      if !repo.resources.administration.writable_by?(current_user)
        deliver_error! 422, message: "You cannot change repository archived state."
      elsif parse_bool(data["archived"]) && !repo.archived?
        saved = repo.set_archived
      elsif parse_bool(data["archived"]) == false && repo.archived?
        if repo.unarchive_blocked?
          deliver_error! 422, message: "Repository cannot be unarchived because its parent organization is archived."
        else
          saved = repo.unset_archived
        end
      end
    end

    # update the merge/squash blocking option
    allow_merge_commit = allow_rebase_merge = nil
    if data.has_key?("allow_merge_commit")
      allow_merge_commit = parse_bool(data["allow_merge_commit"])
    end
    if data.has_key?("allow_squash_merge")
      allow_squash_merge = parse_bool(data["allow_squash_merge"])
    end
    if data.has_key?("allow_rebase_merge")
      allow_rebase_merge = parse_bool(data["allow_rebase_merge"])
    end
    if data.has_key?("allow_auto_merge")
      allow_auto_merge = parse_bool(data["allow_auto_merge"])
    end
    if data.has_key?("delete_branch_on_merge")
      delete_branch_allowed = parse_bool(data["delete_branch_on_merge"])
    end
    if data.has_key?("allow_update_branch")
      update_branch_allowed = parse_bool(data["allow_update_branch"])
    end
    if data.has_key?("use_squash_pr_title_as_default")
      use_squash_pr_title_as_default = parse_bool(data["use_squash_pr_title_as_default"])
    end
    if data.has_key?("squash_merge_commit_message")
      squash_merge_commit_message = data["squash_merge_commit_message"]
    end
    if data.has_key?("squash_merge_commit_title")
      squash_merge_commit_title = data["squash_merge_commit_title"]
    end

    if data.has_key?("merge_commit_title")
      merge_commit_title = data["merge_commit_title"]
    end

    if data.has_key?("merge_commit_message")
      merge_commit_message = data["merge_commit_message"]
    end

    begin
      repo.update_merge_settings(current_user,
        merge_allowed: allow_merge_commit,
        squash_allowed: allow_squash_merge,
        rebase_allowed: allow_rebase_merge,
        auto_merge_allowed: allow_auto_merge,
        delete_branch_allowed: delete_branch_allowed,
        update_branch_allowed: update_branch_allowed,
        squash_pr_title_used_as_default: use_squash_pr_title_as_default,
        merge_commit_title_setting: merge_commit_title,
        merge_commit_message_setting:  merge_commit_message,
        squash_merge_commit_message_setting: squash_merge_commit_message,
        squash_merge_commit_title_setting: squash_merge_commit_title
      )
    rescue Repository::PullRequestDependency::MergeMethodError => e
      deliver_error! 422,
        errors: [
          api_error(:Repository, :merge_commit_allowed, :invalid,
            message: "#{e.message} (#{e.reason})"),
        ],
        documentation_url: @documentation_url
    end

    if data.has_key?("allow_forking")
      unless repo.owner&.organization?
        deliver_error! 422, message: "Allow forks can only be changed on org-owned repositories"
      end

      if repo.private_repository_forking_configurable? && !repo.allow_private_repository_forking_disabled_by_inherited_policy?
        allow_forks = parse_bool(data["allow_forking"])
        if allow_forks
          repo.allow_private_repository_forking(actor: current_user)
        else
          repo.block_private_repository_forking(actor: current_user)
        end
      else
        deliver_error! 422, message: "This organization does not allow private repository forking"
      end
    end

    if data.has_key?("web_commit_signoff_required")
      if repo.owner&.organization? && repo.organization&.dco_signoff_enabled?
        deliver_error! 422, message: "Commit signoff is enforced by the organization and cannot be disabled"
      else
        enable_signoff = parse_bool(data["web_commit_signoff_required"])
        if enable_signoff
          repo.enable_dco_signoff(actor: current_user)
        else
          repo.reset_dco_signoff(actor: current_user)
        end
      end
    end

    # have to go through a model method to update git
    attempt_default_branch_update = repo.empty? || data["default_branch"] != repo.default_branch
    if (new_branch = data["default_branch"]) && attempt_default_branch_update
      if !(saved &&= repo.switch_default_branch(current_user, new_branch))
        # TODO: Push this to the model, along with similar logic in GitContentController
        if !repo.empty? && new_branch == repo.default_branch
          return deliver :full_repository_hash, repo, show_merge_settings: true
        end
        message = if repo.empty?
          "Cannot update default branch for an empty repository. " \
          "Please init the repository and push first."
        elsif new_branch&.starts_with?("refs/heads/")
          "Sorry, branch names starting with 'refs/heads/' are not allowed."
        else
          "The branch #{new_branch} was not found. " \
          "Please push that ref first or create it via the Git Data API."
        end
        deliver_error! 422,
          errors: [
            api_error(:Repository, :default_branch, :invalid, message: message),
          ],
          documentation_url: @documentation_url
      end
    end

    # set anonymous git access if provided
    if data.keys.include?("anonymous_access_enabled")
      unless GitHub.anonymous_git_access_enabled?
        repo.errors.add(:base, "Repository anonymous access is not enabled")
        saved = false
      end

      saved &&= begin
        value = data["anonymous_access_enabled"]&.to_s
        error = nil
        if repo.fork?
          error = Repository::AnonymousGitAccess::FORK_ERROR
        elsif repo.anonymous_git_access_locked?(current_user)
          error = Repository::AnonymousGitAccess::LOCKED_ERROR
        elsif value == "true"
          repo.enable_anonymous_git_access(current_user)
        elsif value == "false"
          repo.disable_anonymous_git_access(current_user)
        else
          error = "Invalid value \"#{value}\" given for anonymous_access_enabled"
        end

        repo.errors.add(:base, error) if error
        error.nil?
      end
    end

    if data.dig("security_and_analysis", "advanced_security", "status")
      show_security_settings = true
      update_advanced_security(repo, data)
    else
      show_security_settings = repo.advanced_security_configurable?
    end

    if data.dig("security_and_analysis", "secret_scanning", "status")
      show_security_settings = true
      update_secret_scanning(repo, data)
    else
      show_security_settings |= (repo.advanced_security_configurable? || SecretScanning::Features::Repo::TokenScanning.new(repo).feature_available?)
    end

    push_protection = SecretScanning::Features::Repo::PushProtection.new(repo)
    if data.dig("security_and_analysis", "secret_scanning_push_protection", "status")
      if push_protection.feature_available?
        show_security_settings = true
        update_secret_scanning_push_protection(repo, data)
      end
    else
      show_security_settings |= (repo.advanced_security_configurable? || push_protection.feature_available?)
    end

    validity_checks = SecretScanning::Features::Repo::ValidityChecks.new(repo)
    if data.dig("security_and_analysis", "secret_scanning_validity_checks", "status")
      if validity_checks.feature_available?
        if validity_checks.enabled_by_org_or_biz?
          admin_type = case validity_checks.enabled_by
          when SecretScanning::Features::Repo::ValidityChecks::ENABLED_BY_ORGANIZATION
            "organization"
          when SecretScanning::Features::Repo::ValidityChecks::ENABLED_BY_BUSINESS
            "enterprise"
          else
            "organization or business"
          end
          deliver_error!(422, message: "Validity checks has been set by #{admin_type} administrators.")
        else
          show_security_settings = true
          update_secret_scanning_validity_checks(repo, data)
        end
      end
    else
      show_security_settings |= (repo.advanced_security_configurable? || validity_checks.feature_available?)
    end

    npp = SecretScanning::Features::Repo::LowerConfidencePatterns.new(repo)
    if data.dig("security_and_analysis", "secret_scanning_non_provider_patterns", "status")
      if npp.feature_available? && npp.enablement_api_available?
        if npp.enabled_by_enterprise?
          deliver_error!(422, message: "Non-provider patterns has been set by enterprise administrators.")
        elsif npp.enabled_by_organization?
          deliver_error!(422, message: "Non-provider patterns has been set by organization administrators.")
        else
          show_security_settings = true
          update_secret_scanning_non_provider_patterns(repo, data)
        end
      end
    else
      show_security_settings |= (repo.advanced_security_configurable? || npp.feature_available?)
    end

    if data.dig("security_and_analysis", "dependabot_security_updates", "status")
      show_security_settings = true
      update_dependabot_security_updates(repo, data)
    else
      show_security_settings |= (
        repo.advanced_security_configurable? ||
        SecurityProduct::VulnerabilityUpdates.new(repo).can_enable?(actor: current_user, options: {})
      )
    end

    if saved
      # Introducing strict validation of the repository.update
      # JSON schema would cause breaking changes for integrators
      # skip_validation until a rollout strategy can be determined
      # TODO: replace `receive` with `receive_with_schema`
      # see: https://github.com/github/ecosystem-api/issues/1555
      _ = receive_with_schema("repository", "update", skip_validation: true)

      show_merge_settings = access_allowed?(GitHub.flipper[:merge_settings_perms].enabled? ? :view_merge_settings : :edit_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true)
      deliver :full_repository_hash, repo, show_merge_settings: show_merge_settings, show_security_settings: show_security_settings
    elsif repo.errors[:visibility].present?
      deliver_error 422,
        message: repo.errors.full_messages.to_sentence,
        documentation_url: "https://github.com/pricing"
    else
      deliver_error 422,
        errors: repo.errors,
        documentation_url: @documentation_url
    end
  end

  # delete a repository
  delete "/repositories/:repository_id", operation_id: "repos/delete" do
    # Introducing strict validation of the repository.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("repository", "delete", skip_validation: true)

    repo = find_repo!

    control_access :delete_repo,
      resource: repo,
      # Respond with 403 when the user can access this repo but doesn't have the delete_repo scope
      forbid: forbids_when_deleting_repo?(repo, current_user),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    error = repo.cannot_delete_repository_reason(current_user)
    case error
    when :ofac_trade_restricted
      deliver_error! 403, message: ::TradeControls::Notices.notice_as_plaintext(:api_access_restricted)
    when :cant_delete_repos_on_this_appliance
      deliver_error! 403, message: "Users cannot delete repositories on this appliance."
    when :members_cant_delete_repositories
      deliver_error! 403, message: "Organization members cannot delete repositories."
    when :not_ready_for_writes
      deliver_error! 403, message: "Repository cannot be deleted until it is done being created on disk."
    when :prevented_by_ruleset
      deliver_error! 403, message: "Ruleset(s) are preventing this repository from being deleted."
    end

    # The default is already synchronous: false, but let's be explicit.
    # Make sure they know we're on a web request and want all the heavy lifting done in a background job
    repo.remove(current_user, synchronous: false)

    deliver_empty(status: 204)
  end

  # Get contributors for a repository
  get "/repositories/:repository_id/contributors", operation_id: "repos/list-contributors" do
    control_access :list_contributors, resource: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true

    if !repo.default_branch_exists?
      deliver_empty status: 204
    else
      GitHub.dogstats.time "repository", tags: ["action:contributors", "via:api"] do
        with_anon = parse_bool(params[:anon])

        response = repo.contributors(with_anon: with_anon, email_limit: 500)
        unless response.computed?
          deliver_error! 403,
            message: "The history or contributor list is too large to " \
                        "list contributors for this repository via the API."
        end

        contributors = response.value.paginate(pagination)
        deliver :contributor_hash, contributors, last_modified: calc_last_modified_for_object(repo)
      end
    end
  end

  # List teams for a repository.
  get "/repositories/:repository_id/teams", operation_id: "repos/list-teams" do
    control_access :list_repo_teams, resource: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true
    teams = repo.visible_teams_for(current_user, include_all_repo_roles: true).order(:id)
    teams = paginate_rel(teams)

    GitHub::PrefillAssociations.prefill_associations(teams, { organization: :profile })
    GitHub::PrefillAssociations.prefill_associations(teams, :ldap_mapping) if GitHub.enterprise?
    deliver :team_hash, teams, repo: repo
  end

  # list languages for a repository
  get "/repositories/:repository_id/languages", operation_id: "repos/list-languages" do
    control_access :list_languages,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_raw repo.language_breakdown, last_modified: calc_last_modified_for_object(repo)
  end

  # list tags for a repository
  get "/repositories/:repository_id/tags", operation_id: "repos/list-tags" do
    control_access :list_tags,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    page_tags = repo.tags.to_a.paginate(pagination)
    Git::Ref::Collection.preload_target_objects(page_tags)

    hashes = page_tags.map do |ref|
      commit = {
        sha: ref.commit? ? ref.commit.oid : "",
        url: ref.commit? ? commit_path(repo, ref.commit.oid) : "",
      }

      {
        name: ref.name,
        zipball_url: ref.commit? ? zipball_path(repo, ref.qualified_name) : "",
        tarball_url: ref.commit? ? tarball_path(repo, ref.qualified_name) : "",
        commit: commit,
        node_id: ref.global_relay_id,
      }
    end

    # Replace the original WillPaginate::Collection to keep its pagination metadata
    page_tags.replace(hashes)

    deliver_raw page_tags, last_modified: calc_last_modified_for_object(repo)
  end

  # list cache info for a repository
  get "/repositories/:repository_id/replicas/caches", operation_id: "repos/list-cache-info" do
    deliver_error!(404) unless GitHub.enterprise_only_api_enabled?

    control_access :list_repo_cache_info,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    cache_json = GitHub::DGit::Routing::all_repo_replicas(repo.id).map do |replica|
      next unless replica.cache_replica?

      if !replica.online?
        status = "offline"
      elsif !replica.active?
        status = "inactive"
      elsif replica.cache_in_sync?
        status = "in_sync"
      else
        status = "not_in_sync"
      end

      {
        host: replica.host,
        location: replica.cache_location,
        git: {
          sync_status: status,
          last_sync: replica.updated_at,
        },
      }
    end.compact

    deliver_raw cache_json.paginate(pagination)
  end

  # list forks for a repository
  get "/repositories/:repository_id/forks", operation_id: "repos/list-forks" do
    control_access :list_forks, resource: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true

    order = case params[:sort]
    when "newest"
      "repositories.created_at desc"
    when "oldest"
      "repositories.created_at"
    when "stargazers", "watchers" # TODO Remove `watchers` in API v4
      "#{Repository.stargazer_count_column} DESC"
    when String
      deliver_error! 400,
      message: "Invalid sort: #{params[:sort].inspect}.",
      documentation_url: @documentation_url
    else
      "repositories.created_at desc"
    end

    # Fallback to public forks only
    scope = if logged_in? && repo.private?
      private_repository_ids = ProgrammaticActor::RepositoryFilter.perform(
        actor: current_user, repository_ids: repo.forks.private_scope.pluck(:id), resource: "metadata"
      )

      private_repository_ids = current_user.associated_repository_ids(repository_ids: private_repository_ids)

      if private_repository_ids.any?
        repo.forks.public_scope.or(repo.forks.private_scope.where(id: private_repository_ids))
      else
        repo.forks.public_scope
      end
    else
      repo.forks.public_scope
    end

    forks = paginate_rel(scope.order(order))

    Configurable.preload_configuration(forks)
    Repository.prefill_associations(forks, internal: true)
    Repository.preload_repository_permissions(repositories: forks, users: [current_user].compact)

    deliver :repository_hash, forks
  end

  # create a fork
  post "/repositories/:repository_id/forks", operation_id: "repos/create-fork" do
    repo = find_repo!

    if repo.access.disabled?
      deliver_error! 404
    end

    # Introducing strict validation of the fork.create
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("fork", "create", skip_validation: true, expected_type: Hash, required: false) || {}

    # DEPRECATED: In API v4, you will no longer be able to specify the
    # organization as a query parameter. You will only be able to specify it in
    # the JSON request body.
    org_name = (params[:org] || params[:organization] || data["organization"]).to_s.dup
    org_name.strip!
    using_org = org_name.present?

    org = User.find_by(login: org_name) if using_org

    # validate the user has permissions before we validate the input arguments
    authorize_content(:fork, repo: repo) unless repo.private?
    control_access :create_fork,
      resource: repo,
      organization: org,
      enforce_oauth_app_policy: repo.private?,
      # For historical reasons, if you are forking and you can see the repo,
      # but you have insufficient scopes, then...
      # ... when forking to a user account, you get a 404
      # ... when forking to an organization, you get a 403
      forbid: org && repo.readable_by?(current_user),
      allow_integrations: true,
      allow_user_via_granular_actor: true
    authorize_content(:fork, repo: repo) if repo.private?

    if using_org
      if org.nil?
        error_options = {
          errors: convert_error({ organization: "is invalid" }, :Fork),
          documentation_url: @documentation_url,
        }
        deliver_error!(422, error_options)
      end

      if org.user?
        error_options = {
          errors: convert_error({ organization: "is invalid" }, :Fork),
          documentation_url: @documentation_url,
          message: "'#{org_name}' is the login for a user account. You must pass the login for an organization account.",
        }
        deliver_error!(422, error_options)
      end

      org = T.cast(org, Organization)

      if requestor_governed_by_oauth_application_policy? && !org.allows_oauth_application?(current_app_via_oauth)
        # TODO: this is the message that currently gets set if an app is blocked.
        # Perhaps we should reconsider.
        error_options = {
          message: "Must have admin rights to Repository.",
          documentation_url: @documentation_url,
        }
        deliver_error!(403, error_options)
      end
    end

    if repo.empty?
      deliver_error! 403,
        message: "The repository exists, but it contains no Git content. Empty repositories cannot be forked.",
        documentation_url: @documentation_url
    end

    if repo.forking_disabled?
      deliver_error!(403, {
        message: "The repository exists, but forking is disabled.",
        documentation_url: @documentation_url,
      })
    end

    new_fork_name = data["name"]
    default_branch_only = data["default_branch_only"]

    options = {
      forker: current_user,
      org: org,
      new_name: new_fork_name,
      one_branch: default_branch_only,
    }
    # If the actor is a GitHub App, then by default
    # it will fork the repository to the [bot]
    # account. Instead, we wwant to fork to the account or
    # organization that the App is installed on.
    if current_actor.is_a?(IntegrationInstallation)
      target = current_actor.target
      if target.user?
        options[:forker] = target
      else
        options[:org] = target
      end
    end

    forked_repo, reason, errors = repo.fork(options)

    if !forked_repo
      message = Repository::ForkerMethods.message_from_reason(reason, errors)
      deliver_error!(403, message: message, documentation_url: @documentation_url) if message
    end

    deliver :full_repository_hash, forked_repo, status: 202
  end

  # Compare commits
  get "/repositories/:repository_id/compare/*", operation_id: "repos/compare-commits" do
    repo = find_repo!
    control_access :compare_commits,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    base, head = params[:splat].first.split("...", 2)

    # We don't want a limit if we're going to paginate, since we're doing the
    # pagination inside serialization.
    # The limit is only applied on this side of the RPC call, so it doesn't add
    # any overhead to the comparison, just moves the truncation of the commit
    # list to serialization rather than in the model method.
    comparison = repo.comparison(base, head, wants_pagination? ? nil : 250)

    unless comparison.valid? && !comparison.diffs.missing_commits? && comparison.viewable_by?(current_user)
      deliver_error! 404
    end

    unless comparison.common_ancestor?
      deliver_error! 404,
        message: "No common ancestor between #{base} and #{head}."
    end

    if !comparison.diffs.available? || comparison.diffs.truncated_for_timeout?
      deliver_undiffable_error!(:Comparison, comparison.diffs)
    end

    # Only add pagination links if the request originally requested pagination
    if wants_pagination?
      @paginator = build_paginator(default_per_page: 250, max_per_page: 1000)

      if comparison.total_commits > pagination[:per_page]
        last_page = (comparison.total_commits / pagination[:per_page].to_f).ceil
        @links.add_current({ page: last_page }, rel: "last") if last_page

        @links.add_current({ page: current_page + 1 }, rel: "next") if current_page < last_page
      end

      @links.add_current({ page: 1 }, rel: "first")
      if current_page > 1
        @links.add_current({ page: current_page - 1 }, rel: "prev")
      end
    end

    begin
      deliver_compare_content(
        repo: repo,
        comparison: comparison,
        last_modified_at: calc_last_modified_for_object(comparison)
      )
    rescue GitRPC::Timeout
      GitHub.dogstats.increment("api.compare.rpc_timeout")

      deliver_undiffable_error!(:Comparison, comparison.diffs)
    end
  end

  get "/repositories", operation_id: "repos/list-public" do
    control_access :public_site_information, resource: Platform::PublicResource.new, allow_integrations: true, allow_user_via_granular_actor: true # rubocop:disable GitHub/PublicResource

    since = params[:since] ? int_id_param!(key: :since, halt: true) : 0
    options = { cursor: since }

    if GitHub.flipper[:get_repositories_custom_page_size].enabled?(current_user) # rubocop:disable GitHub/UseActorFeatureEnabled
      options[:page_size] = params[:per_page].to_i
    end

    repos = if include_private_repos?
      # these should likely be CAP filtered
      T.unsafe(Repository.active).dump_all(options)
    else
      unauthorized_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations)
      unauthorized_sso_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)
      if unauthorized_org_ids.any?
        set_sso_partial_results_header(unauthorized_sso_org_ids) if unauthorized_sso_org_ids.any?
        options[:unauthorized_org_ids] = unauthorized_org_ids
      end
      T.unsafe(Repository.active).dump_public(options)
    end
    @links.add_dump_pagination(repos.last)

    include_timestamps = GitHub.flipper[:simple_repository_hash_with_timestamps].enabled?(current_user) # rubocop:disable GitHub/UseActorFeatureEnabled

    Repository.prefill_associations(repos)

    deliver :simple_repository_hash,
      exclude_orphans(repos),
      include_timestamps: include_timestamps
  end

  get "/repositories/:repository_id/mentionables/users", operation_id: :unreleased do
    @route_owner = "@github/repos"

    control_access :get_repo, resource: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true

    mentionables = repo.mentionable_users_for(current_user, include_child_teams: false)
    mentionables = mentionables.includes(:profile, :primary_user_email, :primary_private_user_email, :stealth_user_email)

    deliver :mentionable_user_hash, mentionables
  end

  READ_ONLY_ACTION_ROUTES = [
    ["get", "/repositories/:repository_id"]
  ]

  # This method is defined here to allow the ConditionalAccess
  # enforcer to skip access checks (specifically IP allow list) on
  # public repositories.
  def action
    return :read if READ_ONLY_ACTION_ROUTES.include?(
      [request.request_method.downcase, route_pattern.to_s]
    )
    nil
  end

  def emu_ownership_enforceable
    template_generate = request.request_method == "POST" && route_pattern == "/repositories/:template_repository_id/generate"

    # Allow EMU to generate templates from public repos
    return :no if template_generate && find_repo!.public?

    :yes
  end

  # This method is added for EMU visibility policy enforcement
  # It follows the same logic as emu_ownership_enforceable
  # meaning that it allows EMU to generate templates from public repos
  def emu_visibility_enforceable
    emu_ownership_enforceable
  end

  private

  sig do
    params(
      attributes: Repositories::CreateRepositoryAttributes,
      data: T::Hash[Symbol, String],
      attribute: Symbol,
      source_key: Symbol
    ).void
  end
  def update_repo_attributes(attributes, data, attribute, source_key: attribute)
    return unless data.key?(source_key)

    attributes.send("#{attribute}=", parse_bool(data[source_key]))
  end

  sig { params(value: Kernel).returns(T.nilable(String)) }
  def coerce_string(value)
    value.nil? ? nil : value.to_s
  end

  sig do
    params(
      attributes: Repositories::CreateRepositoryAttributes,
      data: T::Hash[Symbol, String],
      attribute: Symbol,
      enum: T.class_of(T::Enum)
    ).void
  end
  def update_commit_setting(attributes, data, attribute, enum)
    return if data[attribute].nil?

    value = data[attribute]&.downcase
    attributes.send("#{attribute}=", enum.try_deserialize(value))
  end

  def domain_actor
    current_user
  end

  def deliver_compare_content(repo:, comparison:, last_modified_at:)
    if medias.api_param?(:diff)
      delivering_raw_diff_content(medias) do
        deliver_raw comparison.to_diff,
        content_type: "#{medias}; charset=utf-8",
        last_modified: last_modified_at
      end
    elsif medias.api_param?(:patch)
      delivering_raw_diff_content(medias) do
        deliver_raw comparison.to_patch,
        content_type: "#{medias}; charset=utf-8",
        last_modified: last_modified_at
      end
    else
      serialization_options = {
        repo: repo,
        last_modified: last_modified_at,
      }

      if wants_pagination?
        serialization_options = serialization_options.merge({
          page: current_page,
          per_page: pagination[:per_page],
        })
      end

      deliver :github_comparison_hash, comparison, serialization_options
    end
  end

  # These are repos that are orphaned due to failed user deletes, we need to exclude them because they
  # fail serialization
  def exclude_orphans(repos)
    repos.select { |repo| repo.owner.present? }
  end

  def creating_private_repo?(data)
    data[Repository::PUBLIC_VISIBILITY] == false || data[Repository::PRIVATE_VISIBILITY] == true
  end

  def creating_public_repo?(data)
    if data.has_key?("visibility")
      data["visibility"] == Repository::PUBLIC_VISIBILITY
    else
      !creating_private_repo?(data)
    end
  end

  def updating_repo_to_public?(data)
    (
      data.has_key?("visibility") ||
      data.has_key?(Repository::PUBLIC_VISIBILITY) ||
      data.has_key?(Repository::PRIVATE_VISIBILITY)
    ) && creating_public_repo?(data)
  end

  def zipball_path(repo, ref)
    "#{GitHub.api_url}/repos/#{repo.name_with_owner_for_api}/zipball/#{ref}"
  end

  def tarball_path(repo, ref)
    "#{GitHub.api_url}/repos/#{repo.name_with_owner_for_api}/tarball/#{ref}"
  end

  def commit_path(repo, sha)
    "#{GitHub.api_url}/repos/#{repo.name_with_owner_for_api}/commits/#{sha}"
  end

  def add_pagination_scopes(scope)
    scope = sort_repo_scope(scope, "id")
    paginate_rel(scope)
  end

  # Return a list of repositories for the given org, accessible by the given
  # user, including:
  #
  # - public repositories which are owned by the org
  # - repositories owned by the org, when user is a member of org's Owners team
  # - repositories owned by the org, when user is a member of an org team which
  #   grants access to the repository
  def all_org_constrained_accessible_repositories(organization:, user:, public_only:)
    params[:sort] = "id" if params[:sort].blank?
    sort = case params[:sort]
    when "updated"
      Repositories::SortBy::UpdatedAtThenId
    when "pushed"
      Repositories::SortBy::PushedAtThenId
    when "name"
      Repositories::SortBy::NameThenId
    when "full_name"
      Repositories::SortBy::FullNameThenId
    when "id"
      Repositories::SortBy::Id
    else
      Repositories::SortBy::CreatedAtThenId
    end

    direction = if params[:direction]
      GH::Pagination::Sort::Direction.from_string(params[:direction])
    else
      case sort
      when Repositories::SortBy::CreatedAtThenId, Repositories::SortBy::UpdatedAtThenId, Repositories::SortBy::PushedAtThenId
        GH::Pagination::Sort::Direction::DESC
      else
        GH::Pagination::Sort::Direction::ASC
      end
    end

    args = Repositories::ByOrgMemberArgs.new(
      organization: organization,
      user: user,
      pagination: GH::Pagination::Offset.new(
        per_page: pagination[:per_page],
        page: pagination[:page]
      ),
      sort:,
      direction:,
      permission: Repositories::PlatformPermissionSwitch.new(nil, override: true),
      privacy: public_only ? Repositories::RepositoryVisibility::Public : nil,
      filter_spam: false
    )
    repositories_domain.by_org_member(args)
  end

  # Public: Return a list of root (non-fork) repositories for the given org,
  # accessible by the given user, including:
  #
  # - public repositories which are owned by the org
  # - repositories owned by the org, when user is a member of org's Owners team
  # - repositories owned by the org, when user is a member of an org team which
  #   grants access to the repository
  #
  # user - a User
  # org  - an Organization
  #
  # Returns a Repository scope.
  def source_org_constrained_accessible_repositories(user, org)
    all_public_org_root_repo_ids = org.org_repositories.public_scope.network_roots.pluck(:id)

    repo_ids_with_team_membership = user.associated_repository_ids(including: [:direct, :indirect], repository_ids: Repository.owned_by(org).network_roots.ids)
    repo_ids_with_team_membership = ProgrammaticActor::RepositoryFilter.perform(actor: current_user, repository_ids: repo_ids_with_team_membership)

    ids = repo_ids_with_team_membership | all_public_org_root_repo_ids

    Repository.active.where(id: ids)
  end

  # Public: Return a list of fork repositories for the given org, accessible by
  # the given user, including:
  #
  # - public repositories which are owned by the org
  # - repositories owned by the org, when user is a member of org's Owners team
  # - repositories owned by the org, when user is a member of an org team which
  #    grants access to the repository
  #
  # user - a User
  # org  - an Organization
  #
  # Returns a Repository scope.
  def forked_org_constrained_accessible_repositories(user, org)
    all_public_org_fork_repo_ids = org.org_repositories.public_scope.forks_owned_by(org).pluck(:id)

    repo_ids_with_team_membership = user.associated_repository_ids(including: [:direct, :indirect], repository_ids: Repository.forks_owned_by(org).ids)
    repo_ids_with_team_membership = ProgrammaticActor::RepositoryFilter.perform(actor: current_user, repository_ids: repo_ids_with_team_membership)

    ids = repo_ids_with_team_membership | all_public_org_fork_repo_ids

    Repository.active.where(id: ids)
  end

  def set_repo_direction_and_sort(default_sort)
    params[:direction] = nil if params[:direction].blank?
    params[:sort] = default_sort if params[:sort].blank?
  end

  def sort_repo_scope(scope, default_sort = nil)
    set_repo_direction_and_sort(default_sort)
    scope.sorted_by(params[:sort], params[:direction])
  end

  def filter_and_sort(scope, default_sort = nil)
    # specify sort
    scope = sort_repo_scope(scope, default_sort)

    # filter by updated_at
    if (since = time_param!(:since)).present?
      scope = scope.since(since.getlocal)
    end

    if (before = time_param!(:before)).present?
      scope = scope.before(before.getlocal)
    end

    scope.filter_spam_for(current_user)
  end

  def deliver_create_private_repo_denied!
    message = "You'll need a different OAuth scope to create a private repository. " \
              "Please see the documentation for full details."
    deliver_error! 403,
      message: message,
      documentation_url: "/rest/reference/repos#create-a-repository-for-the-authenticated-user"
  end

  def include_private_repos?
    # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
    GitHub.enterprise? && access_allowed?(:list_all_repos, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true) && params["visibility"] == "all"
    # rubocop:enable GitHub/DoNotSkipCapAccessAllowed
  end

  def authorize_content(operation = :create, data = {})
    authorization = ContentAuthorizer.authorize(current_user, :repo, operation, data)
    deliver_content_authorization_denied!(authorization) if authorization.failed?
  end

  def forbids_when_deleting_repo?(repo, user)
    return true if repo.public?
    return true if access_allowed?(:get_repo,
                                   resource: repo,
                                   allow_integrations: true,
                                   allow_user_via_granular_actor: true)

    return false if current_integration || current_integration_installation || current_user_programmatic_access

    repo.pullable_by?(user) && scope?(user, "delete_repo")
  end

  def new_repository_reflog_data(creator, data, via)
    # login not used in response therefore safe to use here.
    {
      real_ip: remote_ip,
      repo_name: "#{creator.login}/#{data[:name]}", # rubocop:disable GitHub/DoNotAllowLogin
      repo_public: data[:public],
      user_login: current_user.login, # rubocop:disable GitHub/DoNotAllowLogin
      user_agent: request.user_agent,
      from: GitHub.context[:from],
      via: via,
    }
  end

  def set_template_attribute(data, attributes)
    if data.key?("is_template")
      new_val = parse_bool(data["is_template"])
      if !new_val.nil?
        attributes["template"] = new_val
      end
    end
  end

  def build_current_integration_context(target:, entry_point:)
    { integration: current_integration, entry_point: entry_point } if integration_bot_request? || integration_user_request?
  end

  def update_advanced_security(repo, data)
    status = data.dig("security_and_analysis", "advanced_security", "status")

    if status == "enabled"
      res = SecurityProduct::ServiceManager.new(repo).toggle_services(current_user, services_to_enable: [:advanced_security])
    elsif status == "disabled"
      res = SecurityProduct::ServiceManager.new(repo).toggle_services(current_user, services_to_disable: [:advanced_security])
    else
      deliver_error! 400, message: "Invalid value for Advanced Security status"
    end

    if res.error?
      message = SecurityProduct::AdvancedSecurity.error_to_message(res.error) || "Failed to change Advanced Security status"
      deliver_error! 422, message: message
    end
  end

  def get_organization_security_and_analysis_role(owner)
    return unless owner&.is_a?(Organization)

    if access_allowed?(:view_org_settings, resource: owner, allow_integrations: true, allow_user_via_granular_actor: true)
      ORG_ADMIN_ROLE
    elsif access_allowed?(:read_org_security_products, resource: owner, allow_integrations: true, allow_user_via_granular_actor: true)
      ORG_SECURITY_MANAGER_ROLE
    else
      ORG_MEMBER_ROLE
    end
  end

  def emit_security_and_analysis_role(owner, org_level_endpoint: false, role: nil)
    metric_level = org_level_endpoint ? "organization.repositories" : "repository"
    metric_name = "api.#{ metric_level }.security_and_analysis_viewed"

    # There are three types of users that can see the security and analysis settings. Org Admins, Repo Admins, and
    # Security Managers. We start with the highest permission and most permissive type of user first and then move to
    # the more restricted users. An org admin can see all settings across all repos for their org so that is our first
    # check (:view_org_settings). Security managers can see security and analysis settings for repos across the org.
    # Since we already know the user is NOT an org admin by the time we do the :read_org_security_products check we
    # know the user must NOT be a org admin, and could only be a Security Manager if the check passes. Finally if
    # neither check is true, we know the user must be able to see these settings because they are a repo admin
    role = role || get_organization_security_and_analysis_role(owner)
    return if role.nil?

    GitHub.dogstats.increment(metric_name, tags: ["role:#{role}"])
  end

  sig { params(repo: Repositories::IRepository).returns(T::Boolean) }
  def can_access_security_and_analysis?(repo)
    return false unless repo.advanced_security_configurable? || SecretScanning::Features::Repo::TokenScanning.new(T.cast(repo, Repository)).feature_available? # rubocop:todo GitHub/AvoidCast
    access_allowed?(:view_repo_security_products, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true)
  end

  def update_secret_scanning(repo, data)
    success = false # set true only on non-server errors or explicit success
    begin
      if repo.owner&.user? && !SecretScanning::Features::Repo::TokenScanning.new(repo).ux_on_public_repo_enabled?
        success = true
        deliver_error! 422, message: "Secret Scanning can only be changed on org owned repositories"
      end

      status = data.dig("security_and_analysis", "secret_scanning", "status")
      if status == "enabled"
        res = SecurityProduct::ServiceManager.new(repo).toggle_services(current_user, services_to_enable: [[:token_scanning]])
      elsif status == "disabled"
        res = SecurityProduct::ServiceManager.new(repo).toggle_services(current_user, services_to_disable: [:token_scanning])
      else
        success = true
        deliver_error! 400, message: "Invalid value for Secret Scanning status"
      end

      if res.error?
        message = SecurityProduct::TokenScanning.error_to_message(res.error)
        success = true
        deliver_error! 422, message: message
      end
      success = true
    ensure
      # TODO this can only be successful, cleanup after corresponding SLO has been refactored https://github.com/github/secret-scanning/issues/8246
      GitHub.dogstats.increment("github/secret_scanning_experiences.slo", tags: ["name:rest-api-availability", "controller:#{GitHub::TaggingHelper.controller(env)}", "method:#{__method__}", "success:#{success}"])
    end
  end

  def update_secret_scanning_push_protection(repo, data)
    status = data.dig("security_and_analysis", "secret_scanning_push_protection", "status")
    if status == "enabled"
      res = SecurityProduct::ServiceManager.new(repo).toggle_services(current_user, services_to_enable: [:token_scanning_push_protection])
    elsif status == "disabled"
      res = SecurityProduct::ServiceManager.new(repo).toggle_services(current_user, services_to_disable: [:token_scanning_push_protection])
    else
      deliver_error! 400, message: "Invalid value for Push Protection status"
    end

    if res.error?
      message = SecurityProduct::TokenScanningPushProtection.error_to_message(res.error)
      deliver_error! 422, message: message
    end
  end

  def update_secret_scanning_validity_checks(repo, data)
    status = data.dig("security_and_analysis", "secret_scanning_validity_checks", "status")
    if status == "enabled"
      res = SecurityProduct::ServiceManager.new(repo).toggle_services(current_user, services_to_enable: [:token_scanning_validity_checks])
    elsif status == "disabled"
      res = SecurityProduct::ServiceManager.new(repo).toggle_services(current_user, services_to_disable: [:token_scanning_validity_checks])
    else
      deliver_error! 400, message: "Invalid value for Validity Checks status"
    end

    if res.error?
      message = SecurityProduct::TokenScanningValidityChecks.error_to_message(res.error)
      deliver_error! 422, message: message
    end
  end

  def update_secret_scanning_non_provider_patterns(repo, data)
    status = data.dig("security_and_analysis", "secret_scanning_non_provider_patterns", "status")
    if status == "enabled"
      res = SecurityProduct::ServiceManager.new(repo).toggle_services(current_user, services_to_enable: [:token_scanning_lower_confidence_patterns])
    elsif status == "disabled"
      res = SecurityProduct::ServiceManager.new(repo).toggle_services(current_user, services_to_disable: [:token_scanning_lower_confidence_patterns])
    else
      deliver_error! 400, message: "Invalid value for Non-provider Patterns status"
    end

    if res.error?
      message = SecurityProduct::TokenScanningLowerConfidencePatterns.error_to_message(res.error)
      deliver_error! 422, message: message
    end
  end

  def update_dependabot_security_updates(repo, data)
    status = data.dig("security_and_analysis", "dependabot_security_updates", "status")

    if status == "enabled"
      res = SecurityProduct::ServiceManager.new(repo).toggle_services(current_user, services_to_enable: [:vulnerability_updates])
    elsif status == "disabled"
      res = SecurityProduct::ServiceManager.new(repo).toggle_services(current_user, services_to_disable: [:vulnerability_updates])
    else
      deliver_error! 400, message: "Invalid value for Dependabot Security Updates status"
    end

    if res.error?
      message = SecurityProduct::VulnerabilityUpdates.error_to_message(res.error) || "Failed to change Dependabot Security Updates status"
      deliver_error! 422, message: message
    end
  end

  def minimum_to_hydrate(pagination)
    page = pagination[:page] || 1
    per_page = pagination[:per_page] || WillPaginate.per_page
    page * per_page
  end

  def security_and_analysis_only_access?(data)
    # If any value other than security_and_analysis is being modified then you need edit_repo
    return false if data.keys.any? { |k| k != "security_and_analysis" }
    # If security_and_analysis isnt being modified then you need edit_repo
    return false unless modifying_security_and_analysis?(data)

    true
  end

  def modifying_security_and_analysis?(data)
    data.key?("security_and_analysis")
  end

  def sort_and_paginate_scope(scope, page, per_page, order_by, order_by_direction)
    order_by = :id if order_by.blank?
    order_by = order_by.to_sym

    default_dir = Repository::DEFAULT_ASC_SORT_FIELDS.include?(order_by) ? :asc : :desc
    order_by_direction = if order_by_direction.blank?
      default_dir
    else
      order_by_direction.to_s.downcase == "asc" ? :asc : :desc
    end

    repos = case order_by
    when :created
      scope.pluck(:created_at, :id)
    when :updated
      scope.pluck(:updated_at, :id)
    when :pushed
      scope.pluck(:pushed_at, :id)
    when :full_name
      scope.select(:owner_login, :name, :id).map { |r| ["#{r.owner_display_login}/#{r.name}", r.id] }
    else
      scope.pluck(:id, :id)
    end

    repos = repos.sort_by { |t| sortable_field_to_tuple(t) }
    repos = repos.reverse if order_by_direction == :desc
    GitHub.dogstats.distribution("repositories_api.unpaginated_repositories.count", repos.size, tags: ["owner:organization"])

    offset = (page - 1) * per_page
    limit = per_page
    [repos.drop(offset).take(limit), repos.size]
  end

  # Fields are in the form: [sort_by_field_value, id]
  # e.g. ["some-repo", 123]
  # e.g. [123, 123]

  # For Enumerable#sort_by purposes, we need to convert this to: [present?, sort_by_field_value, id]
  # so nil values will be come first.
  #
  # We also upcase everything to ensure we sort in the manner as the database (e.g. underscores last)
  def sortable_field_to_tuple(field)
    not_nil = (field.present? && field[0].present?) ? 1 : 0
    sortable_field = sortable_field(field[0])
    id = field[1]
    [not_nil, sortable_field, id]
  end

  def sortable_field(field)
    field.try(:upcase) || field
  end

  def prefill_repository_reference_keys(repos)
    if GitHub.spokesd_enabled?
      repo_ids = repos.pluck(:id)
      return if repo_ids.empty?

      checksums = SpokesAPI::Client.for_repositories(repo_ids).get_cache_keys
      repos.each do |repo|
        repo.rpc.set_repository_reference_key!(checksums[repo.id] || "now/#{"%d" % (Time.now.to_f * 1000.0)}")
      end
    end

    repos.map { |repo| repo.rpc.repository_reference_key }
  rescue Repository::RpcDependency::UnroutedError, SpokesAPI::Error
  end

  TransferRepositoryQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($repositoryId: ID!, $newOwnerId: ID!, $teamIds: [ID!], $newName: String) {
      transferRepository(input: {repositoryId: $repositoryId, newOwnerId: $newOwnerId, teamIds: $teamIds, newName: $newName}) {
        repository {
          ...Api::Serializer::RepositoriesDependency::SimpleRepositoryFragment
        }
      }
    }
  GRAPHQL
end
