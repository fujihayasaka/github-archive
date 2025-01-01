# typed: true
# frozen_string_literal: true


# This is a coupled mixin. It expects the including class to define the following:
# - fixtures do
#     make_trusted_oauth_apps_owner
#     make_proxima_third_party_apps_owner
#     @job_klass = ProximaAppSync::Update*PartyAppJob
#     @owner_id = @job_klass.new.owner_id
#     @app = create(:integration, owner: @owner_id)
#     @dotcom_global_id = "Q_8675309"
#     @fingerprint = "fingerprint"
#     @latest_fingerprint = "fingerprint_next"
#     @synchronization = ProximaAppSynchronization.create!(dotcom_global_id: @dotcom_global_id, local_app: @app, fingerprint: @fingerprint)
#   end
#
#   Test failures in packages/apps/test/jobs/proxima_app_sync/update_app_job_helper_test.rb
#   are produced by these test suites:
#   - UpdateFirstPartyAppJobTest
#   - UpdateThirdPartyAppJobTest
module UpdateAppJobHelperTest
  extend ActiveSupport::Concern

  included do
    self.instance_eval do
      context "#perform" do
        test "raises if local state is not found" do
          @synchronization.destroy!

          assert_raises(ProximaAppSync::UpdateAppJobHelper::LocalStateNotFound) do
            @job_klass.perform_now(@dotcom_global_id, @fingerprint)
          end
        end

        test "raises if local app is not found" do
          @app.destroy!

          assert_raises(ProximaAppSync::UpdateAppJobHelper::LocalAppNotFound) do
            @job_klass.perform_now(@dotcom_global_id, @fingerprint)
          end
        end

        test "raises if fingerprint is current" do
          assert_raises(ProximaAppSync::UpdateAppJobHelper::LocalStateCurrentFingerprint) do
            @job_klass.perform_now(@dotcom_global_id, @fingerprint)
          end
        end

        test "fetches app manifest" do
          Apps::Internal::ApiHmacClient
            .any_instance.expects(:app_manifest)
            .with(id: @dotcom_global_id)
            .returns(
              {
                "settings" => {
                  "owner" => {
                    "dotcom_id" => 123431,
                    "dotcom_type" => "User",
                    "dotcom_node_id" => "Q_1234567",
                    "login" => "owner_dtcm",
                    "display_login" => "owner",
                    "url" => "https://owner.com",
                    "avatar_url" => "https://owner.com/avatar/1"
                  }
                },
              }
            )

          @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)
        end

        test "raises if has_many association is unknown" do
          Apps::Internal::ApiHmacClient
            .any_instance.expects(:app_manifest)
            .with(id: @dotcom_global_id)
            .returns(
              { "settings" => {
                  "unknown_has_many_association" => []
                }
              }
            )

          assert_raises(ProximaAppSync::UpdateAppJobHelper::UnknownHasManyAssociation) do
            @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)
          end
        end

        test "updates synchronization record attributes" do
          Apps::Internal::ApiHmacClient
          .any_instance.expects(:app_manifest)
          .with(id: @dotcom_global_id)
          .returns(
            { "fingerprint" => "new_fingerprint",
              "settings" => {
                "canonical_avatar_url" => "https://example.com/avatar/2",
                "owner" => {
                  "dotcom_id" => 123431,
                  "dotcom_type" => "User",
                  "dotcom_node_id" => "Q_1234567",
                  "login" => "owner_dtcm",
                  "display_login" => "owner",
                  "url" => "https://owner.com",
                  "avatar_url" => "https://owner.com/avatar/1"
                }
              }
            }
          )

          refute_equal @synchronization.fingerprint, "new_fingerprint"
          @job_klass.perform_now(@dotcom_global_id, "new_fingerprint")

          @synchronization.reload
          assert_equal @synchronization.fingerprint, "new_fingerprint"
          assert_equal @synchronization.canonical_avatar_url, "https://example.com/avatar/2"
        end

        test "updates local app record" do
          Apps::Internal::ApiHmacClient
          .any_instance.expects(:app_manifest)
          .with(id: @dotcom_global_id)
          .returns(
            { "fingerprint" => "#{@latest_fingerprint}",
              "settings" => {
                "description" => "My App Description",
                "device_flow_enabled" => true,
                "state" => 0,
                "owner" => {
                  "dotcom_id" => 123431,
                  "dotcom_type" => "User",
                  "dotcom_node_id" => "Q_1234567",
                  "login" => "owner_dtcm",
                  "display_login" => "owner",
                  "url" => "https://owner.com",
                  "avatar_url" => "https://owner.com/avatar/1"
                }
              }
            }
          )

          @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)

          @synchronization.local_app.reload
          assert_equal @synchronization.local_app.description, "My App Description"
          assert_equal @synchronization.local_app.state, "active"
          assert_equal @synchronization.local_app.device_flow_enabled, true
        end

        test "updates local app's integration version when an update attribute is 'latest_version' and introduces new changes" do
          Apps::Internal::ApiHmacClient
          .any_instance.expects(:app_manifest)
          .with(id: @dotcom_global_id)
          .returns(
            { "fingerprint" => "#{@latest_fingerprint}",
              "settings" => {
                "latest_version" => {
                  "default_permissions" => { "metadata" => "read", "contents" => "read", "single_file" => "read" },
                  "default_events" => ["label"],
                  "single_file_name" => "README.md",
                  "note" => "This is a note"
                },
                "owner" => {
                  "dotcom_id" => 123431,
                  "dotcom_type" => "User",
                  "dotcom_node_id" => "Q_1234567",
                  "login" => "owner_dtcm",
                  "display_login" => "owner",
                  "url" => "https://owner.com",
                  "avatar_url" => "https://owner.com/avatar/1"
                }
              }
            }
          )
          app = @synchronization.reload.local_app
          app.update!(hook: build(:hook, active: true, confirmed: true, pinned_api_version: GitHub.api_versions.last, secret: "Example Secret"))

          assert_equal app.default_permissions, {}
          assert_equal app.default_events, []
          assert_nil app.single_file_name
          assert_nil app.note

          @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)

          app.reload

          assert_equal app.default_permissions, { "metadata" => :read, "contents" => :read, "single_file" => :read }
          assert_equal app.default_events, ["label"]
          assert_equal app.single_file_name, "README.md"
          assert_equal app.note, "This is a note"
        end

        test "does not create new integration version for the local app when an update attribute is 'latest_version' and it introduces no changes" do
          app = @synchronization.reload.local_app
          app.hook = build(:hook, active: true, confirmed: true, pinned_api_version: GitHub.api_versions.last, secret: "Example Secret")

          pre_update_version = app.latest_version

          Apps::Internal::ApiHmacClient
          .any_instance.expects(:app_manifest)
          .with(id: @dotcom_global_id)
          .returns(
            { "fingerprint" => "#{@latest_fingerprint}",
              "settings" => {
                "latest_version" => {
                  "default_permissions" => app.default_permissions,
                  "default_events" => app.default_events,
                  "single_file_name" => app.single_file_name,
                  "note" => app.note
                },
                "owner" => {
                  "dotcom_id" => 123431,
                  "dotcom_type" => "User",
                  "dotcom_node_id" => "Q_1234567",
                  "login" => "owner_dtcm",
                  "display_login" => "owner",
                  "url" => "https://owner.com",
                  "avatar_url" => "https://owner.com/avatar/1"
                }
              }
            }
          )

          @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)

          app.reload

          post_update_version = app.reload.latest_version

          assert_equal pre_update_version.id, post_update_version.id
        end

        test "updates local app record when an update attribute value is a Hash" do
          hook = build(:hook, active: true, confirmed: true, pinned_api_version: GitHub.api_versions.last, secret: "Example Secret")

          Apps::Internal::ApiHmacClient.any_instance
            .expects(:app_manifest)
            .with(id: @dotcom_global_id)
            .returns(
              {
                "settings" => {
                  "hook" => {
                    "active" => hook.active,
                    "confirmed" => hook.confirmed,
                    "pinned_api_version" => hook.pinned_api_version,
                    "url" => hook.url,
                    "content_type" => hook.content_type,
                    "secret" => hook.secret,
                    "insecure_ssl" => hook.insecure_ssl,
                    "name" => hook.name,
                  },
                  "owner" => {
                    "dotcom_id" => 123431,
                    "dotcom_type" => "User",
                    "dotcom_node_id" => "Q_1234567",
                    "login" => "owner_dtcm",
                    "display_login" => "owner",
                    "url" => "https://owner.com",
                    "avatar_url" => "https://owner.com/avatar/1"
                  }
                }
              }
            )

          refute @synchronization.local_app.hook
          @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)

          @synchronization.local_app.reload
          assert_equal @synchronization.local_app.hook.active, hook.active
          assert_equal @synchronization.local_app.hook.confirmed, hook.confirmed
          assert_equal @synchronization.local_app.hook.name, hook.name
          assert_equal @synchronization.local_app.hook.url, hook.url
        end

        test "updates local app hook when hook already exists" do
          hook = build(:hook, active: true, confirmed: true, pinned_api_version: GitHub.api_versions.last, secret: "Example Secret")
          @synchronization.local_app.hook = hook
          @synchronization.local_app.save!

          updated_hook = build(:hook, active: true, confirmed: true, pinned_api_version: GitHub.api_versions.last, secret: "Another Secret")

          Apps::Internal::ApiHmacClient.any_instance
            .expects(:app_manifest)
            .with(id: @dotcom_global_id)
            .returns(
              {
                "settings" => {
                  "hook" => {
                    "active" => updated_hook.active,
                    "confirmed" => updated_hook.confirmed,
                    "pinned_api_version" => updated_hook.pinned_api_version,
                    "url" => updated_hook.url,
                    "content_type" => updated_hook.content_type,
                    "secret" => updated_hook.secret,
                    "insecure_ssl" => updated_hook.insecure_ssl,
                    "name" => updated_hook.name,
                  },
                  "owner" => {
                    "dotcom_id" => 123431,
                    "dotcom_type" => "User",
                    "dotcom_node_id" => "Q_1234567",
                    "login" => "owner_dtcm",
                    "display_login" => "owner",
                    "url" => "https://owner.com",
                    "avatar_url" => "https://owner.com/avatar/1"
                  }
                }
              }
            )

          assert_equal @synchronization.local_app.hook.name, hook.name
          @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)

          @synchronization.local_app.reload
          assert_equal @synchronization.local_app.hook.active, updated_hook.active
          assert_equal @synchronization.local_app.hook.confirmed, updated_hook.confirmed
          assert_equal @synchronization.local_app.hook.name, updated_hook.name
          assert_equal @synchronization.local_app.hook.url, updated_hook.url
        end
      end

      test "updates local app by deleting hook successfully" do
        create(:hook, installation_target: @app)
        Apps::Internal::ApiHmacClient
        .any_instance.expects(:app_manifest)
        .with(id: @dotcom_global_id)
        .returns(
          { "fingerprint" => "#{@latest_fingerprint}",
            "settings" => {
              "hook" => nil,
              "owner" => {
                "dotcom_id" => 123431,
                "dotcom_type" => "User",
                "dotcom_node_id" => "Q_1234567",
                "login" => "owner_dtcm",
                "display_login" => "owner",
                "url" => "https://owner.com",
                "avatar_url" => "https://owner.com/avatar/1"
              }
            }
          }
        )
        @synchronization.local_app.reload
        assert_predicate @synchronization.local_app.hook, :present?

        @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)

        @synchronization.local_app.reload
        assert_nil @synchronization.local_app.hook
      end

      test "updates local app associated records when an update attribute value is an Array and no associated records exist" do
        ::ProximaAppRequest::TenantScopedUrl.expects(:should_generate?).returns(false).at_least_once
        ip_allowlist_entry = build(:ip_allowlist_entry, name: "Example IP Allowlist Entry", allow_list_value: "2001:db8::/48", range_from: " \x01\r\xB8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", range_to: " \x01\r\xB8\x00\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF")
        application_callback_url = build(:application_callback_url, url: "https://example.com/callback")
        integration_install_trigger = build(:integration_install_trigger, install_type: "file_added", path: "\\A\\.github/example/path", reason: "Example Reason", deactivated: false)
        secret = "33sfs33967a56"
        client_secret = build(:integration_client_secret, secret_hash: OauthApplicationClientSecret.hash_for(secret), secret_last_eight: secret.last(8))
        public_key = build(:integration_key)

        Apps::Internal::ApiHmacClient.any_instance
          .expects(:app_manifest)
          .with(id: @dotcom_global_id)
          .returns(
            {
              "settings" => {
                "application_callback_urls" => [
                    {
                      "url" => application_callback_url.url
                    }
                ],
                "ip_allowlist_entries" => [
                  {
                    "allow_list_value" => ip_allowlist_entry.allow_list_value,
                    "range_from" => ip_allowlist_entry.range_from,
                    "range_to" => ip_allowlist_entry.range_to,
                    "name" => ip_allowlist_entry.name,
                    "active" => ip_allowlist_entry.active
                  }
                ],
                "integration_install_triggers" => [
                  {
                    "install_type" => integration_install_trigger.install_type,
                    "path" => integration_install_trigger.path,
                    "reason" => integration_install_trigger.reason,
                    "deactivated" => integration_install_trigger.deactivated
                  }
                ],
                "client_secrets" => [
                  {
                    "secret_hash" => client_secret.secret_hash,
                    "secret_last_eight" => client_secret.secret_last_eight
                  }
                ],
                "public_keys" => [
                  {
                    "public_pem" => public_key.public_pem,
                  }
                ],
                "owner" => {
                  "dotcom_id" => 123431,
                  "dotcom_type" => "User",
                  "dotcom_node_id" => "Q_1234567",
                  "login" => "owner_dtcm",
                  "display_login" => "owner",
                  "url" => "https://owner.com",
                  "avatar_url" => "https://owner.com/avatar/1"
                }
              }
            }
          )

        app = @synchronization.local_app

        # No associated records exist
        assert_empty @synchronization.local_app.ip_allowlist_entries
        assert_empty @synchronization.local_app.application_callback_urls
        assert_empty @synchronization.local_app.integration_install_triggers
        assert_empty @synchronization.local_app.client_secrets
        assert_empty @synchronization.local_app.public_keys

        @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)

        app.reload

        # Associated records are created
        assert_equal app.ip_allowlist_entries.count, 1
        assert_equal app.ip_allowlist_entries.first.allow_list_value, ip_allowlist_entry.allow_list_value
        assert_equal app.ip_allowlist_entries.first.name, ip_allowlist_entry.name
        assert_equal app.ip_allowlist_entries.first.active, ip_allowlist_entry.active

        assert_equal app.application_callback_urls.count, 1
        assert_equal app.application_callback_urls.first.url, application_callback_url.url

        assert_equal app.integration_install_triggers.count, 1
        assert_equal app.integration_install_triggers.first.install_type, integration_install_trigger.install_type
        assert_equal app.integration_install_triggers.first.path, integration_install_trigger.path
        assert_equal app.integration_install_triggers.first.reason, integration_install_trigger.reason
        assert_equal app.integration_install_triggers.first.deactivated, integration_install_trigger.deactivated

        assert_equal app.client_secrets.count, 1
        assert_equal app.client_secrets.first.secret_hash, client_secret.secret_hash
        assert_equal app.client_secrets.first.secret_last_eight, client_secret.secret_last_eight

        # First-party apps do not sync public keys
        if app.synchronized_third_party_app?
          assert_equal app.public_keys.count, 1
          assert_equal app.public_keys.first.public_pem, public_key.public_pem
        end
      end

      test "updates local app has_many records when an update attribute value is an Array and associated records exist" do
        ip_allowlist_entry = build(:ip_allowlist_entry, name: "Example IP Allowlist Entry", allow_list_value: "2001:db8::/48", range_from: " \x01\r\xB8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", range_to: " \x01\r\xB8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
        application_callback_url = build(:application_callback_url, url: "https://example.com/callback")
        integration_install_trigger = build(:integration_install_trigger, install_type: "file_added", path: "\\A\\.github/example/path", reason: "Example Reason", deactivated: false)
        secret = "33sfs33967a56"
        client_secret = build(:integration_client_secret, secret_hash: OauthApplicationClientSecret.hash_for(secret), secret_last_eight: secret.last(8))
        public_key = build(:integration_key)

        app = @synchronization.local_app
        app.update!(
          ip_allowlist_entries: [ip_allowlist_entry],
          application_callback_urls: [application_callback_url],
          integration_install_triggers: [integration_install_trigger],
          client_secrets: [client_secret],
          public_keys: [public_key]
        )

        Apps::Internal::ApiHmacClient.any_instance
          .expects(:app_manifest)
          .with(id: @dotcom_global_id)
          .returns(
            {
              "settings" => {
                "application_callback_urls" => [
                    {
                      "url" => application_callback_url.url + "/test"
                    }
                ],
                "ip_allowlist_entries" => [
                  {
                    "allow_list_value" => "192.168.100.0/22",
                    "range_from" => "\xC0\xA8d\u0000",
                    "range_to" => "\xC0\xA8g\xFF",
                    "name" => "Example IP Allowlist Entry2",
                    "active" => !ip_allowlist_entry.active
                  }
                ],
                "integration_install_triggers" => [
                  {
                    "install_type" => "user_created",
                    "path" => "example/path2",
                    "reason" => "Another Reason",
                    "deactivated" => !integration_install_trigger.deactivated
                  }
                ],
                "client_secrets" => [
                  {
                    "secret_hash" => "ipPPMJrCKhg26rWvXVZdItbwbgcGSco2+YCGTaAT7aY=",
                    "secret_last_eight" => "33d1112s"
                  }
                ],
                "public_keys" => [
                  {
                    "public_pem" => new_pem = OpenSSL::PKey::RSA.new(2048).public_key.to_pem
                  }
                ],
                "owner" => {
                  "dotcom_id" => 123431,
                  "dotcom_type" => "User",
                  "dotcom_node_id" => "Q_1234567",
                  "login" => "owner_dtcm",
                  "display_login" => "owner",
                  "url" => "https://owner.com",
                  "avatar_url" => "https://owner.com/avatar/1"
                }
              }
            }
          )

        app = @synchronization.local_app

        refute_empty @synchronization.local_app.ip_allowlist_entries
        refute_empty @synchronization.local_app.application_callback_urls
        refute_empty @synchronization.local_app.integration_install_triggers
        refute_empty @synchronization.local_app.client_secrets
        refute_empty @synchronization.local_app.public_keys

        @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)

        app.reload

        assert_equal app.ip_allowlist_entries.count, 1
        assert_equal app.ip_allowlist_entries.first.allow_list_value, "192.168.100.0/22"
        assert_equal app.ip_allowlist_entries.first.name, "Example IP Allowlist Entry2"
        assert_equal app.ip_allowlist_entries.first.active, !ip_allowlist_entry.active

        assert_equal app.application_callback_urls.count, 1
        assert_equal app.application_callback_urls.first.url, application_callback_url.url + "/test"

        assert_equal app.integration_install_triggers.count, 1
        assert_equal app.integration_install_triggers.first.install_type, "user_created"
        assert_equal app.integration_install_triggers.first.path, "example/path2"
        assert_equal app.integration_install_triggers.first.reason, "Another Reason"
        assert_equal app.integration_install_triggers.first.deactivated, !integration_install_trigger.deactivated

        assert_equal app.client_secrets.count, 2
        assert_includes app.client_secrets.map(&:secret_hash), "ipPPMJrCKhg26rWvXVZdItbwbgcGSco2+YCGTaAT7aY="
        assert_includes app.client_secrets.map(&:secret_last_eight), "33d1112s"

        if app.synchronized_third_party_app?
          assert_equal app.public_keys.count, 2
          assert_includes app.public_keys.map(&:public_pem), new_pem
        end
      end

      test "removes association record when it is not present in the dotcom state" do
        application_callback_url = build(:application_callback_url, url: "https://example.com/callback")
        @synchronization.local_app.application_callback_urls << application_callback_url

        Apps::Internal::ApiHmacClient.any_instance
        .expects(:app_manifest)
        .with(id: @dotcom_global_id)
        .returns(
          {
            "settings" => {
              "application_callback_urls" => [],
              "owner" => {
                "dotcom_id" => 123431,
                "dotcom_type" => "User",
                "dotcom_node_id" => "Q_1234567",
                "login" => "owner_dtcm",
                "display_login" => "owner",
                "url" => "https://owner.com",
                "avatar_url" => "https://owner.com/avatar/1"
              }
            }
          }
        )

        assert_equal @synchronization.local_app.application_callback_urls.count, 1
        @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)

        @synchronization.local_app.reload
        assert_equal @synchronization.local_app.application_callback_urls.count, 0
      end

      test "handles multiple association records" do
        Apps::Internal::ApiHmacClient.any_instance
        .expects(:app_manifest)
        .with(id: @dotcom_global_id)
        .returns(
          {
            "settings" => {
              "application_callback_urls" => [
                {
                  "url" => "https://example.com/callback"
                },
                {
                  "url" => "https://example.com/callback_2"
                }
              ],
              "owner" => {
                "dotcom_id" => 123431,
                "dotcom_type" => "User",
                "dotcom_node_id" => "Q_1234567",
                "login" => "owner_dtcm",
                "display_login" => "owner",
                "url" => "https://owner.com",
                "avatar_url" => "https://owner.com/avatar/1"
              }
            }
          }
        )

        assert_equal @synchronization.local_app.application_callback_urls.count, 0
        @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)

        @synchronization.local_app.reload
        assert_equal @synchronization.local_app.application_callback_urls.count, 2
        assert_same_elements @synchronization.local_app.application_callback_urls.map(&:url), ["https://example.com/callback", "https://example.com/callback_2"]
      end

      # Test with different values and similar values
      test "updates oauth app" do
        oauth_application = build(
          :oauth_application,
          id: 0,
          name: "oauth-application-#{SecureRandom.hex(8)}",
          url: "http://example.com",
          device_flow_enabled: false,
          application_callback_urls: [build(:application_callback_url, url: "https://example.com/callback")]
        )
        Apps::Internal::Registry.configure(
          app: oauth_application,
          app_alias: oauth_application.name.to_sym,
          id: ->() { oauth_application.id },
          capabilities: { proxima_first_party_sync: true },
          properties: { proxima_sync_delegate: :DefaultDelegate },
        )

        synchronization = ProximaAppSynchronization.create!(dotcom_global_id: oauth_application.global_relay_id, local_app: oauth_application, fingerprint: @fingerprint)

        Apps::Internal::ApiHmacClient.any_instance.stubs(:app_manifest).with(id: oauth_application.global_relay_id).returns(
          {
            "global_relay_id" => oauth_application.global_relay_id,
            "fingerprint" => oauth_application.synchronization_fingerprint,
            "type" => "OauthApplication",
            "settings" => {
              "name" => oauth_application.name,
              "url" => oauth_application.url,
              "device_flow_enabled" => true,
              "application_callback_urls" => [
                {
                  "url" => "https://something-completely-different.com/callback",
                }
              ],
              "owner" => {
                "dotcom_id" => 123431,
                "dotcom_type" => "User",
                "dotcom_node_id" => "Q_1234567",
                "login" => "owner_dtcm",
                "display_login" => "owner",
                "url" => "https://owner.com",
                "avatar_url" => "https://owner.com/avatar/1"
              }
            }
          }
        )

        @job_klass.perform_now(oauth_application.global_relay_id, @latest_fingerprint)

        oauth_application.reload
        assert_equal oauth_application.device_flow_enabled, true
        assert_equal oauth_application.application_callback_urls.first.url, "https://something-completely-different.com/callback"
      end

      test "updates oauth app when attribute value is an Array and no associated records exist" do
        ::ProximaAppRequest::TenantScopedUrl.expects(:should_generate?).returns(false).at_least_once
        oauth_application = build(
          :oauth_application,
          id: 0,
          name: "oauth-application-#{SecureRandom.hex(8)}",
          url: "http://example.com",
          application_callback_urls: [],
          client_secrets: []
        )
        secret = "33sfs33967a56"
        client_secret = build(:oauth_application_client_secret, secret_hash: OauthApplicationClientSecret.hash_for(secret), secret_last_eight: secret.last(8))
        application_callback_url = build(:application_callback_url, url: "https://example.com/callback")

        Apps::Internal::Registry.configure(
          app: oauth_application,
          app_alias: oauth_application.name.to_sym,
          id: ->() { oauth_application.id },
          capabilities: { proxima_first_party_sync: true },
          properties: { proxima_sync_delegate: :DefaultDelegate },
        )

        Apps::Internal::ApiHmacClient.any_instance.stubs(:app_manifest).with(id: oauth_application.global_relay_id).returns(
          {
            "global_relay_id" => oauth_application.global_relay_id,
            "fingerprint" => oauth_application.synchronization_fingerprint,
            "type" => "OauthApplication",
            "settings" => {
              "name" => oauth_application.name,
              "url" => oauth_application.url,
              "application_callback_urls" => [
                {
                  "url" => application_callback_url.url
                }
            ],
              "client_secrets" => [
                {
                  "secret_hash" => "ipPPMJrCKhg26rWvXVZdItbwbgcGSco2+YCGTaAT7aY=",
                  "secret_last_eight" => "33967a56"
                }
              ],
              "owner" => {
                "dotcom_id" => 123431,
                "dotcom_type" => "User",
                "dotcom_node_id" => "Q_1234567",
                "login" => "owner_dtcm",
                "display_login" => "owner",
                "url" => "https://owner.com",
                "avatar_url" => "https://owner.com/avatar/1"
              }
            }
          }
        )

        synchronization = ProximaAppSynchronization.create!(dotcom_global_id: oauth_application.global_relay_id, local_app: oauth_application, fingerprint: @fingerprint)

        assert_empty synchronization.local_app.application_callback_urls
        assert_empty synchronization.local_app.client_secrets

        @job_klass.perform_now(oauth_application.global_relay_id, @latest_fingerprint)

        app = synchronization.local_app.reload

        assert_equal app.application_callback_urls.count, 1
        assert_equal app.application_callback_urls.first.url, application_callback_url.url

        assert_equal app.client_secrets.count, 1
        assert_equal app.client_secrets.first.secret_hash, "ipPPMJrCKhg26rWvXVZdItbwbgcGSco2+YCGTaAT7aY="
        assert_equal app.client_secrets.first.secret_last_eight, "33967a56"
      end

      test "updates oauth app when attribute value is an Array and associated records exist" do
        secret = "33sfs33967a56"
        oauth_application = create(
          :oauth_application,
          id: 0,
          name: "oauth-application-#{SecureRandom.hex(8)}",
          url: "http://example.com",
          application_callback_urls: [build(:application_callback_url, url: "https://example.com/callback")],
          client_secrets: [build(:oauth_application_client_secret, secret_hash: OauthApplicationClientSecret.hash_for(secret), secret_last_eight: secret.last(8))]
        )

        Apps::Internal::Registry.configure(
          app: oauth_application,
          app_alias: oauth_application.name.to_sym,
          id: ->() { oauth_application.id },
          capabilities: { proxima_first_party_sync: true },
          properties: { proxima_sync_delegate: :DefaultDelegate },
        )

        Apps::Internal::ApiHmacClient.any_instance.stubs(:app_manifest).with(id: oauth_application.global_relay_id).returns(
          {
            "global_relay_id" => oauth_application.global_relay_id,
            "fingerprint" => oauth_application.synchronization_fingerprint,
            "type" => "OauthApplication",
            "settings" => {
              "name" => oauth_application.name,
              "url" => oauth_application.url,
              "application_callback_urls" => [
                {
                  "url" => oauth_application.application_callback_urls.first.url + "/test"
                }
            ],
              "client_secrets" => [
                {
                  "secret_hash" => "ipPPMJrCKhg26rWvXVZdItbwbgcGSco2+YCGTaAT7aY=",
                  "secret_last_eight" => "33d1112s"
                }
              ],
              "owner" => {
                "dotcom_id" => 123431,
                "dotcom_type" => "User",
                "dotcom_node_id" => "Q_1234567",
                "login" => "owner_dtcm",
                "display_login" => "owner",
                "url" => "https://owner.com",
                "avatar_url" => "https://owner.com/avatar/1"
              }
            }
          }
        )

        synchronization = ProximaAppSynchronization.create!(dotcom_global_id: oauth_application.global_relay_id, local_app: oauth_application, fingerprint: @fingerprint)

        refute_empty synchronization.local_app.application_callback_urls
        refute_empty synchronization.local_app.client_secrets

        @job_klass.perform_now(oauth_application.global_relay_id, @latest_fingerprint)

        synced_app = synchronization.local_app.reload

        assert_equal synced_app.application_callback_urls.count, 1
        assert_equal synced_app.application_callback_urls.first.url, "https://example.com/callback/test"

        assert_equal synced_app.client_secrets.count, 2
        assert_includes synced_app.client_secrets.map(&:secret_hash), "ipPPMJrCKhg26rWvXVZdItbwbgcGSco2+YCGTaAT7aY="
        assert_includes synced_app.client_secrets.map(&:secret_last_eight), "33967a56"
      end

      test "handles multiple callback urls for oauth apps" do
        ::ProximaAppRequest::TenantScopedUrl.expects(:should_generate?).returns(false).at_least_once
        oauth_application = build(
          :oauth_application,
          id: 0,
          name: "oauth-application-#{SecureRandom.hex(8)}",
          url: "http://example.com",
          application_callback_urls: [],
          client_secrets: []
        )

        application_callback_url_1 = build(:application_callback_url, url: "https://example.com/callback")
        application_callback_url_2 = build(:application_callback_url, url: "https://example.com/callback2")

        Apps::Internal::Registry.configure(
          app: oauth_application,
          app_alias: oauth_application.name.to_sym,
          id: ->() { oauth_application.id },
          capabilities: { proxima_first_party_sync: true },
          properties: { proxima_sync_delegate: :DefaultDelegate },
        )

        Apps::Internal::ApiHmacClient.any_instance.stubs(:app_manifest).with(id: oauth_application.global_relay_id).returns(
          {
            "global_relay_id" => oauth_application.global_relay_id,
            "fingerprint" => oauth_application.synchronization_fingerprint,
            "type" => "OauthApplication",
            "settings" => {
              "name" => oauth_application.name,
              "url" => oauth_application.url,
              "application_callback_urls" => [
                {
                  "url" => application_callback_url_1.url
                },
                {
                  "url" => application_callback_url_2.url
                }
              ],
              "owner" => {
                "dotcom_id" => 123431,
                "dotcom_type" => "User",
                "dotcom_node_id" => "Q_1234567",
                "login" => "owner_dtcm",
                "display_login" => "owner",
                "url" => "https://owner.com",
                "avatar_url" => "https://owner.com/avatar/1"
              }
            }
          }
        )

        synchronization = ProximaAppSynchronization.create!(dotcom_global_id: oauth_application.global_relay_id, local_app: oauth_application, fingerprint: @fingerprint)

        assert_empty synchronization.local_app.application_callback_urls

        @job_klass.perform_now(oauth_application.global_relay_id, @latest_fingerprint)

        synchronization.local_app.reload
        assert_equal synchronization.local_app.application_callback_urls.count, 2
        assert_same_elements synchronization.local_app.application_callback_urls.map(&:url), ["https://example.com/callback", "https://example.com/callback2"]
      end

      test "creates dotcom app owner metadata record if one doesn't exist" do
        Apps::Internal::ApiHmacClient.any_instance.stubs(:app_manifest).with(id: @dotcom_global_id).returns(
          {
            "global_relay_id" => @dotcom_global_id,
            "fingerprint" => @latest_fingerprint,
            "type" => "OauthApplication",
            "settings" => {
              "name" => "oauth-application-#{SecureRandom.hex(8)}",
              "url" => "http://example.com",
              "application_callback_urls" => [
                {
                  "url" => "https://example.com/callback"
                }
              ],
              "owner" => {
                "dotcom_id" => 123431,
                "dotcom_type" => "User",
                "dotcom_node_id" => "Q_1234567",
                "login" => "owner_dtcm",
                "display_login" => "owner",
                "url" => "https://owner.com",
                "avatar_url" => "https://owner.com/avatar/1"
              }
            }
          }
        )

        assert_nil DotcomAppOwnerMetadata.find_by(local_app: @app)

        assert_difference "DotcomAppOwnerMetadata.count", 1 do
          @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)
        end

        dotcom_owner_metadata = DotcomAppOwnerMetadata.last

        assert_equal dotcom_owner_metadata.local_app, @app
        assert_equal dotcom_owner_metadata.dotcom_id, 123431
        assert_equal dotcom_owner_metadata.dotcom_type, "User"
        assert_equal dotcom_owner_metadata.dotcom_node_id, "Q_1234567"
        assert_equal dotcom_owner_metadata.login, "owner_dtcm"
        assert_equal dotcom_owner_metadata.display_login, "owner"
        assert_equal dotcom_owner_metadata.url, "https://owner.com"
        assert_equal dotcom_owner_metadata.avatar_url, "https://owner.com/avatar/1"
      end

      test "updates dotcom app owner metadata record if it exists" do
        Apps::Internal::ApiHmacClient.any_instance.stubs(:app_manifest).with(id: @dotcom_global_id).returns(
          {
            "global_relay_id" => @dotcom_global_id,
            "fingerprint" => @latest_fingerprint,
            "type" => "OauthApplication",
            "settings" => {
              "name" => "oauth-application-#{SecureRandom.hex(8)}",
              "url" => "http://example.com",
              "application_callback_urls" => [
                {
                  "url" => "https://example.com/callback"
                }
              ],
              "owner" => {
                "dotcom_id" => 123431,
                "dotcom_type" => "User",
                "dotcom_node_id" => "Q_1234567",
                "login" => "owner_dtcm",
                "display_login" => "owner",
                "url" => "https://owner.com",
                "avatar_url" => "https://owner.com/avatar/1"
              }
            }
          }
        )

        dotcom_owner_metadata = create(:dotcom_app_owner_metadata, local_app: @app)
        refute_equal dotcom_owner_metadata.dotcom_id, 123431

        assert_no_difference "DotcomAppOwnerMetadata.count" do
          @job_klass.perform_now(@dotcom_global_id, @latest_fingerprint)
        end

        dotcom_owner_metadata.reload
        assert_equal dotcom_owner_metadata.dotcom_id, 123431
        assert_equal dotcom_owner_metadata.dotcom_type, "User"
        assert_equal dotcom_owner_metadata.dotcom_node_id, "Q_1234567"
        assert_equal dotcom_owner_metadata.login, "owner_dtcm"
        assert_equal dotcom_owner_metadata.display_login, "owner"
        assert_equal dotcom_owner_metadata.url, "https://owner.com"
        assert_equal dotcom_owner_metadata.avatar_url, "https://owner.com/avatar/1"
      end
    end
  end
end
