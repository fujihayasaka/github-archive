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

    # This is an inner join, so it inherently filters out businesses with no SAML provider
    enforced_ids = actor.businesses.joins(:saml_provider).pluck(:id)
    businesses.filter { |b| enforced_ids.include? b.id }
  end

  def enforced?
    return @enforced if defined?(@enforced)
    @enforced = calculate_enforced
  end

  private

  def calculate_enforced
    return false unless @business && @user

    return true if @business.oidc_enabled? # OIDC is enabled for EMU businesses only; This policy is enforced for all users in OIDC businesses
    return false unless @business.saml_sso_enabled?
    if @business.supports_unaffiliated_user_accounts? && !@business.enterprise_managed_user_enabled?
      return false if !@business.exclusive_unaffiliated_member?(@user) && !@business.member?(@user)
    else
      return false unless @business.member?(@user)
    end
    return false if     @organization&.user_is_outside_collaborator?(@user.id)
    return false unless @business.saml_sso_enforced?

    true
  end
end
