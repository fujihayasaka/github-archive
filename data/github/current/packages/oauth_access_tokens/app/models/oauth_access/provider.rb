# typed: true
# frozen_string_literal: true

# Public: Interface for finding or creating OauthAccess records.
module OauthAccess::Provider
  extend ActiveSupport::Concern
  extend T::Helpers

  abstract!

  sig { abstract.returns(ActiveRecord::Associations::CollectionProxy) }
  def accesses; end

  # Finds an OauthAccess by its temporary code.
  #
  # code    - String code of a matching OauthAccess.
  #
  # Returns authorized OauthAccess if a matching record is found.
  # Returns nil if nothing is found.
  def access_for_code(code)
    return nil if code.blank? || code == 0

    code = code.to_s
    return unless GitHub::UTF8.valid_unicode3?(code)

    access = accesses.find_by(code: code)
    return nil unless access

    # In order to prevent a race condition where clients are trying
    # to use the same code we invalidate the code as soon as possible
    #
    # See https://github.com/github/ecosystem-apps/issues/1716#issuecomment-960178773
    access.update(code: nil); access.reload

    return nil if access.created_at < OauthAccess::CODE_EXPIRY.ago
    access
  end

  # Creates an OauthAccess for the given user.  This OauthAccess is still
  # unauthorized (it has a `nil` token), but comes ready with a temporary code.
  #
  # user    - User that is accessing the current OauthApplication.
  # options - Hash of OAuth2-specific options for this user's access permissions.
  #           :scope                      - String comma separated list of granted
  #                                         scopes: "user,repo" (optional).
  #           :requested_scope            - String comma separate list of requested
  #                                         scopes: "user,repo" (optional).
  #           :integration_version_number - String representing the Integration
  #                                         version number that should be assigned
  #                                         to the OAuthAccess
  #           :user_session               - A UserSession for the given `user`.
  #           :redirect_uri               - Persists the redirect URI on the Access to
  #                                         be verified during the code exchange.
  #           :entry_point                - The entry point to log with Permission Cluster Activity (optional).
  # Returns newly created OauthAccess record.
  def grant(user, options = nil)
    options ||= {}

    access = accesses.
      build(user: user).
      grant(options[:scope], options[:requested_scope], options[:integration_version_number], options[:redirect_uri], options[:entry_point])

    # Skip Organization::CredentialAuthorizations for internal apps configured to
    return access if Apps::Privileged.capable?(:skip_oauth_organization_credential_authorizations, app: access.application)

    # Grant Organization::CredentialAuthorizations for each organization
    # that has an active external identity.
    if (user_session = options[:user_session])
      return access if user != user_session.user

      filter = ConditionalAccess::Model::Filter.new(self, web_session: user_session, actor: user, location: :model) # rubocop:todo GitHub/DoNotInstantiatePlatformObjects
      authorized_orgs = filter.satisfied_resources(user.organizations, only: :saml)

      authorized_orgs.in_groups_of(100, false) do |organizations|
        Organization::CredentialAuthorization.grant_in_bulk(organizations: organizations, credential: access, actor: user)
      end
    end

    access
  end

  # Creates an OauthAccess for the given user with a scoped installation.
  # This OauthAccess is authorized (it has a `nil` token), but comes ready with a temporary code.
  #
  # access  - The OauthAccess that is used for making the subsequent new OauthAccess.
  # target  - The target resource that the installation is scoped to.
  # permissions    - Hash of permissions to limit the installation.
  #                  permissions: { "metadata" => :read } (optional).
  # resources      - Hash of different resources
  #                  :repository_ids - The Array of Integer IDs used to limit the repository
  #                                    access on the installation.
  #                                    repository_ids: [8,6,7,5] (optional).
  #
  # entry_point - The entry point to log with Permission Cluster Activity (optional).
  #
  # Returns an Array.
  def grant_scoped_access_from(access, target, permissions: nil, resources: { repository_ids: nil }, entry_point: nil)
    if access.installation
      return invalid_token_error
    end

    new_access = grant(access.user, integration_version_number: access.authorization.integration_version.number, entry_point: entry_point)

    # Bless the new access with a credential authorization to
    # the target that the old one had.
    if saml_enforcement_policy?(access, target) && active_organization_credential_authorization?(access: access, target: target, resource: target)
      authorization = Organization::CredentialAuthorization.grant(
        organization: target,
        credential: new_access,
        actor: new_access.user,
      )

      if authorization.nil?
        new_access.destroy
        return token_creation_failure_error
      end
    end

    _, error = grant_scoped_installation_on(
      new_access,
      target,
      permissions: permissions,
      repository_ids: resources[:repository_ids],
      entry_point: entry_point
    )

    if error
      new_access.destroy
      return [nil, error]
    end

    new_access.reload
    [new_access, nil]
  end

  # Creates an single repository scoped installation on the given OauthAccess.
  #
  # access  - The OauthAccess that is used for making the subsequent new OauthAccess.
  # options - Hash of options the installation bound to the OauthAccess.
  #           :repository_id  - The primary of the ID to scope the installation to.
  #                             repository_id: 1 (optional).
  #           :request_elevated_read_access — Whether the installation should have read permissions extended to the
  #                                             repository owner's other repositories, when the repo scoped here is trusted.
  # Returns an Array.
  def grant_repository_scoped_installation_on(access, repository_id: nil, request_elevated_read_access: false, entry_point: nil)
    return bad_verification_code_error if access.nil?
    return invalid_token_error if access.installation

    if repository_id.nil?
      # TODO: Could this just be `installed_globally`? as global apps should
      # never be able to create user to server tokens? :thinking:
      if Apps::Privileged.capable?(:per_repo_user_to_server_tokens_required, app: self)
        return missing_repository_error
      end

      # If a repository_id is not passed and the app doesn't require it,
      # we should silently pass through as nothing failed.
      return [nil, nil]
    end

    repository = Repository.find_by(id: repository_id)

    user = access.user

    return repository_not_found_error unless repository
    return repository_not_found_error unless repository.readable_by?(user)

    access, error = grant_scoped_installation_on(
      access, repository.owner,
      permissions: nil,
      repository_ids: [repository.id],
      request_elevated_read_access: request_elevated_read_access,
      entry_point: entry_point
    )
    return [nil, error] if error

    access.reload
    [access.installation, nil]
  end

  private

  def create_scoped_installation(target, permissions:, repository_ids:, request_elevated_read_access: false, entry_point: nil)
    T.bind(self, Integration)

    result = if Apps::Privileged.capable?(:installed_globally, app: self)
      attributes = {
        permissions: permissions,
        repositories: repositories_for(installation: GlobalIntegrationInstallation.new(self, target), repository_ids: repository_ids),
        expires: false,
        elevated_read_access_on_target: request_elevated_read_access,
        entry_point: entry_point
      }

      SiteScopedIntegrationInstallation::Creator.perform(self, target, **attributes)
    else
      installation = IntegrationInstallation.with_target(target).find_by(integration: self)
      return missing_installation_error unless installation

      repositories = repositories_for(installation: installation, repository_ids: repository_ids)
      ScopedIntegrationInstallation::Creator.perform(
        installation,
        permissions: permissions,
        repositories: repositories,
        expires: false,
        entry_point: entry_point)
    end

    if result.success?
      return [result.installation, nil]
    end

    installation_failure_error(result)
  end

  def ensure_organization_credential_authorized(access:, target:, resource:)
    return unless saml_enforcement_policy?(access, target)
    return if active_organization_credential_authorization?(access: access, target: target, resource: resource)

    sso_required_error
  end

  def active_organization_credential_authorization?(access:, target:, resource:)
    credential = if target&.business&.feature_enabled?(:saml_scope_private_resources_to_org)
      Organization::CredentialAuthorization.by_resource(resource: resource, credential: access, repo: nil, org: target).first
    elsif target&.business&.feature_enabled?(:saml_scope_private_resources_to_org_experiment)
      run_saml_scope_experiment(resource, target, access)
    else
      Organization::CredentialAuthorization.by_repository(credential: access, repo: nil, org: target).first
    end

    credential && credential.active?
  end

  # This is a temporary method to run the experiment for fixing a bug for SAML authorized access tokens
  # Issue: https://github.com/github/authorization/issues/3437
  # The proposed changes can break workflows of customers who are relying on the current behaviour
  # where a token for SAML-org-A can access private resources of SAML-org-B if they are in the same enterprise
  #
  # We are using a Feature Flag to control the experiment because we want finer control over the rollout and send mismatches to Splunk
  # The experiment is expected to return missmatches, to allow us identify how ofthen the new behaviour would
  # break user experience and give users via the audit-log the ability to self-audit and update their access tokens
  def run_saml_scope_experiment(resource, org, oauth)
    # Using match to send mismatch logs
    match = T.let(true, T::Boolean)
    control = Organization::CredentialAuthorization.by_repository(credential: oauth, repo: nil, org: org)

    # return early if the request doesn't match experiment expectations
    return control.first unless org.present? && org.business.present? && (org.saml_sso_enabled? || org.business.saml_sso_enabled?)

    candidate = Organization::CredentialAuthorization.by_resource(resource: resource, credential: oauth, repo: nil, org: org).first

    match = control.empty? ? candidate.nil? : control.include?(candidate)
    unless match
      application_type = oauth.application_type
      if application_type == "OauthApplication" && oauth.application_id == 0
        application_type = "Classic PAT"
      end
      logs = {
        "code.namespace" => "OauthAccess::Provider",
        "code.function" => "get_credential_authorization_experiment",
        "gh.request_id" => GitHub.context[:request_id],
        "gh.business.id" => org&.business&.id,
        "gh.business.name" => org&.business&.slug,
        "gh.organization.id" => org&.id,
        "gh.organization" => org&.display_login,
        "gh.repository.id" => @current_repo&.id,
        "gh.oauth_access.id" => oauth.id,
        "gh.oauth_access.type" => application_type,
        "gh.oauth_access.user.id" => oauth.user.id,
        "gh.oauth_access.user.login" => oauth.user.display_login,
        "gh.oauth_access.is_application" => oauth.is_application || false,
        "gh.oauth_access.application.id" => oauth&.application&.id,
        "gh.oauth_access.application.name" => oauth&.application&.name,
        "gh.oauth_access.installation.id" => oauth.installation_id,
        "gh.oauth_access.installation.type" => oauth.installation_type,
        "gh.external_identities.resource_type" => resource.class.name,
        "gh.saml_credential.experiment.controls" => control.as_json(only: [:id, :organization_id, :credential_id, :credential_type, :actor_id, :actor_type]),
        "gh.saml_credential.experiment.candidate" => candidate&.as_json(only: [:id, :organization_id, :credential_id, :credential_type, :actor_id, :actor_type]) || "nil",
        "http.route" => GitHub.context[:api_route],
        "http.method" => GitHub.context[:request_method]
      }
      GitHub.logger.info("SAML Scope experiment mismatch", logs)
    end
    control.first
  end

  def grant_scoped_installation_on(access, target, permissions:, repository_ids:, request_elevated_read_access: false, entry_point: nil)
    saml_error = ensure_organization_credential_authorized(access: access, target: target, resource: nil)
    return saml_error if saml_error

    installation, error = create_scoped_installation(
      target,
      permissions: permissions,
      repository_ids: repository_ids,
      request_elevated_read_access: request_elevated_read_access,
      entry_point: entry_point
    )
    return [nil, error] if error

    access.update(installation: installation)
    access.reload

    [access, nil]
  end

  def saml_enforcement_policy?(access, target)
    return false unless Apps::Privileged.capable?(:saml_sso_required, app: self)
    return false unless target.organization?
    return false unless access.saml_enforceable?

    saml_enforcement_policy = Organization::SamlEnforcementPolicy.new(organization: target, user: access.user)
    return false unless saml_enforcement_policy.enforced?

    saml_enforcement_policy.enforced?
  end

  def repositories_for(installation:, repository_ids:)
    case installation
    when GlobalIntegrationInstallation
      unless repository_ids
        return SiteScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_REPOSITORIES
      end

      Repository.where(id: repository_ids)
    when IntegrationInstallation
      if repository_ids
        return Repository.where(id: repository_ids)
      end

      if installation.installed_on_all_repositories?
        return ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_REPOSITORIES
      end

      installation.repositories
    else
      []
    end
  end

  ##########
  # Errors #
  ##########

  def bad_verification_code_error
    [
      nil,
      {
        error: :bad_verification_code,
        error_description: "The code passed is incorrect or expired.",
        error_uri: OauthAccessTokenRequest::BAD_VERIFICATION_CODE,
      }
    ]
  end

  def token_creation_failure_error
    [
      nil,
      {
        error: :token_creation_failure,
        error_description: "We failed to grant the token access to the resource(s) requested.",
        error_uri: "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/",
      }
    ]
  end

  def installation_failure_error(result)
    [
      nil,
      {
        error: :installation_creation_failed,
        error_description: result.error,
        error_uri: "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/",
      },
    ]
  end

  def invalid_token_error
    [
      nil,
      {
        error: :invalid_token,
        error_description: "A scoped token cannot create another scoped token.",
        error_uri: "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/",
      },
    ]
  end

  def missing_installation_error
    [
      nil,
      {
        error: :installation_missing_access,
        error_description: "Your app does not have access to the given target.",
        error_uri: "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/",
      },
    ]
  end

  def missing_repository_error
    [
      nil,
      {
        error: :missing_repository,
        error_description: "This application requires that a repository is provided to redeem the OAuth token.",
        error_uri: "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/",
      },
    ]
  end

  def repository_not_found_error
    [
      nil,
      {
        error: :repository_not_found,
        error_description: "The repository requested could not be found.",
        error_uri: "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/",
      },
    ]
  end

  def sso_required_error
    [
      nil,
      {
        error: :sso_required,
        error_description: "Resource protected by Organization SAML enforcement",
        error_uri: "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/",
      },
    ]
  end
end
