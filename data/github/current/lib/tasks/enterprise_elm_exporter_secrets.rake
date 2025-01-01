# typed: true
# frozen_string_literal: true

namespace :enterprise do
  namespace :elm_exporter_secrets do
    task :create, [] => [:environment] do
      next unless GitHub.enterprise? || Rails.env.development?

      Apps::Privileged::ElmExporterSecrets.seed_database!
    end
  end
end
