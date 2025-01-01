# typed: true
# frozen_string_literal: true

module Api::App::FindersDependency
  extend T::Helpers

  requires_ancestor { Api::App }

  include App::IExecContextAccessor

  # Public: Fetches the current repo of this request.
  #
  # Returns a Repository instance. Halts with a 404 if no Repository is found.
  def current_repo
    @current_repo ||= find_repo!
  end

  def current_repo_loaded?
    !@current_repo.nil?
  end

  # Internal: Set the given repository as *the* repository associated with this
  # request, so that it can be used when determining whether the request has
  # sufficient authorization.
  #
  # repo - A Repository.
  #
  # Returns nothing.
  def set_current_repo_for_access_control(repo)
    @current_repo = repo
  end

  # Public: Selects the Repository defined in the URL of all Repository paths:
  #
  #   /repositories/:repository_id
  #
  # Returns a Repository instance or halts with 404 if not found.
  def find_repo!
    repository_or_404(find_repo)
  end

  # Public: Selects the template Repository defined in the URL:
  #
  #   /repositories/:template_repository_id
  #
  # Returns a Repository instance or halts with 404 if not found.
  def find_template_repo!
    id = int_id_param!(key: :template_repository_id)
    template_repo = Repository.templates.find_by(id: id) if id > 0
    repository_or_404(template_repo)
  end

  # Public: Selects the Gist as defined by params[param_name] in the request URL.
  #
  # param_name  - (optional) The `params` key where the Gist repo name can
  #               be found. Defaults to :id. If not :id, assumed to be name
  # owner_param - (optional) The `params` key where the owner login can be
  #               found.
  #
  # Returns a Gist or nil if not found.
  def find_gist(param_name: :id, owner_param: nil)
    scope = Gist.preload(:user).active.not_spammy

    if owner_param.present?
      owner, repo_name = params.values_at(owner_param, param_name)
      T.unsafe(scope).with_name_with_owner(owner, repo_name)
    elsif param_name == :id
      id = int_id_param!(key: :id)
      scope.find_by(id: id) if id > 0
    else
      scope.find_by(repo_name: params[param_name])
    end
  end

  def find_gist_including_deleted_and_disabled
    id = int_id_param!(key: :id)
    Gist.find_by(id: id)
  end

  # Public: Selects the Gist as defined by params[param_name] in the request URL.
  #
  # param_name  - (optional) The `params` key where the Gist repo name can
  #               be found. Defaults to :id.
  # owner_param - (optional) The `params` key where the owner login can be
  #               found.
  #
  # Returns a Gist or halts with a 404 if not found.
  def find_gist!(param_name: :id, owner_param: nil)
    find_gist(param_name: param_name, owner_param: owner_param).tap do |gist|
      gist_or_404(gist)

      if gist.access.disabled?
        deliver_disabled_gist_error!(gist)
      end
    end
  end

  # Public: Selects the PullRequest for the given repository and special PR ref.
  #
  # Returns a PullRequest or nil if not found.
  def find_pull_request_from_ref(repo, ref)
    m = ref&.match(/\Arefs\/pull\/([0-9]+)\/(?:head|merge)\Z/)
    PullRequest.with_number_and_repo(m[1], repo) if m
  end

  # A safer, kinder, gentler way to get a commit. Let's not leak out
  # nasty 500 exceptions to end users if their sha is unknown or malformed
  # This should be handled better at a lower level...some sort of
  # safe way to ask for a commit for a SHA without having to worry about
  # leaking out lower level exceptions.
  def find_commit!(repo, sha, documentation_url = nil)
    if sha && commit_oid = repo.ref_to_sha(sha)
      if repo.is_a?(::Repository)
        Repositories.domain.commits.by_oid(repository: repo, commit_oid: commit_oid)
      else
        # Convert to a domain accessor call when Gist and Wiki have a commits accessor available
        repo.commits.find(commit_oid)
      end
    else
      deliver_error! 422,
        message: "No commit found for SHA: #{sha}",
        documentation_url: documentation_url
    end
  rescue GitRPC::InvalidObject, GitRPC::ObjectMissing
    deliver_error! 422,
      message: "No commit found for SHA: #{sha}",
      documentation_url: documentation_url
  end

  # Public: Selects the Repository defined in the URL of this request by
  # checking the `:user` and `:repo` parameters.
  #
  # Halts with a redirect if the Repository has relocated (e.g., if it has
  #   been renamed).
  # Halts with a 404 if no Repository is found.
  # Returns a Repository instance.
  def this_repo
    if path_includes_relocated_repo?
      redirect_to_new_repo_location_or_404! &method(:this_repo_redirection)
    end

    repo = env[GitHub::Routers::Api::ThisRepositoryKey] = Repository.nwo(repo_nwo_from_path)
    repository_or_404(repo)
  end

  def repository_or_404(repo)
    repo && repo.network_broken?
    repo = nil if repo && (!repo.active? || repo.disabled? || repo.hide_from_user?(current_user))
    record_or_404 repo
  rescue Repository::NetworkDependency::NetworkMissingError => e
    Failbot.report e

    deliver_disabled_repo_error!(repo)
  end

  def gist_or_404(gist)
    gist = nil if gist && !gist.active?
    record_or_404 gist
  end

  sig do
    type_parameters(:U)
      .params(record: T.nilable(T.type_parameter(:U)), error_options: T::Hash[Symbol, String])
      .returns(T.type_parameter(:U))
  end
  def record_or_404(record, error_options: {}) # rubocop:disable GitHub/ApiDeliverWrappersNamedDeliver
    record || deliver_error!(missing_repository_status_code, **(missing_repository_options.merge(error_options)))
  end

  # Public: Selects the PreReceiveEnvironment defined in the URL request.
  #
  # Returns a PreReceiveEnvironment instance if found.
  def find_pre_receive_environment(param_name: :id)
    PreReceiveEnvironment.find_by(id: int_id_param!(key: param_name))
  end

  # Public: Selects the PreReceiveEnvironment defined in the URL request.
  #
  # Returns a PreReceiveEnvironment instance or halts with 404 if not found.
  def find_pre_receive_environment!(param_name: :id)
    record_or_404 find_pre_receive_environment(param_name: param_name)
  end

  # Public: Selects the PreReceiveHook defined in the URL request.
  #
  # Returns a PreReceiveHook instance if found.
  def find_pre_receive_hook(param_name: :id)
    PreReceiveHook.find_by(id: int_id_param!(key: param_name))
  end

  # Public: Selects the PreReceiveHook defined in the URL request.
  #
  # Returns a PreReceiveHook instance or halts with 404 if not found.
  def find_pre_receive_hook!(param_name: :id)
    record_or_404 find_pre_receive_hook(param_name: param_name)
  end

  # Public: Selects the global PreReceiveHookTarget for the PreReceiveHook defined in the URL request.
  #
  # Returns a PreReceiveHookTarget instance if found.
  def find_global_pre_receive_hook_target(param_name: :id)
    PreReceiveHookTarget.global.for_hook(int_id_param!(key: param_name)).first
  end

  # Public: Selects the global PreReceiveHookTarget for the PreReceiveHook defined in the URL request.
  #
  # Returns a PreReceiveHookTarget instance or halts with 404 if not found.
  def find_global_pre_receive_hook_target!(param_name: :id)
    record_or_404 find_global_pre_receive_hook_target(param_name: param_name)
  end

  # Public: Selects the PreReceiveHookTarget for the PreReceiveHook defined in the URL request.
  #
  # Returns a PreReceiveHookTarget instance if found.
  def find_pre_receive_hook_target(param_name: :id)
    hookable =
      case
      when params[:repository_id]
        find_repo!
      when params[:organization_id]
        find_org!
      else
        GitHub.global_business
      end
    hook_id = int_id_param!(key: param_name)
    PreReceiveHookTarget.enforcement_target(hookable, hook_id)
  end

  # Public: Selects the PreReceiveHookTarget for the PreReceiveHook defined in the URL request.
  #
  # Returns a PreReceiveHookTarget instance or halts with 404 if not found.
  def find_pre_receive_hook_target!(param_name: :id)
    record_or_404 find_pre_receive_hook_target(param_name: param_name)
  end

  # Public: Selects the User defined in the URL request.
  #
  # Returns a User instance if found.
  def find_user
    exec_context.user
  end

  # Public: Selects the User defined in the URL request.
  #
  # Returns a User instance or halts with 404 if not found.
  def find_user!
    record_or_404 find_user
  end

  def this_user
    path = (params[:user] || params[:username]).to_s
    user = User.find_by_login(path)
    record_or_404 user
  end

  # Deprecated: Use #find_org instead.
  def this_organization
    record_or_404 find_org_by_login
  end

  # Public: Select the Audit Log Stream Configuration ID in the URL request.
  #
  # Returns an AuditLogStreamConfiguration or halts with 404 if not found
  def find_audit_log_stream_configurations!
    record_or_404 find_audit_log_stream_configurations
  end

  # Public: Select the Audit Log Stream Configuration ID in the URL request.
  #
  # Returns an AuditLogStreamConfiguration instance or nil
  def find_audit_log_stream_configurations
    if params[:stream_id].present?
      stream_id = params[:stream_id].to_i
      return AuditLogStreamConfiguration.find_by(id: stream_id, business_id: find_enterprise!.id)
    end
    @current_enterprise.audit_log_stream_configurations
  end

  # Public: Selects the Organization defined in the URL request.

  #
  # Returns an Organization instance, or nil.
  def find_org
    # TODO: @current_org should not be memoized at this level but some code is depending on it
    # so for now we keep it.
    @current_org ||= exec_context.organization
  end

  # Public: Selects the Organization defined in the URL request.
  #
  # Halts with 404 if no Organization is found.
  # Returns an Organization instance.
  def find_org!
    record_or_404(find_org)
  end

  def find_enterprise
    @current_enterprise ||= exec_context.business
  end

  # Public: Finds the Enterprise defined in the URL
  #
  # Halts with 404 if no Enterprise is found.
  # Returns an Enterprise instance.
  def find_enterprise!(error_options: {})
    record_or_404(find_enterprise, error_options: error_options)
  end

  # Public: Finds the Custom Organization Role defined in the URL
  #
  # Halts with 404 if no Custom Organization Role is found.
  # Returns an OrganizationRole instance.
  def find_custom_org_role!
    record_or_404(find_custom_role_by_id_and_organization)
  end

  # Finds a role based on id and org owner and validates it is a custom role
  def find_custom_role_by_id_and_organization
    role_id = int_id_param!(key: :role_id)
    org = Organization.find_by(id: int_id_param!(key: :organization_id))
    role = OrganizationRole.custom_roles_for_org(org).find_by(id: role_id)
    return nil unless role&.custom?
    role
  end

  # Public: Finds the Organization Role defined in the URL
  #
  # Halts with 404 if no Organization Role is found.
  # Returns an OrganizationRole instance.
  def find_org_role!
    record_or_404(find_org_role_by_id)
  end

  # Public: Selects the Team by ID defined in the URL request.
  #
  # Returns a Team instance.
  def find_team(param_name: :team_id, org_param_name: :org_id)
    Team.find_by(id: int_id_param!(key: param_name), organization_id: int_id_param!(key: org_param_name))
  end

  # Public: Selects the Team by ID defined in the URL request.
  #
  # Halts with 404 if no Team is found.
  # Returns a Team instance.
  def find_team!(param_name: :team_id, org_param_name: :org_id)
    record_or_404(find_team(param_name: param_name, org_param_name: org_param_name))
  end

  # Public: Selects the EnterpriseTeam by ID defined in the URL request.
  #
  # Returns an EnterpriseTeam instance.
  def find_enterprise_team(param_name: :team_id)
    business = find_enterprise!
    EnterpriseTeam.find_by(id: int_id_param!(key: param_name), business_id: business.id)
  end

  # Public: Selects the EnterpriseTeam by ID defined in the URL request.
  #
  # Halts with 404 if no EnterpriseTeam is found.
  # Returns an EnterpriseTeam instance.
  def find_enterprise_team!(param_name: :team_id, error_options: {})
    record_or_404(find_enterprise_team(param_name: param_name), error_options: error_options)
  end

  # Public: The REST implementation of the App::IContext based on the current request.
  sig { override.returns(App::IContext) }
  def exec_context
    @exec_context ||= App::RestContext.new(app: T.cast(self, App::IController))
  end

  private

  # Private: Selects the Organization defined in the URL request.
  def find_org_by_login
    login = params[:org].to_s
    login.present? && Organization.find_by_login(login)
  end

  # Finds an org role based on id
  def find_org_role_by_id
    role_id = int_id_param!(key: :role_id)
    org =  Organization.new(id: int_id_param!(key: :organization_id))

    # look for custom role first
    role = OrganizationRole.custom_roles_for_org(org).find_by(id: role_id)
    # if not found, look for system role
    if !role
      role = OrganizationRole.visible_preset_roles(org).find_by(id: role_id)
    end

    role
  end

  # Internal: Selects the Repository defined in the URL of all Repository paths:
  #
  #   /repositories/:repository_id
  #
  # Returns a Repository instance, or nil.
  def find_repo
    # TODO: we still cache @current_repo here to maintain existing behaviour. If you are reading this and like good code
    # please consider removing the `@current_repo ||= ` part of the next line and making things work better.
    @current_repo ||= exec_context.repository
  end

  # Internal: Finds the org owner (if any) for the current resource.
  #
  # Returns an Organization instance, a Business (Enterprise) instance, or nil.
  def current_resource_org_or_biz_owner
    return @current_org if @current_org
    return @current_enterprise if @current_enterprise

    if repo = find_repo
      repo.owner if repo.owner&.organization?
    end
  end

  # Internal: Updates the API url to redirect to the given repository. See
  # #this_repo.
  #
  # path            - String API request path.
  # requested_nwo   - String "user/repo" for the old repository.
  # redirected_repo - The Repository record that is being redirected to.
  #
  # Returns a fixed String API path for the repository.
  def this_repo_redirection(path, requested_nwo, redirected_repo)
    path.sub(requested_nwo, redirected_repo.name_with_owner_for_api)
  end
end
