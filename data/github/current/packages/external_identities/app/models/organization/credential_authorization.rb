# typed: false
# frozen_string_literal: true

#
# This model tracks whether a credential has been granted access to an
# organization. An credential can be a personal access token or an oauth access
# token (both modeled by OauthAccess). It can be expanded to include other
# models such as public keys.
#
# See https://github.com/github/iam/blob/master/docs/adrs/adr-002-organization-saml-access-control-for-non-web-clients.md
class Organization::CredentialAuthorization < ApplicationRecord::Domain::Users
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification

  def event_prefix
    :org_credential_authorization
  end

  def event_payload
    {
      org: organization,
      credential_id: credential_id,
      credential_type: credential_type,
      actor_type: actor_type,
    }.tap do |p|
      if actor.is_a?(User)
        p[:actor] = actor
      else
        p[actor.event_prefix] = actor if actor
      end

      if using_public_key?
        p[:fingerprint] = fingerprint
      else
        if using_application_token?
          p[:oauth_credential_type] = "OauthAccess"
        elsif using_personal_access_token?
          p[:oauth_credential_type] = "Personal Access Token"
        end

        # Check the audit contexts to make sure this action isn't being done programmatically
        # We want to prioritize maintaining data about token usage in the audit log
        if Audit.context[:token_id].nil?
          p[:oauth_access_id] = credential_id
          p[:token_id] = credential_id
          p[:oauth_scopes] = credential&.scopes_string
          p[:token_scopes] = credential&.scopes_string
          p[:hashed_token] = credential&.hashed_token
        else
          p[:managed_oauth_access_id] = credential_id
          p[:managed_token_id] = credential_id
          p[:managed_oauth_scopes] = credential&.scopes_string
          p[:managed_token_scopes] = credential&.scopes_string
          p[:managed_hashed_token] = credential&.hashed_token
        end
      end
    end
  end

  self.table_name = :organization_credential_authorizations

  belongs_to :organization
  belongs_to :credential, polymorphic: true
  belongs_to :actor, polymorphic: true
  belongs_to :revoked_by, class_name: "User"

  validates :actor, presence: true
  validates :organization, presence: true
  validates :credential, presence: true

  validates :credential_id, uniqueness: { scope: [:credential_type, :organization_id, :actor_id, :actor_type] }

  validates :credential_type, inclusion: { in: %w[OauthAccess PublicKey], message: "must be an OauthAccess or PublicKey" }
  validate :validate_actor_is_member_of_organization, unless: [:revoked?, :using_application_token?]
  validate :validate_credential_is_owned_by_actor, unless: :using_application_token?
  validate :validate_credential_is_not_revoked, if: :using_public_key?

  before_create :set_is_application_value
  before_validation :set_fingerprint_sha256
  after_create_commit :instrument_grant
  after_destroy_commit :instrument_deauthorization

  scope :by_credential, -> (credential:) {
    fail "`credential` must not be a relation (cross-domain risk)" if credential.is_a?(ActiveRecord::Relation)
    where(credential: credential)
  }

  scope :by_organization, -> (organization:) {
    if organization.is_a?(Array)
      where(organization_id: organization.map(&:id))
    else
      where(organization_id: organization.id)
    end
  }

  scope :by_actor, -> (actor:) {
    where(actor_id: actor.id, actor_type: actor.class.name)
  }

  scope :by_organization_credential, -> (organization:, credential:) {
    by_organization(organization: organization).
    by_credential(credential: credential)
  }

  # Returns credential authorizations a credential has for any orgs within an Org's Business
  # rubocop:disable Lint/UnusedBlockArgument
  scope :by_organization_credential_with_same_business, -> (credential:, organization:, business:) {
    by_credential(credential: credential).
    where(organization_id: organization.business.organization_ids)
  }
  # rubocop:enable Lint/UnusedBlockArgument

  scope :excluding_organizations, -> (organization_ids:) {
    where("organization_credential_authorizations.organization_id NOT IN (?)", organization_ids)
  }

  scope :active, -> {
    where("revoked_by_id IS NULL")
  }

  scope :revoked, -> {
    where("revoked_by_id IS NOT NULL")
  }

  scope :public_key_credentials_by_fingerprint, -> (fingerprint_sha256:) {
    where(credential_type: "PublicKey", fingerprint_sha256: fingerprint_sha256)
  }

  scope :excluding_applications, -> {
    where(is_application: false)
  }

  def self.grant(organization:, credential:, actor:)
    authorization = create(organization: organization, credential: credential, actor: actor)
    return unless authorization.valid?

    authorization
  end

  def self.grant_in_bulk(organizations: [], credential:, actor:)
    rows = organizations.map do |organization|
      authorization = new(organization: organization, credential: credential, actor: actor)
      next unless authorization.valid?

      # The is_application value is set after validation, but before save.
      authorization.set_is_application_value

      {
        organization_id: organization.id,
        credential_id: credential.id,
        credential_type: credential.class.name,
        actor_id: actor.id,
        actor_type: actor.class.name,
        fingerprint_sha256: authorization.fingerprint_sha256,
        is_application: authorization.is_application,
      }
    end.compact

    return if rows.empty?

    ActiveRecord::Base.connected_to(role: :writing) do
      insert_all(rows)

      # The :returning KWARG is not supported by the MySQL adapter. So we have
      # query the records created by other means.
      organization_ids = rows.map { |row| row[:organization_id] }

      if actor.is_a?(User) && (FeatureFlag.vexi.enabled?(:use_instrument_bulk_credential_authorization_grants_job, actor, default: false) || FeatureFlag.vexi.enabled?(:use_instrument_bulk_credential_authorization_grants_job, actor.enterprise_managed_business, default: false))
        InstrumentBulkCredentialAuthorizationGrantsJob.perform_later(organization_ids: organization_ids, credential_id: credential.id, credential_type: credential.class.name)
      else
        # #insert_all does not perform ActiveRecord callbacks, so we need to
        # manually perform instrumentation.
        where(organization_id: organization_ids, credential: credential).map(&:instrument_grant)
      end
    end
  end

  def self.revoke(organization:, credential:, actor:)
    # Organization admins can revoke any authorized credentials on its org
    can_revoke ||= organization.resources.organization_administration.writable_by?(actor)

    # Admins of enterprise managed businesses can revoke any authorized credentials in the business
    can_revoke ||= (organization.enterprise_managed_user_enabled? \
      && organization.business.adminable_by?(actor))

    # Personal access tokens can be revoked by its owner
    can_revoke ||= (credential.personal_access_token? && credential.user == actor)

    return unless can_revoke

    if authorization = authorization(organization: organization, credential: credential)
      authorization.update(revoked_by_id: actor.id, revoked_at: Time.now)
      authorization.instrument :revoke, actor: actor, owner: authorization.actor
      authorization
    end
  end

  def self.authorization(organization:, credential:)
    return unless credential.present?

    active.by_organization_credential(organization: organization, credential: credential).first
  end

  # Public: Creates a signed auth token for the actor that stores a reference
  # to a credential. Currently, this is given to the actor in a URL if they
  # attempt to access SAML protected resources with a credential that has not
  # been authorized yet. The aforementioned URL can be visited to automatically
  # authorize the credential by verifying the auth token before it expires.
  #
  # organization - The organization that the credential will be authorized for.
  # target       - The organization or business used to create and validate the request scope.
  # credential   - The credential to be authorized.
  # actor        - The owner of the credential.
  #
  # Returns a String.
  def self.generate_request(organization:, target:, credential:, actor:)
    actor.signed_auth_token(
      scope: "saml:authorized_credential:#{target.class.name}:#{target.id}",
      expires: 1.hour.from_now,
      data: {
        organization_id: organization.id,
        credential_id: credential.id,
        credential_type: credential.class.name,
      },
    )
  end

  # Public: Verifies a signed auth token generated by `.sign_token`. The
  # verified token can be used to grant a credential access to an organization.
  #
  # target       - The organization or business that the token was generated for.
  # token        - The signed auth token string to be verified.
  # actor        - The credential owner to be verified.
  #
  # Returns a GitHub::Authentication::SignedAuthToken or nothing.
  def self.consume_request(target:, token:, actor:)
    parsed_token = User.verify_signed_auth_token(
      scope: "saml:authorized_credential:#{target.class.name}:#{target.id}",
      token: token,
    )

    return unless parsed_token.valid?
    return unless parsed_token.user == actor

    parsed_token
  end

  # Public: the set of credential authorizations that can be used to acces a given repository.
  #
  # repo         - The target repository. If nil, the behaviour is the same as by_organization_credential.
  # credential   - The auth token used in the request.
  # org          - The target organization that is expected to be linked to the auth token
  #                via a credential authorization.
  #
  # Returns an Organization::CredentialAuthorization ActiveRecord::Relation.
  def self.by_repository(repo:, credential:, org:)
    saml_satisfied_debug_logging("Check repo id", "by_repository", {
      "gh.repo.id": repo&.id,
    })
    scope =
      if scope_lookup_to_business?(repo: repo, business: org.business, credential: credential)
        saml_satisfied_debug_logging("scope_lookup_to_business? is true", "by_repository")
        # inner-source means enabling the PAT or SSH key for 1 org in the business
        # grants access to all internal repos in the business
        by_organization_credential_with_same_business(
          credential: credential,
          organization: org,
          business: org.business
        )
      else
        by_organization_credential(
          organization: org,
          credential: credential,
        )
      end
    scope.order(Arel.sql("CASE WHEN organization_credential_authorizations.revoked_by_id IS NULL THEN 0 ELSE 1 END"))
  end

  # Public: The set of credential authorizations that can be used to acces a
  # given resource.
  #
  # resource:    - The target resource.
  # credential   - The auth token used in the request.
  # repo         - The repository the target resource belongs to or nil if the
  #                resource belongs to no repository.
  # org          - The target organization that is expected to be linked to the
  #                auth token via a credential authorization.
  #
  # Returns an Organization::CredentialAuthorization ActiveRecord::Relation.
  def self.by_resource(resource:, credential:, repo:, org:)
    business = org.business

    # If the resource can identify itself as internal or public, check if the
    # specific request can be authorized with a credential from any org in the
    # business.
    scope_to_business = if is_resource_internal_or_public?(resource: resource, org: org)
      # If true, then use any org's credential. If false, we must use an
      # authorized credential for the owning org.
      scope_lookup_to_business_v2?(repo: repo, business: business, credential: credential)
    else
      # We cannot use any org's credential because this isn't an internal or
      # public resource.

      # Check to see if this is a private repo in a business that allows a
      # credential from any org to authorization accesss. In most cases this is
      # not true, but does exist for some businesses which have a specific
      # migration requirement.
      #
      # This essentially is checking a long-lived feature flag and should be
      # removed.
      #
      # See: https://github.com/github/1ES/issues/287
      scope_private_repo_to_business?(repo: repo, business: business, credential: credential)
    end

    scope = if business && scope_to_business
      # inner-source means enabling the PAT or SSH key for 1 org in the
      # business grants access to all internal repos in the business
      by_organization_credential_with_same_business(
        credential: credential,
        organization: org,
        business: business
      )
    else
      by_organization_credential(
        organization: org,
        credential: credential,
      )
    end

    # Order the results to have the authorized credentials first.
    scope.order(Arel.sql("CASE WHEN organization_credential_authorizations.revoked_by_id IS NULL THEN 0 ELSE 1 END"))
  end

  # Internal: Whether to scope credential authorization lookup to the Business
  # (use any authorization for any organization in the Business) or not for a
  # resource.
  #
  # Returns true if the resource is explicitly public or internal (public to the Enterprise)
  # and therefore a credential authorization for any org in the business is accepted
  # Otherwise, if the resource is private, a credential authorization specific to the resource's
  # owning organization is required
  def self.is_resource_internal_or_public?(resource:, org:)
    return false if resource.nil?

    case resource
    when Repository
      true if resource.internal? || resource.public?
    when Integration
      true if resource.public?
    when MemexProject
      # depends on https://github.com/github/memex/issues/18622
      true if resource.public? || (resource.org_owned? && resource.owner.same_business_as_org?(org))
    when Platform::PublicResource, Platform::InternalResource
      true
    else
      can_self_identify_internal_or_public = false
      internal_or_public = false

      # Check if this resource has a repository and if that repository is internal or public.
      if resource.respond_to?(:repository) && resource.repository.is_a?(Repository)
        can_self_identify_internal_or_public = true
        internal_or_public = resource.repository.internal? || resource.repository.public?
      end

      GitHub.logger.info(
        "Resource type not included in allowlist.",
        "code.function" => "Organization::CredentialAuthorization.scope_resource_to_business?",
        "gh.business.id" => org&.business&.id,
        "gh.org.id" => org&.id,
        "gh.external_identities.resource_type" => resource.class.name,
        "gh.external_identities.can_self_identify_internal_or_public" => can_self_identify_internal_or_public
      )

      internal_or_public
    end
  end

  # Internal: Whether to scope credential authorization lookup to the Business (find any
  # authorization for any organization in the Business) or not.
  #
  # Returns boolean whether to scope lookup to Business.
  def self.scope_lookup_to_business?(repo:, business:, credential: nil)
    # Internal repositories are scoped Business-wide
    return true if repo&.internal?
    # Public Business-owned repositories are scoped to the Business.
    return true if repo&.public? && business.present?
    # Scope to Business when a business is present and no repository is present.
    return true if repo.blank? && business.present?
    # Private Business-owned repositories are scoped to the Business (feature flagged)
    return true if credential && credential.respond_to?(:user) && FeatureFlag.vexi.enabled?(:sso_same_business_cred_authz_private_repos, credential&.user, default: false) && business.present? && repo&.private?
    # Otherwise, scope exclusively to the repository owner.
    false
  end

  # Private: Whether to scope credential authorization lookup to the Business (find any
  # authorization for any organization in the Business) or not.
  #
  # Returns boolean whether to scope lookup to Business.
  private_class_method def self.scope_lookup_to_business_v2?(repo:, business:, credential: nil)
    # Internal repositories are scoped Business-wide
    return true if repo&.internal?
    # Scope to Business when a business is present and no repository is present.
    return true if repo.blank? && business.present?
    # Public Business-owned repositories are scoped to the Business.
    return true if repo&.public? && business.present?
    # Otherwise, scope exclusively to the repository owner.
    false
  end

  # Private: Whether to allow business-owned private repositories to accept a
  # credential authorization from any organization.
  #
  # Returns true if a private repository can be accessed with a credential
  # authorization from any organization.
  private_class_method def self.scope_private_repo_to_business?(repo:, business:, credential:)
    # Private Business-owned repositories are scoped to the Business (feature flagged)
    credential &&
      credential.respond_to?(:user) &&
      FeatureFlag.vexi.enabled?(:sso_same_business_cred_authz_private_repos, credential&.user, default: false) &&
      business.present? &&
      repo&.private?
  end

  # Public: List all available organizations the actor can create/destroy an
  # authorization on.
  #
  # Returns an ActiveRecord::Relation.
  def self.available_organizations(actor)
    return Organization.none unless actor.instance_of?(User)

    unless actor.is_enterprise_managed?
      return Platform::Authorization::SAML.new(user: actor).saml_organizations # rubocop:todo GitHub/DoNotInstantiatePlatformObjects
    end

    # Since all organizations under EMU are enabled for SSO,
    # either through SAML setup or OIDC setup on an enterprise,
    # direct query can be executed, returning all of the organizations
    # that the user has access to
    organizations = actor.organizations

    organizations
  end

  # Public: whether or not this credential's authorization was revoked by an
  # organization administrator.
  #
  # Returns true if the authorization was revoked, false if not.
  def revoked?
    revoked_by_id.present?
  end

  # Public: whether or not this credential's authorization is active.
  #
  # Returns true if the authorization is active, false if not.
  def active?
    !revoked?
  end

  # Public: whether or not the credential is a token generated for use by an
  # OAuth Application.
  #
  # Returns true if `credential` is an application token, or false if it is a
  # personal access token or other type of object.
  def using_application_token?
    credential.is_a?(OauthAccess) && !credential.personal_access_token?
  end

  # Public: whether or not the credential is a token generated for use by an
  # Personal Access Token.
  #
  # Returns true if `credential` is a personal access token, or false if it is a
  # application token or other type of object.
  def using_personal_access_token?
    credential.is_a?(OauthAccess) && credential.personal_access_token?
  end

  # Public: whether or not the credential is an token generated for use by an
  # SSH key.
  #
  # Returns true if `credential` is a token for SSH key, or false if it is a
  # personal access token or other type of object.
  def using_public_key?
    credential_type == "PublicKey"
  end

  # Public: returns the last time the underlying credential was accessed
  #
  # Returns a ActiveSupport::TimeWithZone corresponding to the last time the credential was accessed
  # may be nil if the credential was never accessed
  def accessed_at
    credential&.last_access_time
  end

  # Public: returns the fingerprint in the format of ssh-keygen
  #
  # Returns the fingerprint in a format suitable to return to users in the UI or API.
  def fingerprint
    if GitHub.multi_tenant_enterprise?
      "SHA256:#{fingerprint_sha256.split("_")[0]}"
    else
      "SHA256:#{fingerprint_sha256}"
    end
  end

  # Internal: This method sets the de-normalized is_application value based on the credential
  #
  # Returns nothing
  def set_is_application_value
    # Because we can't join against the oauth_accesses table we have to de-normalize the value here in order to speed up queries
    return unless credential_type == "OauthAccess"

    self.is_application = credential&.application_id != 0
  end

  def instrument_grant
    GitHub.dogstats.increment("organization_credential_authorization", tags: ["action:grant"])
    instrument :grant
  end

  private

  def set_fingerprint_sha256
    if using_public_key?
      self.fingerprint_sha256 = credential.fingerprint_sha256
    end
  end

  def instrument_deauthorization
    GitHub.dogstats.increment("organization_credential_authorization", tags: ["action:deauthorize"])
    instrument :deauthorize
  end

  def validate_actor_is_member_of_organization
    return unless actor && organization

    unless organization.member?(actor)
      errors.add(:actor, "must be a member of organization")
    end
  end

  def validate_credential_is_owned_by_actor
    return unless actor && credential

    if actor != credential.user
      errors.add(:credential, "must be owned by actor")
    end
  end

  def validate_credential_is_not_revoked
    if self.class.by_organization(organization: organization).revoked.where(fingerprint_sha256: credential.fingerprint_sha256).any?
      errors.add(:credential, "has been revoked")
    end
  end

  private_class_method def self.saml_satisfied_debug_logging(msg, function, options = {})
    return unless FeatureFlag.vexi.enabled?(:saml_satisfied_debug_logging, default: false)
    GitHub.logger.info(
      msg,
      {
        "code.function": function,
        "gh.request_id": GitHub.context[:request_id],
         **options
      }
    )
  end
end
