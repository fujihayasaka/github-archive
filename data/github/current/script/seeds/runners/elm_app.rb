# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class ElmApp < Seeds::Runner
      APP_NAME = "ELM Smoke Test"
      DEFAULT_OUTPUT_DIR = File.join(Rails.root, "tmp", "elm-smoke-test")
      DESIRED_PERMISSIONS = { "enterprise_live_migrations" => :write, "contents" => :write, "workflows" => :write }.freeze
      DESIRED_PERMISSIONS_NO_WORKFLOWS = DESIRED_PERMISSIONS.except("workflows").freeze

      def self.help
        <<~HELP
Create a GitHub App with enterprise_live_migrations and contents permissions,
install it on the avocado-gmbh enterprise and an org. Writes the private
key and env config needed to run the ELM app-auth smoke tests.

Output (default #{DEFAULT_OUTPUT_DIR}):
  <output-dir>/elm-smoke-test.pem    - RSA private key (PEM)
  <output-dir>/.env.app-auth-smoke   - env vars for the smoke tests

Usage:
  bin/seed elm_app
  bin/seed elm_app --output-dir /workspaces/migrations-vnext
  bin/seed elm_app --force          # recreate installations and keys
  bin/seed elm_app --no-workflows   # omit workflows permission (for testing)
        HELP
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.run(options = {})
        output_dir = options[:output_dir] || DEFAULT_OUTPUT_DIR
        force = options[:force]
        no_workflows = options[:no_workflows]

        business = Seeds::Objects::Business.avocado_gmbh
        raise Seeds::Runner::RunnerError, "Enterprise not found. Run multi-tenant seeds first." unless business

        admin = business.owners.first
        raise Seeds::Runner::RunnerError, "No owner found for enterprise '#{business.slug}'." unless admin

        permissions = no_workflows ? DESIRED_PERMISSIONS_NO_WORKFLOWS : DESIRED_PERMISSIONS
        app = find_or_create_app(business, permissions)
        ensure_permissions(app, permissions)
        enterprise_installation = install_on_enterprise(app, business, admin, force: force)
        org, org_installation = install_on_org(app, business, force: force)
        pem_path, env_path = write_credentials(
          app, enterprise_installation, org_installation, org,
          admin: admin, business: business, output_dir: output_dir, force: force,
        )

        STDERR.puts <<~MSG
          ELM Smoke Test app created successfully!

          App ID:                    #{app.id}
          Client ID:                 #{app.key}
          Enterprise Installation:   #{enterprise_installation.id}
          Org Installation:          #{org_installation.id}
          Private key:               #{pem_path}
          Env file:                  #{env_path}
        MSG
      end

      class << self
        private

        def find_or_create_app(business, permissions)
          slug = APP_NAME.parameterize
          app = ::Integration.find_by(slug: slug)
          return app if app

          app = Seeds::Objects::Integration.create(
            owner: business,
            app_name: APP_NAME,
            permissions: permissions,
            events: [],
            integration_url: "http://localhost:4567",
            install_automatically: false,
            visibility: :internal_visibility,
          )
          raise Seeds::Objects::CreateFailed, "Failed to create integration" unless app.persisted?

          app
        end

        def ensure_permissions(app, permissions)
          version = app.latest_version
          current_perms = version.default_permissions
          return if current_perms == permissions

          STDERR.puts "Updating app permissions: #{current_perms.inspect} -> #{permissions.inspect}"
          version.default_permissions = permissions
          version.save!
        end

        def install_on_enterprise(app, business, admin, force: false)
          if force && app.installed_on?(business)
            app.installations_on(business).destroy_all
          end

          Seeds::Objects::Integration.install(
            integration: app, repo: [], target: business, installer: admin,
          )
          app.installations_on(business).first
        end

        def install_on_org(app, business, force: false)
          org = business.organizations.detect { |o| o.admins.any? }
          raise Seeds::Runner::RunnerError, "No organization with admins found for enterprise '#{business.slug}'." unless org

          org_admin = org.admins.first
          raise Seeds::Runner::RunnerError, "No admin found for org '#{org.login}'." unless org_admin

          # The multi-tenant seeds add the org to business_organizations but don't always
          # set users.business_id. Installation token validation requires business_id to
          # match the enterprise for tenant scoping to pass. See the tenant validation
          # chain in Bots.domain.from_unhashed_token → valid_for_current_tenant? → resolve_tenant.
          if org.business_id != business.id
            org.update_columns(business_id: business.id, updated_at: Time.current)
          end

          if force && app.installed_on?(org)
            app.installations_on(org).destroy_all
          end

          Seeds::Objects::Integration.install(
            integration: app, repo: [], target: org, installer: org_admin,
          )
          [org, app.installations_on(org).first]
        end

        def write_credentials(app, enterprise_installation, org_installation, org, admin:, business:, output_dir:, force: false)
          FileUtils.mkdir_p(output_dir)

          pem_path = File.join(output_dir, "elm-smoke-test.pem")
          env_path = File.join(output_dir, ".env.app-auth-smoke")

          # Regenerate the key if forced, if the PEM file is missing, or if the app
          # has no keys in the database (e.g. after a `--reset` that wiped the DB
          # while the PEM file still existed on disk).
          if force || !File.exist?(pem_path) || IntegrationKey.where(integration_id: app.id).none?
            key = app.generate_key(creator: admin)
            File.open(pem_path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |f|
              f.write(key.private_key.to_pem)
            end
            File.chmod(0o600, pem_path)
          end

          env_content = <<~ENV
            APP_ID=#{app.id}
            APP_CLIENT_ID=#{app.key}
            APP_INSTALLATION_ID=#{enterprise_installation.id}
            ORG_INSTALLATION_ID=#{org_installation.id}
            APP_PRIVATE_KEY_PATH=#{pem_path}
            TARGET_ENTERPRISE=#{business.slug}
            TARGET_ORG=#{org.display_login}
            API_URL=http://api.#{business.slug}.ghe.localhost:80
            POLL_TIMEOUT=3m
          ENV

          File.write(env_path, env_content.gsub(/^ +/, ""))

          [pem_path, env_path]
        end
      end
    end
  end
end
