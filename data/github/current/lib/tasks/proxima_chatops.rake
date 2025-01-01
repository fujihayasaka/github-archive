# frozen_string_literal: true

namespace :proxima do
  namespace :chatops do
    task :create_teams, [:app_url, :webhook_url, :callback_url, :webhook_secret, :client_key, :client_secret, :public_key_file] => [:environment] do |_t, args|
      next unless GitHub.multi_tenant_enterprise?
      public_key = File.read(args[:public_key_file])

      Apps::Privileged::Msteams.seed_database!(
        app_url: args[:app_url],
        webhook_url: args[:webhook_url],
        callback_url: args[:callback_url],
        webhook_secret: args[:webhook_secret],
        insecure_ssl: 0,
        client_key: args[:client_key],
        client_secret: args[:client_secret],
        public_key: public_key)
    end

    task :update_teams, [:app_url, :webhook_url, :callback_url, :webhook_secret, :client_key, :client_secret, :public_key_file] => [:environment] do |_t, args|
      next unless GitHub.multi_tenant_enterprise?
      public_key = File.read(args[:public_key_file])

      Apps::Privileged::Msteams.update_app!(
        app_url: args[:app_url],
        webhook_url: args[:webhook_url],
        callback_url: args[:callback_url],
        webhook_secret: args[:webhook_secret],
        insecure_ssl: 0,
        client_key: args[:client_key],
        client_secret: args[:client_secret],
        public_key: public_key)
    end

    task :delete_teams, [] => [:environment] do |_t, _args|
      next unless GitHub.multi_tenant_enterprise?
      Apps::Privileged::Msteams.delete_app!
    end

    task :create_slack, [:app_url, :webhook_url, :callback_url, :webhook_secret, :client_key, :client_secret, :public_key_file] => [:environment] do |_t, args|
      next unless GitHub.multi_tenant_enterprise?
      public_key = File.read(args[:public_key_file])

      Apps::Privileged::Slack.seed_database!(
        app_url: args[:app_url],
        webhook_url: args[:webhook_url],
        callback_url: args[:callback_url],
        webhook_secret: args[:webhook_secret],
        insecure_ssl: 0,
        client_key: args[:client_key],
        client_secret: args[:client_secret],
        public_key: public_key)
    end

    task :update_slack, [:app_url, :webhook_url, :callback_url, :webhook_secret, :client_key, :client_secret, :public_key_file] => [:environment] do |_t, args|
      next unless GitHub.multi_tenant_enterprise?
      public_key = File.read(args[:public_key_file])

      Apps::Privileged::Slack.update_app!(
        app_url: args[:app_url],
        webhook_url: args[:webhook_url],
        callback_url: args[:callback_url],
        webhook_secret: args[:webhook_secret],
        insecure_ssl: 0,
        client_key: args[:client_key],
        client_secret: args[:client_secret],
        public_key: public_key)
    end

    task :delete_slack, [] => [:environment] do |_t, _args|
      next unless GitHub.multi_tenant_enterprise?
      Apps::Privileged::Slack.delete_app!
    end

    task :create_unfurl, [:app_url, :client_key, :client_secret, :public_key_file] => [:environment] do |_t, args|
      next unless GitHub.multi_tenant_enterprise?
      public_key = File.read(args[:public_key_file])

      Apps::Privileged::ChatopsUnfurl.seed_database!(
        app_url: args[:app_url],
        insecure_ssl: 0,
        client_key: args[:client_key],
        client_secret: args[:client_secret],
        public_key: public_key)
    end

    task :delete_unfurl, [] => [:environment] do |_t, _args|
      next unless GitHub.multi_tenant_enterprise?
      Apps::Privileged::ChatopsUnfurl.delete_app!
    end
  end
end
