# typed: true
# frozen_string_literal: true

module EnterpriseCloudOnboard
  class CodeSecurityTrial < SKUTrial

    sig { params(billable_entity: Business, api_access: T::Boolean).void }
    def initialize(billable_entity:, api_access: false)
      super(billable_entity: billable_entity, api_access: api_access, sku_name: "code_security", advanced_security_enabled_type_volume: Configurable::AdvancedSecurityBillingConfig::CODE_SECURITY_VOLUME)
    end

    protected

    # This must return the number of seats for this feature that are in use.
    sig { override.returns(Integer) }
    def seats_used
      @billable_entity.code_security.seats_used
    end
  end
end
