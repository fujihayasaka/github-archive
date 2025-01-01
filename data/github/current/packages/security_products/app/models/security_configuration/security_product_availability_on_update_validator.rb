# typed: strict
# frozen_string_literal: true

class SecurityConfiguration::SecurityProductAvailabilityOnUpdateValidator < ActiveModel::Validator
  extend T::Sig

  sig { params(config: SecurityConfiguration).void }
  def validate(config)
    SecurityProductsEnablement::SecurityProductsManager.new.services.each do |feature, is_installed|
      next if is_installed

      if config.attribute_changed?(feature)
        next if config.ghas_is_being_disabled? && config[feature] == "disabled" # allow disabling if GHAS is being disabled
        config.errors.add feature, "enablement for uninstalled #{feature} can not be changed"
      end
    end
  end
end
