# typed: true
# frozen_string_literal: true

class SshCertificateAuthority < ApplicationRecord::Collab
  SET_DEFAULT_MAX_SSH_CERT_LIFETIME_AFTER_DATE = Time.parse("2024-03-27T00:00:00Z")

  belongs_to :owner, polymorphic: true

  before_validation :set_fingerprint, on: :create
  after_create_commit :instrument_creation
  after_destroy_commit :instrument_deletion
  before_create :add_default_max_ssh_cert_lifetime

  validates :owner,              presence: true
  validates :openssh_public_key, presence: true
  validates :fingerprint,        presence: true
  validate :valid_owner_type
  validate :key_quality_check
  validate :uniqueness_of_openssh_public_key
  validate :validate_owner_is_eligible_for_feature

  # Cascading ownership, used for Configurable::SshCertificateRequirement.
  # Returns cas owned by object or by object's owners.
  scope :usable_for, ->(object) {
    case object
    when Repository
      usable_for(object.owner)
    when Organization
      usable_for(object.business).or(where(
        owner_type: object.class.base_class.name,
        owner_id: object.id,
      ))
    when Business
      where(
        owner_type: object.class.base_class.name,
        owner_id: object.id,
      )
    else
      where("1=0")
    end
  }

  def allowed_algos
    algos = [SSHData::PublicKey::ALGO_RSA, SSHData::PublicKey::ALGO_ECDSA256, SSHData::PublicKey::ALGO_ECDSA384,
      SSHData::PublicKey::ALGO_ECDSA521, SSHData::PublicKey::ALGO_SKECDSA256]
    unless GitHub.fips_mode?
      algos << SSHData::PublicKey::ALGO_ED25519
      algos << SSHData::PublicKey::ALGO_SKED25519
    end

    algos
  end

  # Is the given RSA key too weak to be used?
  #
  # parsed - An SSHData::PublicKey::Base subclass instance.
  #
  # Returns boolean.
  def self.weak_rsa_key?(parsed)
    return false unless parsed.algo == SSHData::PublicKey::ALGO_RSA
    parsed.openssl.params["n"].num_bits < 2048 || GitHub::SSH.weak_rsa_key?(parsed.openssl)
  end

  # Load the owner records for several CAs at onces. Ordinarily, we'd do a JOIN
  # on the query that loads the CA records, but they are in a different database
  # cluster than the orgs/enterprises.
  #
  # cas - An Array of SshCertificateAuthority instances.
  #
  # Returns nothing.
  def self.load_owners(cas)
    cas.group_by(&:owner_type).each do |owner_type, cas|
      owner_by_id = if owner_type == ::Business.name
        ::Business.where(id: cas.map(&:owner_id)).all.index_by(&:id)
      else
        ::Organization.where(id: cas.map(&:owner_id)).all.index_by(&:id)
      end

      cas.each do |ca|
        ca.owner = owner_by_id[ca.owner_id]
      end
    end
  end

  # Find orgs belonging to a business that have the cert requirement enabled
  sig { params(owner: Business).returns(T::Array[Integer]) }
  def self.cert_required_org_ids(owner)
    return [] unless owner.organization_ids.present?
    Configuration::Entry.targeting_user_ids(owner.organization_ids)
      .named(Configurable::SshCertificateRequirement::KEY)
      .with_true_value
      .pluck(:target_id)
  end

  # We don't want the user to delete their last SSH CA if they have the SSH
  # certificate authentication requirement enabled, as this could lead to a
  # confusing state.
  #
  # Because CAs and cert requiremnt can be configured at the business and
  # organization levels, we must be careful about how we decide whether a CA is
  # depended on for the cert requirement. In particular, a CA at the
  # organization level is only depended on if it is the last CA for the
  # organization and the organization has the cert requirement enabled. For a CA
  # at the businesses, this is more complicated since a CA at the business level
  # is inherrited by all organizations under the business. So, even if the
  # business doesn't have cert requirement enabled, a CA at the business level
  # _could_ be depended on if any organization under the business does have the
  # cert requirement enabled, but doesn't have any CAs added to the organization
  # directly.
  def depended_on_for_cert_requirement?
    # This org or business has more than one useable CA and doesn't rely on this
    # CA exclusively.
    return false if SshCertificateAuthority.usable_for(owner).count > 1

    # This is the last CA for this org or business and we require at least one
    # CA is configured to avoid confusing configurations where cert auth is
    # required but there are no CAs to use.
    return true if owner.ssh_certificate_requirement_enabled?

    # CAs at the organization level can only be depended on by the organization.
    # We know the cert requirement is disabled, so the CA is not relied on.
    return false if owner.is_a?(::Organization)

    # We know that the owner is a business and we know that the business doesn't
    # have cert requirement enabled. So, we must figure out if any organizations
    # currently have the cert requirement enabled and if they have no CAs
    # configured at the organization level (i.e. are dependent on this business
    # level CA)

    config_enabled_orgs = self.class.cert_required_org_ids(owner)

    # No orgs within this business have the cert requirement enabled, so nothing
    # depends on this CA.
    return false if config_enabled_orgs.empty?

    # Find orgs belonging to this business that have the cert requirement
    # enabled and have their own CA.
    orgs_with_cas = SshCertificateAuthority.where(
      owner_type: ::Organization.base_class.name,
      owner_id: config_enabled_orgs,
    ).distinct.pluck(:owner_id)

    # Find the orgs that have the cert requirement enabled but _don't_ have
    # their own CA.
    config_enabled_orgs_without_cas = config_enabled_orgs - orgs_with_cas

    # Any such orgs depend on _this_ CA.
    config_enabled_orgs_without_cas.any?
  end

  # Check if this CA is owned by an org or business without loading the
  # associated owner record.
  #
  # org_or_business - An Organization or Business instance.
  #
  # Returns boolean.
  def owned_by?(org_or_business)
    [org_or_business.class.base_class.name, org_or_business.id] == [owner_type, owner_id]
  end

  # SHA256 fingerprint encoded as base64. This matches the output of ssh-keygen.
  #
  # Returns a String fingerprint.
  def base64_fingerprint
    parsed_key.fingerprint
  end

  # Calcuate the key's fingerprint before validation.
  def set_fingerprint
    self.fingerprint = begin

      if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
        Base64.decode64(parsed_key.fingerprint << "_#{current_tenant.shortcode}")
      else
        Base64.decode64(parsed_key.fingerprint)
      end

    rescue SSHData::DecodeError, SSHData::AlgorithmError
      nil
    end
  end

  # Check that the owner is an Organization or Business. We don't use the Rails
  # `inclusion` validation because `owner_type` is actuall "User" for orgs.
  def valid_owner_type
    return if [Organization, Business].include?(owner.class)
    errors.add(:owner, "must be organization or business")
  end

  # Check that the certificate key isn't bad for a number of reasons:
  #   - An unsupported algorithm.
  #   - A known compromised key, where the private key was exposed
  #   - A easily factorable RSA key.
  #   - Too small of RSA key.
  #
  # Returns boolean.
  def key_quality_check
    if allowed_algos.exclude?(parsed_key.algo)
      errors.add(:openssh_public_key, "uses #{parsed_key.algo}, which is not supported")
    elsif GitHub::SSH.blocklisted_key?(parsed_key)
      errors.add(:openssh_public_key, "is blocked because its private key has been compromised")
    elsif self.class.weak_rsa_key?(parsed_key)
      errors.add(:openssh_public_key, "is too small or was generated unsafely. RSA keys must be 2048 bits or greater")
    end
  rescue SSHData::DecodeError, SSHData::AlgorithmError
    errors.add(:openssh_public_key, "is invalid")
  end

  # Check that the key is unique. We don't use the Rails `uniquenes` validation
  # because we want the error to be on the :key, rather than the :fingerprint.
  def uniqueness_of_openssh_public_key
    return unless errors[:openssh_public_key].empty?
    others = self.class.where(fingerprint: fingerprint)
    others = others.where.not(id: id) unless new_record?
    errors.add(:openssh_public_key, "is already in use") unless others.none?
  end

  # Does the owner's plan support this feature?
  #
  # Returns boolean.
  def self.eligible_for_feature?(owner)
    owner.is_a?(::Business) ||
      owner.plan_supports?(:ssh_certificates) ||
      grandfathered_into_feature?(owner)
  end

  GRANDFATHERED_ORG_IDS = if GitHub.enterprise?
    []
  else
    [
      538264,   # Uber
      856813,   # Stripe
      2387206,  # OpenSSH
      3028687,  # CloudTools
      3083516,  # Foobartestorg :-)
      23427221, # Latacora
    ]
  end

  # A few orgs helped us beta test this feature. They're allowed to continue
  # using the feature, regardless of their billing plan.
  def self.grandfathered_into_feature?(owner)
    owner.is_a?(::Organization) && GRANDFATHERED_ORG_IDS.include?(owner.id)
  end

  # Does the owner's plan support this feature?
  #
  # Returns boolean.
  def owner_is_eligible_for_feature?
    self.class.eligible_for_feature?(owner)
  end

  # Check that owner has a plan for which this feature is enabled.
  def validate_owner_is_eligible_for_feature
    unless owner_is_eligible_for_feature?
      errors.add(:owner, "doesn't have an eligible plan")
    end
  end

  # The name of the owner and it's type. This is useful for UI where we need to
  # talk about the "@github org" or "github-inc business"  that owns this CA.
  #
  # Return a String.
  def owner_name_and_type
    if owner_type == "Business"
      "#{owner.slug} enterprise"
    else
      "@#{owner.login} organization"
    end
  end

  def has_max_ssh_cert_lifetime?
    self.max_ssh_cert_lifetime_hours.present?
  end

  def set_default_max_ssh_cert_lifetime
    self.max_ssh_cert_lifetime_hours = GitAuth::SSHCertificateAuthority::DEFAULT_MAX_SSH_CERT_LIFETIME_IN_HOURS
    self.save
  end

  include Instrumentation::Model

  def event_payload
    {
      :ssh_certificate_authority => self,
      :openssh_public_key        => openssh_public_key,
      :fingerprint               => base64_fingerprint,
      owner.event_prefix         => owner,
    }
  end

  private

  def instrument_creation
    instrument :create
  end

  def instrument_deletion
    instrument :destroy
  end

  def parsed_key
    @parsed_key ||= SSHData::PublicKey.parse_openssh(openssh_public_key)
  end

  def add_default_max_ssh_cert_lifetime
    # for GHES and Proxima, we always set the default
    # for GHEC, we only set the default if the current date is after the date we want to start enforcing the default
    if GitHub.enterprise? || GitHub.multi_tenant_enterprise? || Time.now.utc >= SET_DEFAULT_MAX_SSH_CERT_LIFETIME_AFTER_DATE
      self.max_ssh_cert_lifetime_hours = GitAuth::SSHCertificateAuthority::DEFAULT_MAX_SSH_CERT_LIFETIME_IN_HOURS
    end
  end
end
