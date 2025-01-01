# typed: true
# frozen_string_literal: true
class Api::RepositoryAdvisories < Api::App
  include Api::App::AdvisoryPaginationHelpers
  include Api::App::RepositoryAdvisoriesHelpers

  before do
    deliver_error! 404 unless current_repo.advisories_enabled?
  end

  sig { params(ghsa_id: String).returns(RepositoryAdvisory) }
  def find_advisory!(ghsa_id: params[:ghsa_id])
    advisory = RepositoryAdvisory.find_by(ghsa_id: ghsa_id, repository: current_repo)

    advisory || deliver_error!(404)
  end

  # This method exists because we don't want to leak an advisory's existence
  # to users who shouldn't know about it. We'll return an 404 instead of a 403 if the user
  # can't read the advisory.
  #
  # We also don't return 403s to OAuth apps. The OAuth apps auth matrix doesn't allow for
  # us to return both 403s or 404s so we'll err on the side of caution and only return 404s.
  def allow_forbid?(advisory)
    return false if current_user&.using_auth_via_oauth_application?

    advisory.readable_by?(current_user)
  end

  get "/repositories/:repository_id/private-vulnerability-reporting", operation_id: "repos/check-private-vulnerability-reporting" do
    @accepted_scopes = %w(repo)
    repo = find_repo!

    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if repo.archived? || !repo.public?
      deliver_error!(422, message: "Repository must be public and not archived")
    end

    deliver :private_vulnerability_reporting_hash, repo
  end

  # Disables private vulnerability reporting on a repository.
  delete "/repositories/:repository_id/private-vulnerability-reporting", operation_id: "repos/disable-private-vulnerability-reporting" do
    control_access :toggle_private_vulnerability_reporting,
      resource: current_repo,
      repo: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if current_repo.archived? || !current_repo.public?
      deliver_error!(422, message: "Repository must be public and not archived")
    end

    security_params = { private_vulnerability_reporting_enabled: "0" }
    _, error = SecurityProduct::ServiceManager.new(current_repo).toggle_services_with_form_inputs(current_user, params: security_params)
    if current_repo.private_vulnerability_reporting_enabled?
      deliver_error!(422, message: SecurityProduct::PrivateVulnerabilityReporting.error_to_message(error))
    end

    deliver_empty status: 204
  end

  # Enables private vulnerability reporting on a repo.
  put "/repositories/:repository_id/private-vulnerability-reporting", operation_id: "repos/enable-private-vulnerability-reporting" do
    control_access :toggle_private_vulnerability_reporting,
      resource: current_repo,
      repo: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if current_repo.archived? || !current_repo.public?
      deliver_error!(422, message: "Repository must be public and not archived")
    elsif AdvisoryDB::Innersource.repo_authorized?(repo: current_repo)
      deliver_error!(422, message: "Private Vulnerability Reporting cannot be enabled for innersource repositories")
    end

    security_params = { private_vulnerability_reporting_enabled: "1" }
    _, error = SecurityProduct::ServiceManager.new(current_repo).toggle_services_with_form_inputs(current_user, params: security_params)
    unless current_repo.private_vulnerability_reporting_enabled?
      deliver_error!(422, message: SecurityProduct::PrivateVulnerabilityReporting.error_to_message(error))
    end

    deliver_empty status: 204
  end

  # Gets a specific repository security advisory by ghsa_id
  get "/repositories/:repository_id/security-advisories/:ghsa_id", operation_id: "security-advisories/get-repository-advisory" do
    advisory = find_advisory!

    control_access :get_repository_advisory,
      resource: advisory,
      repo:  current_repo,
      forbid: allow_forbid?(advisory),
      forbid_message: "You must have the repository security advisories scope to view this advisory.",
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_advisory advisory
  end

  # Lists security advisories for a repository
  get "/repositories/:repository_id/security-advisories", operation_id: "security-advisories/list-repository-advisories" do
    control_access :list_published_repository_advisories,
      resource: current_repo,
      forbid: current_repo.public?,
      forbid_message: "You must have the repository security advisories scope to view advisories in this repo.",
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_non_conflicting_cursor_params!

    advisories = if access_allowed?(:list_unpublished_repository_advisories, resource: current_repo, allow_integrations: true, allow_user_via_granular_actor: true)
      current_repo.repository_advisories.limit_advisory_type.available_to(current_user)
    else
      current_repo.repository_advisories.limit_advisory_type.published
    end

    state = params[:state]&.to_sym
    if state
      advisories = advisories.state(state)
    end

    advisories = order_advisories(advisories)
    advisories_platform_relation = paginate_advisories(advisories, params)
    advisories = advisories_platform_relation.edge_nodes.sync
    set_cursor_based_pagination_headers(advisories_platform_relation) if advisories.any?

    deliver_advisories(advisories)
  rescue Platform::Errors::Cursor,
    Platform::Errors::ExcessivePagination,
    Platform::Errors::InvalidPagination => e

    deliver_error!(400, message: e.message)
  end

  # Creates a new repository security advisory
  post "/repositories/:repository_id/security-advisories", operation_id: "security-advisories/create-repository-advisory" do
    control_access :create_repository_advisory,
      repo: current_repo,
      forbid: current_repo.public?,
      forbid_message: "You must have the repository security advisories scope and administrative/security management rights to create an advisory.",
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    advisory = begin
                 RepositoryAdvisory.build_from_params(data, repo: current_repo, actor: current_user)
               rescue RepositoryAdvisory::ApiInvalidInputError => e
                 deliver_error!(422, message: e.message)
               end

    start_private_fork_after_create(advisory) if data["start_private_fork"]

    deliver_advisory advisory, 201
  end

  # Updates an existing repository security advisory
  patch "/repositories/:repository_id/security-advisories/:ghsa_id", operation_id: "security-advisories/update-repository-advisory" do
    advisory = find_advisory!

    control_access :update_repository_advisory,
      resource: advisory,
      repo: current_repo,
      forbid: allow_forbid?(advisory),
      forbid_message: "You must have the repository security advisories scope and be an advisory collaborator or have administrative/security management rights to update an advisory.",
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    begin
      advisory = advisory.update_from_params(data, actor: current_user)
    rescue RepositoryAdvisory::ApiInvalidInputError => e
      deliver_error!(422, message: e.message)
    rescue RepositoryAdvisory::ApiForbbidenActionError => e
      deliver_error!(403, message: e.message)
    end

    deliver_advisory advisory, 200
  end

  # Requests a CVE for a specific repository security advisory
  post "/repositories/:repository_id/security-advisories/:ghsa_id/cve", operation_id: "security-advisories/create-repository-advisory-cve-request" do
    advisory = find_advisory!

    control_access :create_cve_request,
      resource: advisory,
      repo: current_repo,
      forbid: allow_forbid?(advisory),
      forbid_message: "You must have the repository security advisories scope and have administrative/security management rights to create a CVE request.",
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if advisory.repository&.private?
      deliver_error(400, message: "Cannot request a CVE for an advisory that is in a private repository.")
    elsif RepositoryAdvisory::CVE.cve_requestable?(advisory)
      RepositoryAdvisory::CVE.request_cve(advisory, current_user)

      deliver_empty status: 202
    else
      deliver_error!(422, message: "Cannot request a CVE if the repository is private or the advisory is not open, is missing a description, severity, or vulnerability info, or if the advisory already has a CVE.")
    end
  end

  # Creates a temporary private fork (workspace) for a repository security advisory
  post "/repositories/:repository_id/security-advisories/:ghsa_id/forks", operation_id: "security-advisories/create-fork" do
    advisory = find_advisory!

    control_access :create_temporary_fork,
      resource: advisory,
      repo: current_repo,
      forbid: allow_forbid?(advisory),
      forbid_message: "You must have the repository security advisories permission and be a maintainer or reporter to create a fork.",
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(403, message: "Cannot add a repository to a security advisory once it is closed or published.") unless advisory.open?
    deliver_error!(403, message: "A repository already exists for this security advisory.") if advisory.workspace_repository
    deliver_error!(403, message: "Creating forks for archived repositories is not allowed.") if current_repo.archived?

    workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, current_user)

    deliver_error!(500, message: "Something went wrong. Please try again.") unless workspace_repo.persisted?

    GlobalInstrumenter.instrument("repository_advisory.workspace_open", {
      repository_advisory: advisory,
      actor: current_user,
    })

    deliver :full_repository_hash, workspace_repo, status: 202
  end

  # Creates a private vulnerability report for a repository.
  post "/repositories/:repository_id/security-advisories/reports", operation_id: "security-advisories/create-private-vulnerability-report" do
    control_access :create_private_vulnerability_report,
      repo: current_repo,
      forbid: current_repo.public?,
      forbid_message: "You must be authenticated to report a vulnerability. Actions require the Repository Advisories write scope.",
      enforce_oauth_app_policy: current_repo.private?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(403, message: "Repository does not have private vulnerability reporting enabled") unless AdvisoryDB::Pvd.authorized_repo?(repo: current_repo)
    deliver_error!(403, message: "You are not authorized to report advisories in this repository via private vulnerability reporting") unless AdvisoryDB::Pvd.authorized_user?(repo: current_repo, user: current_user)

    data = receive_with_openapi

    advisory = begin
                 RepositoryAdvisory.build_from_params(data, repo: current_repo, actor: current_user, external: true)
               rescue RepositoryAdvisory::ApiInvalidInputError => e
                 deliver_error!(422, message: e.message)
               end

    start_private_fork_after_create(advisory) if data["start_private_fork"]

    deliver_advisory advisory, 201
  end

  def start_private_fork_after_create(advisory)
    can_fork = access_allowed?(:create_temporary_fork, resource: advisory, repo: current_repo, allow_integrations: true, allow_user_via_granular_actor: true) &&
      advisory.open? &&
      !advisory.workspace_repository

    return unless can_fork

    workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, current_user)

    return unless workspace_repo.persisted?

    GlobalInstrumenter.instrument("repository_advisory.workspace_open", {
      repository_advisory: advisory,
      actor: current_user,
    })
  end

  def deliver_advisory(advisory, status = 200)
    options = {
      repo_advisory_writable: advisory.writable_by?(current_user),
      removed_pvr_author: !advisory.published? && advisory.user_is_pvd_submitter?(current_user) && !advisory.writable_by?(current_user),
      status: status,
      last_modified: calc_last_modified_for_object(advisory),
    }

    deliver :repository_advisory_hash, advisory, options
  end
end
