# typed: strict
# frozen_string_literal: true

module SecretScanning::AccessControl
  class PublicMonitoring
    sig { params(business: Business, user: User).returns(T::Boolean) }
    def self.can_access?(business, user)
      SecurityProduct::Permissions::BusinessAuthz.new(business, actor: user).can_manage_enterprise_security_products?
    end
  end
end
