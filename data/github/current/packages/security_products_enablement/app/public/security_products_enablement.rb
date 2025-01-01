# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  extend GH::Domain::Registration

  register_domain SecurityProductsEnablement::Domain

  sig { params(business: Business).returns(T::Boolean) }
  def self.enterprise_configs_enabled?(business)
    GitHub.enterprise? ||
    SecurityCenter::FeatureFlagHelper.feature_flag(:enterprise_security_configurations, actors: [business])
  end
end
