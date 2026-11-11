# typed: true
# frozen_string_literal: true

class Business::SamlEnforcementPolicy
  attr_reader :business, :user
  alias_attribute :target, :business

  def initialize(business:, user:, organization: nil)
    @business = business
    @organization = organization
    @user = user
  end

  def self.filter_enforced(businesses, actor)
    return [] if GitHub.single_business_environment?
    return [] if businesses.empty?

    actor_business_ids = actor.businesses.pluck(:id)
    return [] if actor_business_ids.empty?

    enforced_ids = Business::SamlProvider.batched_scope(:business_id, values: actor_business_ids).pluck(:business_id)

    businesses.filter { |b| enforced_ids.include? b.id }
  end

  def enforced?
    return @enforced if defined?(@enforced)
    @enforced = calculate_enforced_with_oidc
  end

  private

  def calculate_enforced_with_oidc
    return false unless @business && @user
    return false unless @business.external_provider_enabled?

    exclusive_unaffiliated = false
    if @business.supports_unaffiliated_user_accounts? && !@business.enterprise_managed_user_enabled?
      exclusive_unaffiliated = @business.exclusive_unaffiliated_member?(@user)
      return false if !exclusive_unaffiliated && !@business.member?(@user)
    else
      return false unless @business.member?(@user)
    end

    return false if @organization&.user_is_outside_collaborator?(@user.id)
    return false if exclusive_unaffiliated && pending_outside_collaborator_invitation?

    if @business.saml_sso_enabled?
      return false unless @business.saml_sso_enforced?
    end

    true
  end

  # Exempt invitees accepting an outside-collaborator invitation. Without this, a residual
  # BusinessUserAccount from a former org membership forces SSO. Caller must have already
  # verified the user is an exclusive unaffiliated member of @business.
  def pending_outside_collaborator_invitation?
    return false unless @organization
    return false unless FeatureFlag.vexi.enabled?(:saml_exempt_pending_repo_invitee, @business, default: false)
    return false if @organization.member?(@user)

    RepositoryInvitation
      .for_invitee(@user.id)
      .for_organization_ids([@organization.id])
      .excluding_expired
      .exists?
  end
end
