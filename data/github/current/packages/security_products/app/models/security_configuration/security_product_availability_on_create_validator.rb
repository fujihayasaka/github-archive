# typed: strict
# frozen_string_literal: true

class SecurityConfiguration::SecurityProductAvailabilityOnCreateValidator < ActiveModel::Validator

  sig { params(config: SecurityConfiguration).void }
  def validate(config)
    SecurityProductsEnablement::SecurityProductsManager.new.services.each do |service, is_installed|
      next if service == :dependabot_vea || is_installed

      if config[service] != "disabled"
        config.errors.add service, "uninstalled product #{service} must be set to `disabled`"
      end
    end
  end
end
