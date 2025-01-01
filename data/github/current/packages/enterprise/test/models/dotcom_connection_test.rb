# typed: true
# frozen_string_literal: true

require "test_helper"

class DotcomConnectionTest < GitHub::TestCase
  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @user = create(:paid_user)
  end

  teardown do
    # Avoid memoization of license path, because some tests change the Rails environment
    GitHub.send(:license_path=, nil)
  end

  if GitHub.enterprise?
    context "token management" do
      test "store and retrieve token" do
        connection = DotcomConnection.new
        connection.authentication_token = "foobar"
        assert_equal "foobar", connection.authentication_token
      end

      test "store and retrieve temporary token" do
        connection = DotcomConnection.new
        connection.temp_authentication_token = "foobar"
        assert_equal "foobar", connection.temp_authentication_token
      end

      test "temporary token expires at" do
        connection = DotcomConnection.new
        connection.temp_authentication_token = nil
        assert_nil connection.temp_authentication_token_expires_at
        connection.temp_authentication_token = "foobar"
        refute_nil connection.temp_authentication_token_expires_at
      end
    end

    context "#destroy" do
      test "destroys all users without calling dotcom to revoke their tokens or remove contributions" do
        connection = DotcomConnection.new
        dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser", token: "user-token")

        GitHub::Connect::Authenticator.any_instance.expects(:revoke_oauth_token).never
        GitHub::Connect.expects(:remove_user_contributions).never
        connection.destroy
        refute DotcomUser.any?
      end

      test "requests installation removal on dotcom side" do
        connection = DotcomConnection.new
        connection.authentication_token = "abcde"

        connection.authenticator.expects(:remove_enterprise_installation)
        connection.destroy
      end

      test "does not destroy a stored server id" do
        connection = DotcomConnection.new
        server_id = connection.server_id

        connection.destroy

        assert_equal server_id, DotcomConnection.new.server_id
      end
    end

    context "#create" do
      test "sets the token on itself" do
        connection = DotcomConnection.new

        connection.create("abcde")
        assert_equal "abcde", connection.authentication_token
      end

      test "persists app and installation id values passed when the connection is created" do
        connection = DotcomConnection.new

        connection.create("abcde", "14", "101")
        assert_equal "14", connection.installation_issuer
        assert_equal "101", connection.installation_id
      end

      test "persists GitHub version used when the connection was created" do
        connection = DotcomConnection.new

        connection.create("abcde", "14", "101")
        version_on_creation = GitHub.version_number
        assert_equal version_on_creation, connection.enterprise_server_version
        GitHub.stubs(:version_number).returns("different.number")
        assert_equal version_on_creation, connection.enterprise_server_version
      end
    end

    context "#update_application_info" do
      test "persists the owner type and identifier" do
        connection = DotcomConnection.new
        connection.authenticator.stubs(:request_oauth_application).returns({
          "owner_type" => "business",
          "owner_identifier" => "the-business",
          "other" => "stuff",
        })
        connection.update_application_info
        assert_equal "business", connection.owner_type
        assert_equal "the-business", connection.owner_identifier
      end
    end

    context "#owner_type" do
      test "returns the persisted GitHub.com installation owner type" do
        connection = DotcomConnection.new
        connection.authenticator.stubs(:request_oauth_application).returns({
          "owner_identifier" => "owner",
          "owner_type" => "test-owner-type",
        })
        connection.update_application_info
        assert_equal "test-owner-type", connection.owner_type
      end

      test "defaults to 'org' if nothing is persisted" do
        connection = DotcomConnection.new
        assert_equal "org", connection.owner_type
      end
    end

    context "#owner_identifier" do
      test "returns the persisted GitHub.com installation owner id" do
        connection = DotcomConnection.new
        connection.authenticator.stubs(:request_oauth_application).returns({
          "owner_identifier" => "owner",
          "owner_type" => "test-owner-type",
        })
        connection.update_application_info
        assert_equal "owner", connection.owner_identifier
      end

      test "defaults to the legacy organization logic if owner identifier is not persisted" do
        Connect::KV.store.set("ghe-install-organization-login", "organization")
        connection = DotcomConnection.new
        assert_equal "organization", connection.owner_identifier
      end

      test "defaults to nil if neither owner identifier or organization login is persisted" do
        connection = DotcomConnection.new
        assert_nil connection.owner_identifier
      end
    end

    context "#dotcom_profile_url" do
      context "with an organization" do
        test "builds a profile URL from the organization's login" do
          connection = DotcomConnection.new
          connection.stubs(:owner_identifier).returns("some-org")
          connection.stubs(:owner_type).returns("org")
          assert_equal "https://github.com/some-org", connection.dotcom_profile_url
        end

        test "allows non-standard dotcom instances (review lab, local dotcom, etc.)" do
          connection = DotcomConnection.new
          GitHub.stubs(:dotcom_host_protocol).returns("http")
          GitHub.stubs(:dotcom_host_name).returns("github.localhost")
          connection.stubs(:owner_identifier).returns("some-org")
          connection.stubs(:owner_type).returns("org")
          assert_equal "http://github.localhost/some-org", connection.dotcom_profile_url
        end
      end

      context "with a business" do
        test "builds a profile URL from the business's slug" do
          connection = DotcomConnection.new
          connection.stubs(:owner_identifier).returns("some-business")
          connection.stubs(:owner_type).returns("business")
          assert_equal "https://github.com/enterprises/some-business", connection.dotcom_profile_url
        end

        test "allows non-standard dotcom instances (review lab, local dotcom, etc.)" do
          connection = DotcomConnection.new
          GitHub.stubs(:dotcom_host_protocol).returns("http")
          GitHub.stubs(:dotcom_host_name).returns("github.localhost")
          connection.stubs(:owner_identifier).returns("some-business")
          connection.stubs(:owner_type).returns("business")
          assert_equal "http://github.localhost/enterprises/some-business", connection.dotcom_profile_url
        end
      end
    end

    context "#dotcom_enterprise_licensing_url" do
      test "returns the URL to the enterprise licensing page when the owner_type is business" do
        connection = DotcomConnection.new
        connection.stubs(:owner_identifier).returns("some-business")
        connection.stubs(:owner_type).returns("business")
        assert_equal "https://github.com/enterprises/some-business/enterprise_licensing", connection.dotcom_enterprise_licensing_url
      end

      test "returns nil when the owner_type is org" do
        connection = DotcomConnection.new
        connection.stubs(:owner_type).returns("org")
        refute connection.dotcom_enterprise_licensing_url
      end
    end

    context "#add_feature / #added_features" do
      test "persist and retrieve features that the admin want to turn on" do
        connection = DotcomConnection.new
        GitHub.enable_dotcom_search(@user)

        assert_empty connection.added_features
        connection.add_feature("contributions")
        connection.add_feature("private_search")

        assert_equal %w[contributions private_search], connection.added_features
      end
    end

    context "#remove_features / #removed_features" do
      test "persist and retrieve features that the admin want to turn off" do
        connection = DotcomConnection.new
        GitHub.enable_dotcom_search(@user)
        GitHub.enable_dotcom_contributions(@user)
        GitHub.enable_ghe_content_analysis(@user)

        assert_empty connection.removed_features
        connection.remove_feature("search")
        connection.remove_feature("content_analysis")

        assert_equal %w[search content_analysis], connection.removed_features
      end
    end

    context "#clear_pending_features" do
      test "clears any previous request for a feature to be turned on or off" do
        connection = DotcomConnection.new
        GitHub.enable_dotcom_search(@user)
        GitHub.enable_dotcom_contributions(@user)
        connection.add_feature("private_search")
        connection.remove_feature("contributions")
        assert_equal ["private_search"], connection.added_features
        assert_equal ["contributions"], connection.removed_features
        connection.clear_pending_features

        assert_empty connection.added_features
        assert_empty connection.removed_features
      end
    end

    context "#apply_pending_feature_changes" do
      test "applies requested configuration changes" do
        connection = DotcomConnection.new
        GitHub.enable_dotcom_search(@user)
        GitHub.enable_dotcom_private_search(@user)
        GitHub.enable_ghe_content_analysis(@user)

        connection.add_feature("contributions")
        connection.remove_feature("content_analysis")
        refute GitHub.dotcom_contributions_enabled?
        assert GitHub.dotcom_search_enabled?
        assert GitHub.dotcom_private_search_enabled?
        assert GitHub.ghe_content_analysis_enabled?

        connection.apply_pending_feature_changes(@user)
        assert GitHub.dotcom_contributions_enabled?
        assert GitHub.dotcom_search_enabled?
        assert GitHub.dotcom_private_search_enabled?
        refute GitHub.ghe_content_analysis_enabled?
      end

      test "cleans up any registered requests" do
        connection = DotcomConnection.new
        GitHub.enable_dotcom_search(@user)
        GitHub.enable_dotcom_private_search(@user)
        GitHub.enable_ghe_content_analysis(@user)

        connection.add_feature("contributions")
        connection.remove_feature("content_analysis")
        assert_equal ["contributions"], connection.added_features
        assert_equal ["content_analysis"], connection.removed_features

        connection.apply_pending_feature_changes(@user)
        assert_empty connection.added_features
        assert_empty connection.removed_features
      end

      test "schedules update installation job when any features are enabled" do
        connection = DotcomConnection.new
        %w(
          actions_download_archive
          content_analysis
          content_analysis_notifications
          contributions
          dependabot_access
          license_usage_sync
          private_search
          search
          usage_metrics
        ).each do |feature|
          connection.add_feature(feature)
          assert_enqueued_with(job: UpdateConnectInstallationInfo, queue: "github_connect") do
            connection.apply_pending_feature_changes(@user)
          end
        end

        # We ignore the others jobs that might be kicked off by enabling features
        assert_enqueued_jobs 9, only: UpdateConnectInstallationInfo
      end

      test "schedules update installation job when any features are disable" do
        GitHub.enable_dotcom_contributions(@user)
        GitHub.enable_dotcom_search(@user)
        GitHub.enable_dotcom_private_search(@user)
        GitHub.enable_dotcom_user_license_usage_upload(@user)
        GitHub.enable_ghe_content_analysis(@user)
        GitHub.enable_ghe_content_analysis_notifications(@user)
        GitHub.enable_dotcom_download_actions_archive(@user)
        GitHub.enable_ghe_usage_metrics(@user)
        GitHub.enable_ghe_dependabot_access_to_dotcom(@user)

        connection = DotcomConnection.new
        %w(
          actions_download_archive
          content_analysis
          content_analysis_notifications
          contributions
          dependabot_access
          license_usage_sync
          private_search
          search
          usage_metrics
        ).each do |feature|
          connection.remove_feature(feature)
          assert_enqueued_with(job: UpdateConnectInstallationInfo, queue: "github_connect") do
            connection.apply_pending_feature_changes(@user)
          end
        end

        # 1 for each feature
        assert_enqueued_jobs 9, only: UpdateConnectInstallationInfo
      end

      test "schedules sync job when license_usage_sync is enabled" do
        connection = DotcomConnection.new
        connection.add_feature("license_usage_sync")
        assert_equal ["license_usage_sync"], connection.added_features
        assert_equal [], connection.removed_features

        perform_enqueued_jobs(only: [UploadEnterpriseServerUserAccountsJob]) do
          connection.apply_pending_feature_changes(@user)
        end
        assert_performed_jobs 1
      end

      test "schedules a metrics upload job when usage_metrics is enabled" do
        connection = DotcomConnection.new
        connection.add_feature("usage_metrics")
        assert_equal ["usage_metrics"], connection.added_features
        assert_equal [], connection.removed_features

        VCR.use_cassette "github_connect/post_metrics" do
          perform_enqueued_jobs(only: [UploadConnectMetricsJob]) do
            connection.apply_pending_feature_changes(@user)
          end
        end
        assert_performed_jobs 1
      end

      test "schedules a EnterpriseAdvisoryDatabaseSyncJob when content_analysis is enabled" do
        connection = DotcomConnection.new
        connection.add_feature("content_analysis")
        assert_equal ["content_analysis"], connection.added_features
        assert_equal [], connection.removed_features

        assert_enqueued_with(job: EnterpriseAdvisoryDatabaseSyncJob, queue: "advisory_database_sync") do
          connection.apply_pending_feature_changes(@user)
        end
      end

      test "schedules a EnterpriseAdvisoryDatabaseSyncJob when content_analysis_notifications is enabled" do
        connection = DotcomConnection.new
        connection.add_feature("content_analysis_notifications")
        assert_equal ["content_analysis_notifications"], connection.added_features
        assert_equal [], connection.removed_features

        assert_enqueued_with(job: EnterpriseAdvisoryDatabaseSyncJob, queue: "advisory_database_sync") do
          connection.apply_pending_feature_changes(@user)
        end
      end

      test "enqueues a EnterpriseUpdateSecurityConfigurationApplicationsJob when content_analysis is enabled" do
        connection = DotcomConnection.new
        connection.add_feature("content_analysis")
        assert_equal ["content_analysis"], connection.added_features
        assert_equal [], connection.removed_features

        assert_enqueued_with(job: EnterpriseUpdateSecurityConfigurationApplicationsJob) do
          connection.apply_pending_feature_changes(@user)
        end
      end

      test "enqueues a EnterpriseUpdateSecurityConfigurationApplicationsJob when content_analysis_notifications is enabled" do
        connection = DotcomConnection.new
        connection.add_feature("content_analysis_notifications")
        assert_equal ["content_analysis_notifications"], connection.added_features
        assert_equal [], connection.removed_features

        assert_enqueued_with(job: EnterpriseUpdateSecurityConfigurationApplicationsJob) do
          connection.apply_pending_feature_changes(@user)
        end
      end

      test "enqueues a EnterpriseUpdateSecurityConfigurationApplicationsJob when content_analysis is disabled" do
        GitHub.enable_ghe_content_analysis(@user)

        connection = DotcomConnection.new
        connection.remove_feature("content_analysis")
        assert_equal [], connection.added_features
        assert_equal ["content_analysis"], connection.removed_features

        assert_enqueued_with(job: EnterpriseUpdateSecurityConfigurationApplicationsJob) do
          connection.apply_pending_feature_changes(@user)
        end
      end

      test "enqueues a EnterpriseUpdateSecurityConfigurationApplicationsJob when content_analysis_notifications is disabled" do
        GitHub.enable_ghe_content_analysis_notifications(@user)

        connection = DotcomConnection.new
        connection.remove_feature("content_analysis_notifications")
        assert_equal [], connection.added_features
        assert_equal ["content_analysis_notifications"], connection.removed_features

        assert_enqueued_with(job: EnterpriseUpdateSecurityConfigurationApplicationsJob) do
          connection.apply_pending_feature_changes(@user)
        end
      end
    end

    context "#update_permissions" do
      test "requests no features if all settings are disabled" do
        connection = DotcomConnection.new
        connection.authenticator.expects(:request_permissions).with([]).returns("permissions_url")

        GitHub.disable_dotcom_search(@user)
        GitHub.disable_dotcom_private_search(@user)
        GitHub.disable_dotcom_contributions(@user)
        GitHub.disable_ghe_content_analysis(@user)
        assert_equal "permissions_url", connection.update_permissions
      end

      test "requests all features if all settings are enabled" do
        connection = DotcomConnection.new

        connection.authenticator.expects(:request_permissions).with(%w(contributions search private_search content_analysis)).returns("permissions_url")
        GitHub.enable_dotcom_search(@user)
        GitHub.enable_dotcom_private_search(@user)
        GitHub.enable_dotcom_contributions(@user)
        GitHub.enable_ghe_content_analysis(@user)

        assert_equal "permissions_url", connection.update_permissions
      end

      test "only requests enabled features" do
        connection = DotcomConnection.new
        connection.authenticator.expects(:request_permissions).with(%w(contributions content_analysis)).returns("permissions_url")

        GitHub.disable_dotcom_search(@user)
        GitHub.disable_dotcom_private_search(@user)
        GitHub.enable_dotcom_contributions(@user)
        GitHub.enable_ghe_content_analysis(@user)
        assert_equal "permissions_url", connection.update_permissions
      end
    end

    context "#check_status" do
      test "#check_status returns :not_connected if we don't have a token" do
        DotcomConnection.new.authentication_token = nil
        assert_equal :not_connected, DotcomConnection.new.check_status
      end

      test "#check_status returns :unifnished if we have a temporary token" do
        DotcomConnection.new.temp_authentication_token = "temp_token"
        assert_equal :unfinished, DotcomConnection.new.check_status
      end

      test "#check_status returns :unverifiable if we have a token, but can't talk to dotcom" do
        DotcomConnection.new.authentication_token = "abcde"
        GitHub::Connect::Authenticator.any_instance.stubs(:enterprise_installation_api).raises GitHub::Connect::Authenticator::ConnectionError
        assert_equal :unverifiable, DotcomConnection.new.check_status
      end

      test "#check_status returns :unverifiable if request_oauth_application returns nil, simulates 503 from dotcom" do
        DotcomConnection.new.authentication_token = "token"
        GitHub::Connect::Authenticator.any_instance.stubs(:request_oauth_application) { :nil? }
        assert_equal :unverifiable, DotcomConnection.new.check_status
      end

      test "#check_status returns :unverifiable if we have a token, but can't get dotcom to confirm our token" do
        DotcomConnection.new.authentication_token = "abcde"
        GitHub::Connect::Authenticator.any_instance.stubs(:enterprise_installation_api).raises GitHub::Connect::Authenticator::AuthenticationError
        assert_equal :unverifiable, DotcomConnection.new.check_status
      end

      test "#check_status returns :disconnected if dotcom positively doesn't recognize our token (we've been disconnected there)" do
        DotcomConnection.new.authentication_token = "abcde"
        VCR.use_cassette "github_connect/bad_credentials_enterprise_installation_application" do
          assert_equal :disconnected, DotcomConnection.new.check_status
        end
      end

      test "#check_status returns :connected if dotcom confirms our token links to a integration (app) there" do
        DotcomConnection.new.authentication_token = "abcde"
        VCR.use_cassette "github_connect/successful_enterprise_installation_application" do
          assert_equal :connected, DotcomConnection.new.check_status
        end
      end
    end

    context "#authenticator_with_license" do
      test "#authenticator_with_license returns an authenticator with license path for test" do
        connection = DotcomConnection.new
        result = connection.authenticator_with_license

        assert_instance_of(GitHub::Connect::Authenticator, result)
        assert_equal File.absolute_path("#{Rails.root}/../enterprise2/test.ghl"), result.license_file_path
      end

      test "#authenticator_with_license returns an authenticator with license path for production" do
        Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
          connection = DotcomConnection.new
          result = connection.authenticator_with_license

          assert_instance_of(GitHub::Connect::Authenticator, result)
          assert_equal "/data/enterprise/enterprise.ghl", result.license_file_path
        end
      end
    end

    context "#request_authentication_token" do
      test "returns token if request from authenticator returns token" do
        connection = DotcomConnection.new
        auth = connection.authenticator_with_license
        auth.stubs(:request_authentication_token).returns("abcde")

        assert_equal "abcde", connection.request_authentication_token
        assert_equal "abcde", connection.temp_authentication_token
      end

      test "returns nil if request from authenticator returns nil" do
        connection = DotcomConnection.new
        auth = connection.authenticator_with_license
        auth.stubs(:request_authentication_token).returns(nil)

        refute connection.request_authentication_token
      end
    end

    context "#generate_keys" do
      test "returns the private key generated by the authenticator" do
        connection = DotcomConnection.new
        auth = connection.authenticator_with_license
        auth.stubs(:generate_keys).returns("private-key")

        assert_equal "private-key", connection.generate_keys
        assert_equal "private-key", connection.bearer_encoding_key
      end
    end

    context "#require_reconnect?" do
      test "returns true if ghe-install-version key is not present" do
        connection = DotcomConnection.new

        assert connection.require_reconnect?
        connection.create("abcde")
        refute connection.require_reconnect?
      end
    end

    context "#upload_license_info" do
      test "sets ghe-install-upload-id and completes upload sync" do
        GitHub::Connect::Authenticator.any_instance.expects(:upload_license_usage).returns({ "id" => 1 })
        GitHub::Connect::Authenticator.any_instance.expects(:complete_license_info_upload).returns({ "sync_state" => "started", "updated_at" => Time.now.to_s })
        connection = DotcomConnection.new
        data = { version: 1, instance: {}, users: [] }
        assert_nil connection.upload_license_info(data)
        Connect::KV.store.set("ghe-install-owner-type", "business")
        Connect::KV.store.set("ghe-install-owner-identifier", "1")
        upload = connection.upload_license_info(data)
        refute_nil upload
        assert_equal "1", Connect::KV.store.get("ghe-install-upload-id").value { nil }
        assert_equal 1, upload[:id]
        refute_nil upload[:state]
      end

      test "instruments dotcom_connection.upload_license_usage" do
        events = subscribe "dotcom_connection.upload_license_usage"

        GitHub::Connect::Authenticator.any_instance.expects(:upload_license_usage).returns({ "id" => 1 })
        GitHub::Connect::Authenticator.any_instance.expects(:complete_license_info_upload).returns({ "sync_state" => "started", "updated_at" => Time.now.to_s })
        connection = DotcomConnection.new
        connection.actor = @user
        Connect::KV.store.set("ghe-install-owner-type", "business")
        Connect::KV.store.set("ghe-install-owner-identifier", "1")
        connection.upload_license_info({ version: 1, instance: {}, users: [] })

        expected_payload = {
          dotcom_connection: true,
          actor: @user.login,
          actor_id: @user.id,
        }
        assert event = events.pop, "dotcom_connection.upload_license_usage event was expected"
        assert events.empty?
        assert_equal expected_payload, event.payload
      end
    end

    context "#license_info_upload_status" do
      test "fetches status based on ghe-install-upload-id" do
        GitHub::Connect::Authenticator.any_instance.expects(:license_usage_upload_info).returns({ "sync_state" => "pending", "updated_at" => Time.now.to_s })
        Connect::KV.store.set("ghe-install-owner-type", "business")
        Connect::KV.store.set("ghe-install-owner-identifier", "1")
        connection = DotcomConnection.new
        assert_nil connection.license_info_upload_status
        Connect::KV.store.set("ghe-install-upload-id", "1")
        status = connection.license_info_upload_status
        refute_nil status
        assert_equal "pending", status[:state]
      end
    end

    context "#server_id" do
      test "generates a server uuid if it already doesn't exist" do
        server_id = DotcomConnection.new.server_id
        refute_nil server_id

        # verify reloading returns the same uuid
        assert_equal server_id, DotcomConnection.new.server_id
      end
    end

    context "#reset_server_id" do
      test "sets and returns a new uuid" do
        connection = DotcomConnection.new
        server_id = connection.server_id
        refute_nil server_id

        new_server_id = connection.reset_server_id
        refute_equal server_id, new_server_id
        assert_equal new_server_id, connection.server_id
      end
    end

    context "#reset" do
      test "resets all connect information" do
        dotcom_user = create(:dotcom_user, user_id: @user.id, login: "testuser", token: "user-token")

        connection = DotcomConnection.new
        connection.create("abcde", "14", "101")
        connection.authenticator.stubs(:request_oauth_application).returns({
          "owner_identifier" => "owner",
          "owner_type" => "test-owner-type",
        })
        connection.update_application_info

        server_id = connection.server_id

        GitHub.enable_dotcom_search(@user)
        GitHub.enable_dotcom_private_search(@user)
        GitHub.enable_dotcom_contributions(@user)

        # Confirm settings are as expected from above
        refute_nil connection.installation_id
        refute_nil connection.installation_issuer
        refute_nil connection.owner_type
        refute_nil connection.owner_identifier
        assert GitHub.dotcom_search_enabled?
        assert GitHub.dotcom_private_search_enabled?
        assert GitHub.dotcom_contributions_enabled?
        refute GitHub.ghe_content_analysis_enabled?

        # Clear all settings
        new_connection = DotcomConnection.new
        new_connection.reset(@user)

        # Confirm settings have been reset
        refute_equal server_id, new_connection.server_id
        assert_nil new_connection.installation_id
        assert_nil new_connection.installation_issuer
        assert_equal "org", connection.owner_type
        assert_nil connection.owner_identifier

        refute GitHub.dotcom_search_enabled?
        refute GitHub.dotcom_private_search_enabled?
        refute GitHub.dotcom_contributions_enabled?
        refute GitHub.ghe_content_analysis_enabled?

        refute DotcomUser.any?
      end
    end

    context "#license_info" do
      test "encrypts user info by default" do
        GitHub::Connect::Authenticator.any_instance.stubs(:license_file_path).returns("#{Rails.root}/test/fixtures/github-enterprise-utf8.ghl")
        connection = DotcomConnection.new

        VCR.use_cassette("get-active-committers", persist_with: :turboghas) do
          info = connection.license_info(include_instance: false)
          assert_instance_of String, info[:users]
        end
      end

      test "does not contain personal user information by default" do
        GitHub::Connect::Authenticator.any_instance.stubs(:license_file_path).returns("#{Rails.root}/test/fixtures/github-enterprise-utf8.ghl")
        connection = DotcomConnection.new
        VCR.use_cassette("get-active-committers", persist_with: :turboghas) do
          info = connection.license_info(encrypt_users: false, include_instance: false)
          assert_instance_of Array, info[:users]
          assert_equal 1, info[:users].size
          assert_nil info[:users].first[:login]
        end
      end

      test "does not encrypt user info when encrypt_users is provided as false" do
        GitHub::Connect::Authenticator.any_instance.stubs(:license_file_path).returns("#{Rails.root}/test/fixtures/github-enterprise-utf8.ghl")
        connection = DotcomConnection.new
        VCR.use_cassette("get-active-committers", persist_with: :turboghas) do
          info = connection.license_info(include_full_user_info: true, encrypt_users: false, include_instance: false)
          assert_instance_of Array, info[:users]
          assert_equal 1, info[:users].size
          assert_equal @user.login, info[:users].first[:login]
        end
      end

      test "includes instance server id" do
        GitHub::Connect::Authenticator.any_instance.stubs(:license_file_path).returns("#{Rails.root}/test/fixtures/github-enterprise-utf8.ghl")
        connection = DotcomConnection.new
        info = connection.license_info(include_users: false)
        assert_equal connection.server_id, info[:instance][:server_id]
      end

      test "includes license public key" do
        GitHub::Connect::Authenticator.any_instance
          .stubs(:license_file_path)
          .returns("#{Rails.root}/test/fixtures/github-enterprise-utf8.ghl")
        connection = DotcomConnection.new
        info = connection.license_info(include_users: false)
        refute_nil info[:instance][:public_key]
        assert_equal \
          Base64.encode64(connection.authenticator_with_license.public_key),
          info[:instance][:public_key]
      end
    end

    context "instrumentation" do
      test "triggers dotcom_connection.create after create" do
        events = subscribe "dotcom_connection.create"
        connection = DotcomConnection.new
        connection.actor = @user
        connection.create("new-token")

        expected_payload = {
          dotcom_connection: true,
          actor: @user.login,
          actor_id: @user.id,
        }
        instrumentation_event = events.pop

        assert_equal "dotcom_connection.create", instrumentation_event.name
        assert_equal expected_payload, instrumentation_event.payload
      end

      test "triggers dotcom_connection.destroy after creating token" do
        events = subscribe "dotcom_connection.destroy"
        connection = DotcomConnection.new
        connection.actor = @user
        connection.destroy

        expected_payload = {
          dotcom_connection: true,
          actor: @user.login,
          actor_id: @user.id,
        }
        instrumentation_event = events.pop

        assert_equal "dotcom_connection.destroy", instrumentation_event.name
        assert_equal expected_payload, instrumentation_event.payload
      end
    end
  end
end
