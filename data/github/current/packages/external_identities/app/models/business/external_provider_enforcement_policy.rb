# typed: true
# frozen_string_literal: true

class Business::ExternalProviderEnforcementPolicy
  attr_reader :business, :user
  alias_attribute :target, :business

  def initialize(business:, user:)
    @user = user
    @business = business
  end

  def enforced?
    return @enforced if defined?(@enforced)
    @enforced = calculate_enforced
  end

  private

  # External session dependency is always enforced for enterprise managed business access except for anonymous users.
  def calculate_enforced
    return false unless @business && @user
    @business.enterprise_managed? && @business == @user.enterprise_managed_business && @business.external_provider_enabled?
  end
end
