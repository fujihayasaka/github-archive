# typed: true
# frozen_string_literal: true

require "test_helper"

# This is a coupled mixin. It expects the including class to define the following:
# - fixtures do
#     make_trusted_oauth_apps_owner
#     make_proxima_third_party_apps_owner
#     @job_klass = ProximaAppSync::Create*PartyAppJob
#     @owner_id = @job_klass.new.owner_id
#   end
#
#   Test failures in packages/apps/test/jobs/proxima_app_sync/create_app_job_helper_test.rb
#   are produced by these test suites:
#   - CreateFirstPartyAppJobTest
#   - CreateThirdPartyAppJobTest
module CreateAppJobHelperTest
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  included do
    def build_internal_integration(name: "integration-#{SecureRandom.hex(8)}", key: SecureRandom.hex(8))
      secret = "33sfs33967a56"
      # We're building instead of persisting an integration here because the tests will create another
      # integration with the same name and we don't want the names to conflict in the DB.
      integration = build(
        :integration,
        id: 1,
        name: name,
        slug: name,
        owner_id: @owner_id,
        url: "http://example.com",
        setup_url: "http://example.com",
        deleted_at: Time.utc(2023, 7, 25),
        suspended_at: Time.utc(2023, 7, 25),
        user_suspended_by_id: @owner_id,
        request_oauth_on_install: true,
        user_token_expiration: 1,
        key: key,
        pinned_api_version: GitHub.api_versions.last,
        note: "Example Note",
        default_permissions: { "metadata" => :read, "single_file" => :read },
        default_events: ["label"],
        single_file_name: "example.txt",
        device_flow_enabled: true,
        application_callback_urls: [build(:application_callback_url, url: "https://example.com/callback")],
        hook: build(:hook, active: true, confirmed: true, pinned_api_version: GitHub.api_versions.last, secret: "Example Secret"),
        integration_install_triggers: [build(:integration_install_trigger, path: "https://example.com", reason: "Example Reason")],
        ip_allowlist_entries: [build(:ip_allowlist_entry, name: "Example IP Allowlist Entry", allow_list_value: "2001:db8::/48", range_from: " \x01\r\xB8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", range_to: " \x01\r\xB8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")],
        client_secrets: [build(:integration_client_secret, secret_hash: IntegrationClientSecret.hash_for(secret), secret_last_eight: secret.last(8))],
        public_keys: [build(:integration_key)],
        bot: build(:bot)
      )
      Apps::Internal::Registry.configure(
        app: integration,
        app_alias: integration.slug.to_sym,
        id: ->() { integration.id },
        capabilities: { proxima_first_party_sync: true },
        properties: { proxima_sync_delegate: :DefaultDelegate },
      )
      integration
    end

    def build_internal_oauth_application(name: "oauth-application-#{SecureRandom.hex(8)}", key: SecureRandom.hex(8))
      secret = "33sfs33967a56"
      # We're building instead of persisting an app here because the tests will create another
      # app with the same name and we don't want the names to conflict in the DB.
      oauth_application = build(
        :oauth_application,
        name: name,
        url: "http://example.com",
        key: key,
        user_id:  @owner_id,
        device_flow_enabled: true,
        client_secrets: [build(:oauth_application_client_secret, secret_hash: OauthApplicationClientSecret.hash_for(secret), secret_last_eight: secret.last(8))],
        application_callback_urls: [build(:application_callback_url, url: "https://example.com/callback"), build(:application_callback_url, url: "https://example.com/callback2")]
      )
      oauth_application.client_secrets.build(creator: oauth_application.user, secret_hash: "py78f7h5IXUL/3MqbxRAslb0AmNAGc6K0IXZ+8c5TEM=", secret_last_eight: "33967a56")
      Apps::Internal::Registry.configure(
        app: oauth_application,
        app_alias: oauth_application.name.to_sym,
        id: ->() { oauth_application.id },
        capabilities: { proxima_first_party_sync: true },
        properties: { proxima_sync_delegate: :DefaultDelegate },
      )
      oauth_application
    end

    def stub_proxima_integration_manifest_endpoint(app, with_latest_version: true)
      return_value = {
        "global_relay_id" => app.global_relay_id,
        "fingerprint" => app.synchronization_fingerprint,
        "type" => "Integration",
        "settings" => {
          "name" => app.name,
          "url" => app.url,
          "description" => app.description,
          "public" => app.public,
          "slug" => app.slug,
          "key" => app.key,
          "setup_url" => app.setup_url,
          "bgcolor" => app.bgcolor,
          "setup_on_update" => app.setup_on_update,
          "deleted_at" => app.deleted_at,
          "request_oauth_on_install" => app.request_oauth_on_install,
          "user_token_expiration" => app.user_token_expiration,
          "state" =>  app.state,
          "suspended_at" => app.suspended_at,
          "user_suspended_by_id" => app.user_suspended_by_id,
          "pinned_api_version" => app.pinned_api_version,
          "device_flow_enabled" => app.device_flow_enabled,
          "application_callback_urls" => [
            {
              "url" => app.application_callback_urls.first.url,
            }
          ],
          "public_keys" => [
            {
              "public_pem" => app.public_keys.first&.public_pem
            }
          ],
          "integration_install_triggers" => [
            "id" => nil,
            "path" => app.integration_install_triggers.first.path,
            "reason" => app.integration_install_triggers.first.reason,
            "install_type" => app.integration_install_triggers.first.install_type,
            "deactivated" => app.integration_install_triggers.first.deactivated
          ],
          "ip_allowlist_entries" => [
            {
              "allow_list_value" => app.ip_allowlist_entries.first.allow_list_value,
              "range_from" => app.ip_allowlist_entries.first.range_from,
              "range_to" => app.ip_allowlist_entries.first.range_to,
              "name" => app.ip_allowlist_entries.first.name,
              "active" => app.ip_allowlist_entries.first.active
            }
          ],
          "client_secrets" => [
            {
              "secret_hash" => app.client_secrets.first&.secret_hash,
              "secret_last_eight" => app.client_secrets.first&.secret_last_eight
            }
          ],
          "canonical_avatar_url" => app.primary_avatar_url,
          "owner" => {
            "dotcom_id" => app.owner.id,
            "dotcom_type" => app.owner.type,
            "dotcom_node_id" => app.owner.global_relay_id,
            "login" => app.owner.login,
            "display_login" => app.owner.display_login,
            "avatar_url" => app.owner.primary_avatar_url,
            "url" => app.url,
          }
        }
      }

      return_value["settings"]["latest_version"] = if with_latest_version
        {
          "note" => app.note,
          "default_permissions" => app.default_permissions,
          "default_events" => app.default_events,
          "single_file_name" => app.single_file_name
        }
      else
        nil
      end

      return_value["settings"]["hook"] = if app.hook
        {
          "active" => app.hook.active,
          "confirmed" => app.hook.confirmed,
          "pinned_api_version" => app.hook.pinned_api_version,
          "url" => app.hook.url,
          "content_type" => app.hook.content_type,
          "secret" => app.hook.secret,
          "insecure_ssl" => app.hook.insecure_ssl,
          "name" => app.hook.name,
        }
      else
        nil
      end

      Apps::Internal::ApiHmacClient.any_instance.stubs(:app_manifest).with(id: app.global_relay_id).returns(return_value)
    end

    def stub_proxima_oauth_app_manifest_endpoint(app)
      Apps::Internal::ApiHmacClient.any_instance.stubs(:app_manifest).with(id: app.global_relay_id).returns(
        {
          "global_relay_id" => app.global_relay_id,
          "fingerprint" => app.synchronization_fingerprint,
          "type" => "OauthApplication",
          "settings" => {
            "name" => app.name,
            "url" => app.url,
            "key" => app.key,
            "device_flow_enabled" => app.device_flow_enabled,
            "application_callback_urls" => [
              {
                "url" => app.application_callback_urls.first.url,
              },
              {
                "url" => app.application_callback_urls.second.url,
              }
            ],
            "client_secrets" => [
              {
                "secret_hash" => app.client_secrets.first&.secret_hash,
                "secret_last_eight" => app.client_secrets.first&.secret_last_eight
              }
            ],
            "canonical_avatar_url" => app.primary_avatar_url,
            "owner" => {
              "dotcom_id" => app.owner.id,
              "dotcom_type" => app.owner.type,
              "dotcom_node_id" => app.owner.global_relay_id,
              "login" => app.owner.login,
              "display_login" => app.owner.display_login,
              "avatar_url" => app.owner.primary_avatar_url,
              "url" => app.url,
            }
          }
        }
      )
    end

    self.instance_eval do
      context "when creating an Integration (GitHub App)" do
        test "creates a proxima app" do
          integration = build_internal_integration

          assert_difference "Integration.all.size", +1 do
            stub_proxima_integration_manifest_endpoint(integration)
            @job_klass.perform_now(app_global_relay_id: integration.global_relay_id)
          end
        end

        test "syncs integration attributes" do
          integration = build_internal_integration
          stub_proxima_integration_manifest_endpoint(integration)
          @job_klass.perform_now(app_global_relay_id: integration.global_relay_id)

          synced_integration = Integration.last

          assert_equal integration.name, synced_integration.name
          assert_equal integration.url, synced_integration.url
          assert_equal integration.description, synced_integration.description
          assert_equal integration.public, synced_integration.public
          assert_equal integration.slug, synced_integration.slug
          assert_equal integration.key, synced_integration.key
          assert_equal integration.setup_url, synced_integration.setup_url
          assert_equal integration.bgcolor, synced_integration.bgcolor
          assert_equal integration.setup_on_update, synced_integration.setup_on_update
          assert_equal integration.deleted_at, synced_integration.deleted_at
          assert_equal integration.request_oauth_on_install, synced_integration.request_oauth_on_install
          assert_equal integration.user_token_expiration, synced_integration.user_token_expiration
          assert_equal integration.state, synced_integration.state
          assert_equal integration.suspended_at, synced_integration.suspended_at
          assert_equal integration.user_suspended_by_id, synced_integration.user_suspended_by_id
          assert_equal integration.pinned_api_version, synced_integration.pinned_api_version
          assert_equal integration.device_flow_enabled, synced_integration.device_flow_enabled
        end

        test "syncs associations attributes" do
          integration = build_internal_integration

          stub_proxima_integration_manifest_endpoint(integration)
          @job_klass.perform_now(app_global_relay_id: integration.global_relay_id)

          synced_integration = Integration.last

          assert_equal integration.note, synced_integration.note
          assert_equal integration.default_permissions, synced_integration.default_permissions
          assert_equal integration.default_events, synced_integration.default_events
          assert_equal integration.single_file_name, synced_integration.single_file_name

          assert_equal integration.application_callback_urls.size, synced_integration.application_callback_urls.size
          assert_equal integration.application_callback_urls.first.url, synced_integration.application_callback_urls.first.url

          assert_equal integration.hook.active, synced_integration.hook.active
          assert_equal integration.hook.confirmed, synced_integration.hook.confirmed
          assert_equal integration.hook.pinned_api_version, synced_integration.hook.pinned_api_version
          assert_equal integration.hook.url, synced_integration.hook.url
          assert_equal integration.hook.content_type, synced_integration.hook.content_type
          assert_equal integration.hook.secret, synced_integration.hook.secret
          assert_equal integration.hook.insecure_ssl, synced_integration.hook.insecure_ssl
          assert_equal integration.hook.name, synced_integration.hook.name

          assert_equal integration.integration_install_triggers.size, synced_integration.integration_install_triggers.size
          assert_equal integration.integration_install_triggers.first.path, synced_integration.integration_install_triggers.first.path
          assert_equal integration.integration_install_triggers.first.reason, synced_integration.integration_install_triggers.first.reason
          assert_equal integration.integration_install_triggers.first.install_type, synced_integration.integration_install_triggers.first.install_type
          assert_equal integration.integration_install_triggers.first.deactivated, synced_integration.integration_install_triggers.first.deactivated

          assert_equal integration.client_secrets.first.secret_hash, synced_integration.client_secrets.first.secret_hash
          assert_equal integration.client_secrets.first.secret_last_eight, synced_integration.client_secrets.first.secret_last_eight
        end

        test "creates a proxima app synchronization record" do
          integration = build_internal_integration

          assert_difference "ProximaAppSynchronization.all.size", +1 do
            stub_proxima_integration_manifest_endpoint(integration)
            @job_klass.perform_now(app_global_relay_id: integration.global_relay_id)
          end

          synced_integration = Integration.last

          ProximaAppSynchronization.last.tap do |sync_record|
            assert_equal sync_record.dotcom_global_id, integration.global_relay_id
            assert_equal sync_record.local_app_id, synced_integration.id
            assert_equal sync_record.local_app_type, synced_integration.class.name
            assert_equal sync_record.fingerprint, integration.synchronization_fingerprint
            assert_equal sync_record.canonical_avatar_url.gsub(/&token=.*/, ""), integration.primary_avatar_url.gsub(/&token=.*/, "")
          end
        end

        test "syncs integration version attributes when single_file_name is nil" do
          integration = build_internal_integration
          integration.default_permissions = { "metadata" => :read }
          integration.latest_version.single_files = []

          assert_nil integration.single_file_name

          stub_proxima_integration_manifest_endpoint(integration)
          @job_klass.perform_now(app_global_relay_id: integration.global_relay_id)

          synced_integration = Integration.last

          assert_equal integration.note, synced_integration.note
          assert_equal integration.default_permissions, synced_integration.default_permissions
          assert_equal integration.default_events, synced_integration.default_events
          assert_nil synced_integration.single_file_name
        end

        test "creates a ProximaAppSynchronization record if an app with the same client id exists" do
          local_app = build_internal_integration
          dotcom_app = build_internal_integration(key: "#{local_app.key}")
          local_app.save!
          @job_klass.any_instance.stubs(:app_from_global_id).returns(dotcom_app)

          assert_no_difference "Integration.all.size" do
            assert_difference "ProximaAppSynchronization.all.size", +1 do
              stub_proxima_integration_manifest_endpoint(dotcom_app)
              @job_klass.perform_now(app_global_relay_id: dotcom_app.global_relay_id)
            end
          end
        end

        test "creates a ProximaAppSynchronization record if an app with the same name and owner exists" do
          local_app = build_internal_integration
          dotcom_app = build_internal_integration(name: "#{local_app.name}")
          local_app.save!
          @job_klass.any_instance.stubs(:app_from_global_id).returns(dotcom_app)

          assert_no_difference "Integration.all.size" do
            assert_difference "ProximaAppSynchronization.all.size", +1 do
              stub_proxima_integration_manifest_endpoint(dotcom_app)
              @job_klass.perform_now(app_global_relay_id: dotcom_app.global_relay_id)
            end
          end

          ProximaAppSynchronization.last.tap do |sync_record|
            assert_equal sync_record.canonical_avatar_url.gsub(/&token=.*/, ""), dotcom_app.primary_avatar_url.gsub(/&token=.*/, "")
          end
        end

        test "performs update job if the app already exists and needs syncing" do
          local_app = build_internal_integration
          dotcom_app = build_internal_integration(name: local_app.name, key: local_app.key)

          local_app.url = "http://example2.com"
          local_app.save!
          @job_klass.any_instance.stubs(:app_from_global_id).returns(dotcom_app)

          expected_args = [
            dotcom_app.global_relay_id,
            dotcom_app.synchronization_fingerprint
          ]

          assert_enqueued_with(job: "ProximaAppSync::Update#{@job_klass.new.party_type.capitalize}PartyAppJob".constantize, args: expected_args) do
            stub_proxima_integration_manifest_endpoint(dotcom_app)
            @job_klass.perform_now(app_global_relay_id: dotcom_app.global_relay_id)
          end
        end
      end

      context "when creating an OAuth application" do
        test "it creates a proxima app" do
          assert_difference "OauthApplication.all.size", +1 do
            app = build_internal_oauth_application
            @job_klass.any_instance.stubs(:app_from_global_id).returns(app)
            stub_proxima_oauth_app_manifest_endpoint(app)
            @job_klass.perform_now(app_global_relay_id: app.global_relay_id)
          end
        end

        test "it syncs oauth application attributes" do
          app = build_internal_oauth_application
          @job_klass.any_instance.stubs(:app_from_global_id).returns(app)
          stub_proxima_oauth_app_manifest_endpoint(app)
          @job_klass.perform_now(app_global_relay_id: app.global_relay_id)

          synced_app = OauthApplication.last

          assert_equal app.name, synced_app.name
          assert_equal app.url, synced_app.url
          assert_equal app.key, synced_app.key
          assert_equal app.device_flow_enabled, synced_app.device_flow_enabled
        end

        test "syncs associations attributes" do
          app = build_internal_oauth_application
          @job_klass.any_instance.stubs(:app_from_global_id).returns(app)
          stub_proxima_oauth_app_manifest_endpoint(app)
          @job_klass.perform_now(app_global_relay_id: app.global_relay_id)

          synced_app = OauthApplication.last

          assert_equal app.application_callback_urls.size, synced_app.application_callback_urls.size
          assert_equal app.application_callback_urls.first.url, synced_app.application_callback_urls.first.url
          assert_equal app.application_callback_urls.second.url, synced_app.application_callback_urls.second.url

          assert_equal app.client_secrets.first.secret_hash, synced_app.client_secrets.first.secret_hash
          assert_equal app.client_secrets.first.secret_last_eight, synced_app.client_secrets.first.secret_last_eight
        end

        test "creates a proxima app synchronization record" do
          app = build_internal_oauth_application
          @job_klass.any_instance.stubs(:app_from_global_id).returns(app)

          assert_difference "ProximaAppSynchronization.all.size", +1 do
            stub_proxima_oauth_app_manifest_endpoint(app)
            @job_klass.perform_now(app_global_relay_id: app.global_relay_id)
          end

          synced_app = OauthApplication.last

          ProximaAppSynchronization.last.tap do |sync_record|
            assert_equal sync_record.dotcom_global_id, app.global_relay_id
            assert_equal sync_record.local_app_id, synced_app.id
            assert_equal sync_record.local_app_type, synced_app.class.name
            assert_equal sync_record.fingerprint, app.synchronization_fingerprint
            assert_equal sync_record.canonical_avatar_url.gsub(/&token=.*/, ""), app.primary_avatar_url.gsub(/&token=.*/, "")
          end
        end

        test "creates a ProximaAppSynchronization record if an app with the same client id exists" do
          local_app = build_internal_oauth_application
          dotcom_app = build_internal_oauth_application(key: local_app.key)
          local_app.save!
          @job_klass.any_instance.stubs(:app_from_global_id).returns(dotcom_app)

          assert_no_difference "OauthApplication.all.size" do
            assert_difference "ProximaAppSynchronization.all.size", +1 do
              stub_proxima_oauth_app_manifest_endpoint(dotcom_app)
              @job_klass.perform_now(app_global_relay_id: dotcom_app.global_relay_id)
            end
          end
        end

        test "creates a ProximaAppSynchronization record if an app with the same name and user_id exists" do
          local_app = build_internal_oauth_application
          local_app.save!
          dotcom_app = build_internal_oauth_application(name: "#{local_app.name}")
          @job_klass.any_instance.stubs(:app_from_global_id).returns(dotcom_app)

          assert_no_difference "OauthApplication.all.size" do
            assert_difference "ProximaAppSynchronization.all.size", +1 do
              stub_proxima_oauth_app_manifest_endpoint(dotcom_app)
              @job_klass.perform_now(app_global_relay_id: dotcom_app.global_relay_id)
            end
          end

          ProximaAppSynchronization.last.tap do |sync_record|
            assert_equal sync_record.canonical_avatar_url.gsub(/&token=.*/, ""), dotcom_app.primary_avatar_url.gsub(/&token=.*/, "")
          end
        end

        test "performs update job if the app already exists and needs syncing" do
          local_app = build_internal_oauth_application
          dotcom_app = build_internal_oauth_application(name: local_app.name, key: local_app.key)
          local_app.url = "http://example2.com"
          local_app.save!
          @job_klass.any_instance.stubs(:app_from_global_id).returns(dotcom_app)

          expected_args = [
            dotcom_app.global_relay_id,
            dotcom_app.synchronization_fingerprint
          ]

          assert_enqueued_with(job: "ProximaAppSync::Update#{@job_klass.new.party_type.capitalize}PartyAppJob".constantize, args: expected_args) do
            stub_proxima_oauth_app_manifest_endpoint(dotcom_app)
            @job_klass.perform_now(app_global_relay_id: dotcom_app.global_relay_id)
          end
        end

        test "gracefully handles settings hash with nil application_callback_urls" do
          assert_difference "OauthApplication.all.size", +1 do
            app = build_internal_oauth_application
            @job_klass.any_instance.stubs(:app_from_global_id).returns(app)
            Apps::Internal::ApiHmacClient.any_instance.stubs(:app_manifest).with(id: app.global_relay_id).returns(
              {
                "global_relay_id" => app.global_relay_id,
                "fingerprint" => app.synchronization_fingerprint,
                "type" => "OauthApplication",
                "settings" => {
                  "name" => app.name,
                  "url" => app.url,
                  "key" => app.key,
                  "device_flow_enabled" => app.device_flow_enabled,
                  "application_callback_urls" => nil,
                  "client_secrets" => [
                    {
                      "secret_hash" => app.client_secrets.first.secret_hash,
                      "secret_last_eight" => app.client_secrets.first.secret_last_eight
                    }
                  ],
                  "owner" => {
                    "dotcom_id" => app.owner.id,
                    "dotcom_type" => app.owner.type,
                    "dotcom_node_id" => app.owner.global_relay_id,
                    "login" => app.owner.login,
                    "display_login" => app.owner.display_login,
                    "avatar_url" => app.owner.primary_avatar_url,
                    "url" => app.url,
                },
                }
              }
            )
            @job_klass.perform_now(app_global_relay_id: app.global_relay_id)
          end
        end
      end

      test "raises an error when app already exists" do
        sync_record = create(:proxima_app_synchronization)

        assert_raises ProximaAppSync::CreateAppJobHelper::LocalStateExists do
          @job_klass.perform_now(app_global_relay_id: sync_record.dotcom_global_id)
        end
      end

      test "raises an error when manifest is not found" do
        app = build_internal_integration
        Apps::Internal::ApiHmacClient.any_instance.stubs(:app_manifest).returns(nil)

        assert_raises ProximaAppSync::CreateAppJobHelper::ManifestNotFound do
          @job_klass.perform_now(app_global_relay_id: app.global_relay_id)
        end
      end

      test "raises an error when app type is unknown" do
        app = build_internal_integration
        unknown_type = "some_unknown_type"
        Apps::Internal::ApiHmacClient.any_instance.stubs(:app_manifest).returns(
          {
            "global_relay_id" => app.global_relay_id,
            "fingerprint" => app.synchronization_fingerprint,
            "type" => unknown_type,
            "settings" => {}
          }
        )

        assert_raises_with_message ProximaAppSync::CreateAppJobHelper::UnknownAppType, "Unknown app type: #{unknown_type}" do
          @job_klass.perform_now(app_global_relay_id: app.global_relay_id)
        end
      end

      test "gracefully handles creating an app with no hooks" do
        name = "integration-#{SecureRandom.hex(8)}"

        # Build an integration without a hook
        integration = build(
          :integration,
          id: 0,
          name: name,
          slug: name,
          url: "http://example.com",
          setup_url: "http://example.com",
          deleted_at: Time.utc(2023, 7, 25),
          suspended_at: Time.utc(2023, 7, 25),
          request_oauth_on_install: true,
          user_token_expiration: 1,
          pinned_api_version: GitHub.api_versions.last,
          application_callback_urls: [build(:application_callback_url, url: "https://example.com/callback")],
          integration_install_triggers: [build(:integration_install_trigger, path: "https://example.com", reason: "Example Reason")],
          ip_allowlist_entries: [build(:ip_allowlist_entry, name: "Example IP Allowlist Entry", allow_list_value: "2001:db8::/48", range_from: " \x01\r\xB8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", range_to: " \x01\r\xB8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")],
          bot: build(:bot)
        )


        stub_proxima_integration_manifest_endpoint(integration)
        @job_klass.perform_now(app_global_relay_id: integration.global_relay_id)

        synced_integration = Integration.last

        assert_equal integration.name, synced_integration.name
        assert_nil synced_integration.hook
      end

      test "gracefully handles creating an app with no latest version" do
        integration = build_internal_integration

        assert_difference "Integration.all.size", +1 do
          stub_proxima_integration_manifest_endpoint(integration, with_latest_version: false)
          @job_klass.perform_now(app_global_relay_id: integration.global_relay_id)
        end
      end

      test "creates a DotcomAppOwnerMetadata record" do
        integration = build_internal_integration
        integration.save!

        assert_difference "DotcomAppOwnerMetadata.all.size", +1 do
          stub_proxima_integration_manifest_endpoint(integration)
          @job_klass.perform_now(app_global_relay_id: integration.global_relay_id)
        end

        dotcom_owner_metadata_record = DotcomAppOwnerMetadata.last
        synced_integration = Integration.last

        assert_equal dotcom_owner_metadata_record.local_app, synced_integration
        assert_equal dotcom_owner_metadata_record.dotcom_id, integration.owner.id
        assert_equal dotcom_owner_metadata_record.dotcom_type, integration.owner.type
        assert_equal dotcom_owner_metadata_record.dotcom_node_id, integration.owner.global_relay_id
        assert_equal dotcom_owner_metadata_record.login, integration.owner.login
        assert_equal dotcom_owner_metadata_record.display_login, integration.owner.display_login
        assert_equal dotcom_owner_metadata_record.url , integration.url
        assert_equal dotcom_owner_metadata_record.avatar_url.gsub(/&token=.*/, ""), integration.owner.primary_avatar_url.gsub(/&token=.*/, "")
      end

      test "performs update job if the app already exists and is synced but has a different global id" do
        local_app = build_internal_integration
        dotcom_app = build_internal_integration(name: local_app.name, key: local_app.key)

        # Local app is synced
        local_app.save!
        sync_record = create(:proxima_app_synchronization, local_app: local_app, dotcom_global_id: local_app.global_relay_id)

        # Simulate Dotcom app getting a different global id, maybe due to a transfer
        dotcom_app.stubs(:global_relay_id).returns("new_global_relay_id")

        expected_args = [
          dotcom_app.global_relay_id,
          dotcom_app.synchronization_fingerprint
        ]

        assert_enqueued_with(job: "ProximaAppSync::Update#{@job_klass.new.party_type.capitalize}PartyAppJob".constantize, args: expected_args) do
          stub_proxima_integration_manifest_endpoint(dotcom_app)
          @job_klass.perform_now(app_global_relay_id: dotcom_app.global_relay_id)
        end
      end

      test "updates sync record and owner metadata if the app already exists and is synced but has a different global id" do
        local_app = build_internal_integration
        dotcom_app = build_internal_integration(name: local_app.name, key: local_app.key)

        # Local app is synced
        local_app.save!
        sync_record = create(:proxima_app_synchronization, local_app: local_app, dotcom_global_id: local_app.global_relay_id)
        owner_metadata = create(:dotcom_app_owner_metadata, local_app: local_app, dotcom_owner: local_app.owner)

        # Simulate Dotcom app getting a different global id, maybe due to a transfer
        dotcom_app.stubs(:global_relay_id).returns("new_global_relay_id")
        dotcom_app.owner = create(:user)
        stub_proxima_integration_manifest_endpoint(dotcom_app)

        @job_klass.perform_now(app_global_relay_id: dotcom_app.global_relay_id)

        assert_equal dotcom_app.global_relay_id, sync_record.reload.dotcom_global_id

        owner_metadata.reload
        assert_equal dotcom_app.owner_id, owner_metadata.dotcom_id
        assert_equal dotcom_app.owner_type, owner_metadata.dotcom_type
        assert_equal dotcom_app.owner.global_relay_id, owner_metadata.dotcom_node_id
      end
    end
  end
end
