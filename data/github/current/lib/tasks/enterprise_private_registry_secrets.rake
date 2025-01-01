# frozen_string_literal: true

namespace :enterprise do
  namespace :private_registry_secrets do
    task :create, [] => [:environment] do
      next unless GitHub.enterprise? || Rails.env.development?

      Apps::Privileged::PrivateRegistrySecrets.seed_database!
    end
  end
end
