# typed: true
# frozen_string_literal: true

module EnterpriseCloudOnboard
  class SecretProtectionTrial < SKUTrial

    SKU_NAME = "secret_protection"

    sig { params(batch_size: Integer).returns(T::Enumerator[T::Array[SecretProtectionTrial]]) }
    def self.active_trials(batch_size)
      self.active_trial_config_entries(sku_name: SKU_NAME, batch_size: batch_size).lazy.map do |configs|
        T.let(configs, T::Array[::Configuration::Entry])
        configs.select { |c| c.target }.map { |c| new(billable_entity: c.target) }
      end
    end

    sig { params(billable_entity: T.any(Business, Organization)).void }
    def initialize(billable_entity:)
      # SKUTrial's feature_is_in_use? needs SECRET_PROTECTION_VOLUME
      super(
        billable_entity: billable_entity,
        sku_name: SKU_NAME,
        advanced_security_enabled_type_volume: Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME
      )
    end

    # This must return the number of seats for this feature that are in use.
    sig { override.returns(Integer) }
    def seats_used
      @billable_entity.secret_protection.seats_used
    end
  end
end
