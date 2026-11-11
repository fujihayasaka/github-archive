# typed: true
# frozen_string_literal: true

namespace :enterprise do
  namespace :license_compliance do
    task :create, [] => [:environment] do
      next unless GitHub.single_or_multi_tenant_enterprise? || Rails.env.development?
      Apps::Privileged::LicenseCompliance.seed_database!
    end

    task :update, [] => [:environment] do
      next unless GitHub.single_or_multi_tenant_enterprise? || Rails.env.development?

      Apps::Privileged::LicenseCompliance.update_app!
    end

    task :upsert, [] => [:environment] do
      next unless GitHub.single_or_multi_tenant_enterprise? || Rails.env.development?

      app = Apps::Privileged.integration(:license_compliance)
      if app.present?
        Apps::Privileged::LicenseCompliance.update_app!
      else
        Apps::Privileged::LicenseCompliance.seed_database!
      end
    end
  end
end
