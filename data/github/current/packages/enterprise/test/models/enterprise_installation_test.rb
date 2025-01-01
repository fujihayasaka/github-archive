# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseInstallationTest < GitHub::TestCase
  include UploadableTestHelpers
  include HydroTestHelpers

  fixtures do
    @admin = create(:paid_user)
    @org   = create(:organization, admin: @admin)
    @org_installation = create :enterprise_installation,
      owner: @org,
      customer_name: "org owner industries",
      host_name: "org.wtf"
    @business = create(:business, owners: [@admin], organizations: [@org])
    @business_installation = create :enterprise_installation, \
      owner: @business,
      customer_name: "business owner industries",
      host_name: "business.wtf"
    @upload = create :enterprise_installation_user_accounts_upload,
      business: @business
    save_file_for_uploadable @upload,
      name: "github-localhost-20190319115623.json",
      size: 1.megabyte,
      content_type: "application/json"
    @user_account = create(
      :enterprise_installation_user_account,
      enterprise_installation: @business_installation,
      business_user_account: create(:business_user_account, user: nil, business: @business),
    )
    @user_account_email = create(
      :enterprise_installation_user_account_email,
      enterprise_installation_user_account: @user_account,
      email: "email@example.com",
      primary: true,
    )
  end

  context "validations" do
    test "requires an owner" do
      installation = EnterpriseInstallation.new
      installation.valid?

      refute_predicate installation.errors[:owner], :blank?
    end

    test "requires a valid owner type" do
      installation = EnterpriseInstallation.new(owner: create(:repository, :minimal))
      installation.valid?

      refute_predicate installation.errors[:owner_type], :blank?
    end

    test "requires a host_name" do
      installation = EnterpriseInstallation.new
      installation.valid?

      refute_predicate installation.errors[:host_name], :blank?
    end

    test "requires a customer_name" do
      installation = EnterpriseInstallation.new
      installation.valid?

      refute_predicate installation.errors[:customer_name], :blank?
    end

    test "requires a license_hash" do
      installation = EnterpriseInstallation.new
      installation.valid?

      refute_predicate installation.errors[:license_hash], :blank?
    end

    test "requires a license_public_key that is not nil" do
      installation = EnterpriseInstallation.new
      installation.valid?

      refute_predicate installation.errors[:license_public_key], :blank?
    end

    test "allows license_public_key to be an empty string" do
      installation = EnterpriseInstallation.new license_public_key: ""
      installation.valid?

      assert_predicate installation.errors[:license_public_key], :blank?
    end

    test "requires a server_id for >= 2.17" do
      installation = EnterpriseInstallation.new(version: "2.17")
      installation.valid?

      refute_predicate installation.errors[:server_id], :blank?

      installation.server_id = "abc123"
      installation.valid?

      refute_predicate installation.errors[:server_id], :blank?
    end

    test "does not require a valid server_id for < 2.17" do
      installation = EnterpriseInstallation.new(version: "2.16")
      installation.valid?

      assert_predicate installation.errors[:server_id], :blank?
    end
  end

  context "for_query scope" do
    test "returns scoped EnterpriseInstallations when query is blank" do
      results = EnterpriseInstallation.for_query("  ")
      assert_same_elements [@org_installation, @business_installation], results
      results = EnterpriseInstallation.for_query(nil)
      assert_same_elements [@org_installation, @business_installation], results
    end

    test "returns EnterpriseInstallations where customer_name matches query" do
      @business_installation.update! customer_name: "Very Serious Industries Ltd"
      results = EnterpriseInstallation.for_query("serious")
      assert_includes results, @business_installation
    end

    test "returns EnterpriseInstallations where host_name matches query" do
      @business_installation.update! host_name: "howveryserious.lol"
      results = EnterpriseInstallation.for_query("lol")
      assert_includes results, @business_installation
    end
  end

  context "#last_user_accounts_upload" do
    test "returns nil when there are no uploads" do
      @business_installation.user_accounts_uploads.destroy_all
      assert_nil @business_installation.last_user_accounts_upload
    end

    test "returns the most recent upload" do
      @business_installation.user_accounts_uploads.destroy_all

      Timecop.freeze(1.month.ago) do
        create :enterprise_installation_user_accounts_upload,
          business: @business, enterprise_installation: @business_installation
      end
      Timecop.freeze(5.days.ago) do
        create :enterprise_installation_user_accounts_upload,
          business: @business, enterprise_installation: @business_installation
      end
      latest = Timecop.freeze(1.day.ago) do
        create :enterprise_installation_user_accounts_upload,
          business: @business, enterprise_installation: @business_installation
      end

      assert_equal latest, @business_installation.last_user_accounts_upload
    end
  end

  context "blocked licenses" do
    test "block license" do
      refute EnterpriseInstallation.blocked?(@org_installation.license_hash)
      EnterpriseInstallation.block(@org_installation.license_hash)
      assert EnterpriseInstallation.blocked?(@org_installation.license_hash)
      EnterpriseInstallation.unblock(@org_installation.license_hash)
      refute EnterpriseInstallation.blocked?(@org_installation.license_hash)
    end
  end

  context ".valid_server_id" do
    test "returns true if version is nil" do
      assert EnterpriseInstallation.valid_server_id?(nil, nil)
    end

    test "returns true if version is < 2.17" do
      assert EnterpriseInstallation.valid_server_id?("2.16", nil)
    end

    test "returns false if server_id is nil for >= 2.17" do
      refute EnterpriseInstallation.valid_server_id?("2.17", nil)
    end

    test "returns false if server_id is not a valid uuid for >= 2.17" do
      refute EnterpriseInstallation.valid_server_id?("2.17", "test")
    end

    test "returns true if server_id is a valid uuid for >= 2.17" do
      assert EnterpriseInstallation.valid_server_id?("2.17", SecureRandom.uuid)
    end
  end

  context "#create_github_app" do
    test "creates a new application and secret for the installation" do
      app, secret = @org_installation.create_github_app
      refute_nil app
      refute_nil secret
      assert app.valid?
      refute_nil @org_installation.integration
      assert_equal app.id, @org_installation.integration_id
      assert_equal EnterpriseInstallation::GITHUB_APP_ICON_BACKGROUND_COLOR, app.bgcolor
    end

    test "creates a new application for the installation with public key" do
      private_key = OpenSSL::PKey::RSA.new(IntegrationKey::KEY_LENGTH)
      public_pem = private_key.public_key.to_pem
      app, secret = @org_installation.create_github_app(public_pem, @admin)
      refute_nil app
      refute_nil secret
      assert_equal 1, app.public_keys.count
      key = app.public_keys.first
      assert_equal public_pem, key.public_pem
      assert_equal @admin, key.creator
      assert app.valid?
      assert_equal app.id, @org_installation.integration_id
    end

    test "different apps have unique names and slugs even if host name is the same" do
      @org_installation.host_name = "github.example.org"
      app, secret = @org_installation.create_github_app
      refute_nil app
      refute_nil secret
      assert app.valid?
      assert_equal app.id, @org_installation.integration_id
      assert app.name.starts_with?("GitHub Enterprise for github.example.org")
      assert app.slug.starts_with?("ghe-github-example-org-")

      org_installation2 = create(:enterprise_installation, owner: @org, host_name: "github.example.org")
      app2, secret2 = org_installation2.create_github_app
      refute_nil app2
      refute_nil secret2
      assert app2.valid?
      assert_equal app2.id, org_installation2.integration_id
      assert app2.name.starts_with?("GitHub Enterprise for github.example.org")
      assert app2.slug.starts_with?("ghe-github-example-org-")

      refute_equal app.name, app2.name
      refute_equal app.slug, app2.slug
      refute_equal app.bot.login, app2.bot.login
    end

    test "name and slug are suffixed only when needed" do
      org_installation1 = create(:enterprise_installation, owner: @org, host_name: "github.example.org")
      app1, secret1 = org_installation1.create_github_app
      assert_equal "GitHub Enterprise for github.example.org", app1.name
      assert_equal "ghe-github-example-org-1", app1.slug

      org_installation2 = create(:enterprise_installation, owner: @org, host_name: "github.example.org")
      app2, secret2 = org_installation2.create_github_app
      assert_equal "GitHub Enterprise for github.example.org (2)", app2.name
      assert_equal "ghe-github-example-org-2", app2.slug
    end

    test "name and slug suffix match (as the minimum needed for both being unique)" do
      org_installation_a = create(:enterprise_installation, owner: @org, host_name: "github.example.org")
      org_installation_b = create(:enterprise_installation, owner: @org, host_name: "github.example.org")
      org_installation_a.create_github_app
      org_installation_b.create_github_app
      org_installation_a.github_app.update_column(:name, "GitHub Enterprise for github.example.org (2)")
      org_installation_b.github_app.update_column(:slug, "ghe-github-example-org-3")

      org_installation = create(:enterprise_installation, owner: @org, host_name: "github.example.org")
      app, secret = org_installation.create_github_app
      assert_equal "GitHub Enterprise for github.example.org (4)", app.name
      assert_equal "ghe-github-example-org-4", app.slug
    end

    test "ensures slug names don't contain double dashes" do
      @org_installation.host_name = "tjl2-0ec6ae17f40f98804.ghe-test.net"
      app, secret = @org_installation.create_github_app
      refute_nil app
      refute_nil secret
      assert app.valid?
      assert_equal app.id, @org_installation.integration_id
      assert app.name.starts_with?("GitHub Enterprise for tjl2-0ec6ae17f40f98804.ghe-test.net")
      assert app.slug.starts_with?("ghe-tjl2-0ec6ae17f40f98804-")
      refute app.slug.starts_with?("ghe-tjl2-0ec6ae17f40f98804--")
    end

    test "app creation works fine even with long domains" do
      @org_installation.host_name = "sit.suscipit.repellendus.repudiandae.sunt.odiogithub.expecto.patronus.example.org"
      app, secret = @org_installation.create_github_app
      refute_nil app
      refute_nil secret
      assert app.valid?
    end

    test "sets the expected callback URLs" do
      app, _ = assert_difference "ApplicationCallbackUrl.count", 1 do
        @org_installation.create_github_app
      end

      refute_nil app
      assert_predicate app, :valid?

      refute_nil @org_installation.integration
      assert_equal app.id, @org_installation.integration_id

      expected_callback_url = UrlHelpers.settings_dotcom_user_callback_url(
        host: @org_installation.host_name,
        protocol: "https"
      )

      assert_same_elements [expected_callback_url], app.application_callback_urls.map(&:url)
      assert_nil app.read_attribute(:callback_url)
    end
  end

  context "#github_app" do
    test "fetches the existing application for the installation" do
      app, secret = @org_installation.create_github_app
      refute_nil app
      refute_nil secret
      assert app.valid?

      inst = EnterpriseInstallation.find(@org_installation.id)
      app2 = inst.github_app
      refute_nil app2
      assert_equal app.id, app2.id
    end

    test "returns nil if github app doesn't exist" do
      assert_nil @org_installation.github_app
    end
  end

  test "removes the application on destroy" do
    app, secret = @org_installation.create_github_app
    @org_installation.destroy
    assert_nil Integration.find_by(id: app.id)
  end

  context "#github_app?" do
    test "true when there's a GitHub App for the installation" do
      @business_installation.create_github_app
      assert_predicate @business_installation, :github_app?
    end

    test "false when there's no GitHub App for the installation" do
      refute_predicate @business_installation, :github_app?
    end
  end

  context "#connected?" do
    test "true when there's a GitHub App for the installation" do
      @business_installation.create_github_app
      assert_predicate @business_installation, :connected?
    end

    test "false when there's no GitHub App for the installation" do
      refute_predicate @business_installation, :connected?
    end
  end

  context "#has_required_github_app_permissions?" do
    test "returns false if app doesn't exist" do
      refute @org_installation.has_required_github_app_permissions?(:search)
      refute @org_installation.has_required_github_app_permissions?(:contributions)
    end

    test "validates if app has required permissions for a feature" do
      @org_installation.create_github_app
      assert @org_installation.has_required_github_app_permissions?(:search)
      refute @org_installation.has_required_github_app_permissions?(:contributions)
    end
  end

  context "#required_github_app_permissions" do
    test "search requires no specific permissions" do
      assert_equal({}, @org_installation.required_github_app_permissions(:search))
    end

    test "contributions requires external_contributions with write permission" do
      assert_equal({ "external_contributions" => :write }, @org_installation.required_github_app_permissions(:contributions))
    end

    test "content_analysis (aka vulnerability scan) requires enterprise_vulnerabilities with read permission" do
      assert_equal({ "enterprise_vulnerabilities" => :read }, @org_installation.required_github_app_permissions(:content_analysis))
    end

    test "private_search requires read permission on our search's scope" do
      assert_equal({ "contents" => :read, "issues" => :read, "metadata" => :read }, @org_installation.required_github_app_permissions(:private_search))
    end
  end

  context "#github_app_permissions" do
    test "#github_app_permissions combines permission requirements for multiple features" do
      contrib_perms = @org_installation.required_github_app_permissions(:contributions)
      content_perms = @org_installation.required_github_app_permissions(:content_analysis)
      private_perms = @org_installation.required_github_app_permissions(:private_search)
      two_perms = contrib_perms.merge(content_perms)
      all_perms = two_perms.merge(private_perms)

      assert_equal({}, @org_installation.github_app_permissions([:search]))
      assert_equal(contrib_perms, @org_installation.github_app_permissions([:search, :contributions]))
      assert_equal(content_perms, @org_installation.github_app_permissions([:search, :content_analysis]))
      assert_equal(private_perms, @org_installation.github_app_permissions([:search, :private_search]))
      assert_equal(two_perms, @org_installation.github_app_permissions([:search, :content_analysis, :contributions]))
      assert_equal(all_perms, @org_installation.github_app_permissions([:search, :content_analysis, :contributions, :private_search]))
    end
  end

  context "#request_github_app_permissions_update" do
    test "does not update if app doesn't exist" do
      version = @org_installation.request_github_app_permissions_update([:search, :contributions])
      assert_nil version
    end

    test "requests an update if required permissions are not met" do
      @org_installation.create_github_app
      version = @org_installation.request_github_app_permissions_update([:search, :contributions])
      refute_nil version
      assert_equal({ "external_contributions" => :write }, version.default_permissions)
    end

    test "does not request an update if required permissions are already enabled" do
      @org_installation.create_github_app
      version = @org_installation.request_github_app_permissions_update(["search"])
      assert_nil version

      @org_installation.github_app.update(default_permissions: { "external_contributions" => :write })
      @org_installation.github_app.reload
      version = @org_installation.request_github_app_permissions_update(%w[search contributions])
      assert_nil version
    end

    test "requests an update if non-required permissions are enabled to remove those" do
      @org_installation.create_github_app
      @org_installation.github_app.update(default_permissions: { "external_contributions" => :write })
      @org_installation.github_app.reload
      version = @org_installation.request_github_app_permissions_update(["search"])
      refute_nil version
      assert_equal({}, version.default_permissions)
    end
  end

  context "#github_app_latest_version_diff" do
    test "returns diff even without a permissions change" do
      app, _ = @org_installation.create_github_app
      app.install_on(@org, repositories: [], installer: @admin, entry_point: :test_case).installation

      diff = @org_installation.github_app_latest_version_diff
      assert_instance_of IntegrationVersion::Differ::Result, diff
      assert_equal({}, diff.permissions_added)
      assert_equal({}, diff.permissions_removed)
    end

    test "returns diff for proposed added permissions" do
      app, _ = @org_installation.create_github_app
      app.install_on(@org, repositories: [], installer: @admin, entry_point: :test_case).installation

      version = @org_installation.request_github_app_permissions_update([:search, :contributions])
      refute_nil version

      diff = @org_installation.github_app_latest_version_diff
      assert_instance_of IntegrationVersion::Differ::Result, diff
      assert_equal({ "external_contributions" => :write }, diff.permissions_added)
    end
  end

  context "#user_has_access?" do
    test "returns false if github app is not created" do
      user = create(:user)
      refute @org_installation.user_has_access?(user)
    end

    test "returns false if user does not have oauth sign in" do
      user = create(:user)
      @org_installation.create_github_app
      refute @org_installation.user_has_access?(user)
    end

    test "returns true if user is signed in with oauth" do
      user = create(:user)
      @org_installation.create_github_app
      user.oauth_authorizations.create!(application: @org_installation.github_app)
      assert @org_installation.user_has_access?(user)
    end
  end

  context "instrumentation" do
    test "triggers enterprise_installation.create after create" do
      events = subscribe "enterprise_installation.create"
      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:increment).with("github_connect.connected")
      GitHub.dogstats.expects(:increment).with("github_connect.connect")
      installation = create(:enterprise_installation, owner: @org)

      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        enterprise_installation_id: installation.id,
        enterprise_installation: "github.example.com",
        http_only: false,
        customer_name: installation.customer_name,
      }
      instrumentation_event = events.pop

      assert_equal "enterprise_installation.create", instrumentation_event.name
      assert_equal expected_payload, instrumentation_event.payload
    end

    if GitHub.hydro_enabled?
      test "publishes a hydro event after create" do
        installation = create :enterprise_installation, owner: @business

        assert_hydro_published({
          enterprise_installation: Hydro::EntitySerializer.enterprise_installation(installation),
        }, schema: "github.github_connect.v0.Connect")
      end
    end

    test "triggers enterprise_installation.updated after updating installation" do
      events = subscribe "enterprise_installation.updated"
      installation = create(:enterprise_installation, owner: @org)
      installation.update(version: "2.14.0")

      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        enterprise_installation_id: installation.id,
        enterprise_installation: "github.example.com",
        http_only: false,
        customer_name: installation.customer_name,
      }
      instrumentation_event = events.pop

      assert_equal "enterprise_installation.updated", instrumentation_event.name
      assert_equal expected_payload, instrumentation_event.payload
    end

    test "triggers enterprise_installation.destroy after removing installation" do
      events = subscribe "enterprise_installation.destroy"
      installation = create(:enterprise_installation, owner: @org)
      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:decrement).with("github_connect.connected")
      GitHub.dogstats.expects(:increment).with("github_connect.disconnect")
      installation.destroy

      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        enterprise_installation_id: installation.id,
        enterprise_installation: "github.example.com",
        http_only: false,
        customer_name: installation.customer_name,
      }
      instrumentation_event = events.pop

      assert_equal "enterprise_installation.destroy", instrumentation_event.name
      assert_equal expected_payload, instrumentation_event.payload
    end
  end

  context "storing and retrieving the user's login on a given installation" do
    test "remote login is nil if never set for this install" do
      assert_nil @org_installation.login_for(@admin)
    end

    test "remote login can be set individually for each user-installation pair" do
      other_org = create(:organization, admin: @admin)
      other_org_installation = create(:enterprise_installation, owner: other_org)

      user1 = create(:user)
      user2 = create(:user)

      @org_installation.set_login_for(user1, "foo")
      @org_installation.set_login_for(user2, "bar")
      other_org_installation.set_login_for(user1, "baz")
      other_org_installation.set_login_for(user2, "bat")

      assert_equal "foo", @org_installation.login_for(user1)
      assert_equal "bar", @org_installation.login_for(user2)
      assert_equal "baz", other_org_installation.login_for(user1)
      assert_equal "bat", other_org_installation.login_for(user2)
    end

    test "raises ArgumentError (instead of setting) if remote login does not abide to dotcom login validation rules" do
      user = create(:user)
      old_login = "foo"
      invalid_login = "javascript:alert(1)"
      too_long_login = SecureRandom.alphanumeric(User::LOGIN_MAX_LENGTH + 1)
      @org_installation.set_login_for(user, old_login)

      assert_raises(ArgumentError) do
        @org_installation.set_login_for(user, invalid_login)
      end
      assert_equal old_login, @org_installation.login_for(user)

      assert_raises(ArgumentError) do
        @org_installation.set_login_for(user, too_long_login)
      end
      assert_equal old_login, @org_installation.login_for(user)
    end
  end

  context "#profile_url_for" do
    test "returns the URL of an user's profile in that instance" do
      @org_installation.set_login_for(@admin, "me-at-work")

      assert_equal "https://org.wtf/me-at-work", @org_installation.profile_url_for(@admin).to_s
    end

    test "falls back to the instance if we don't know the login" do
      assert_equal "https://org.wtf/", @org_installation.profile_url_for(@admin).to_s
    end
  end

  unless GitHub.enterprise?
    context "#clear_enterprise_contributions" do
      test "runs before destroy and removes all contributions" do
        EnterpriseContribution.destroy_all
        contrib = EnterpriseContribution.insert_or_update_contribution(@admin, @org_installation, Date.today, 1)
        assert_equal [contrib.id], EnterpriseContribution.all.map(&:id)
        perform_enqueued_jobs(only: [GitHubConnectDestroyInstallationContributionsJob]) do
          @org_installation.destroy!
        end
        assert_equal [], EnterpriseContribution.all.map(&:id)
      end
    end
  end

  context "#owner" do
    test "can be an organization" do
      installation = create(:enterprise_installation, owner: @org)
      assert installation.valid?
    end

    test "can be a business" do
      installation = create(:enterprise_installation, owner: @business)
      assert installation.valid?
    end
  end

  context "::synchronize_user_accounts_data" do
    test "enqueues SyncEnterpriseServerUserAccountsJob" do
      assert_enqueued_with \
        job: SyncEnterpriseServerUserAccountsJob,
        args: [@business, @business_installation, @upload.id, @admin] do

        EnterpriseInstallation.synchronize_user_accounts_data \
          business: @business,
          installation: @business_installation,
          upload_id: @upload.id,
          actor: @admin
      end
    end
  end

  context "#destroy" do
    test "destroys dependent user_accounts records in the background" do
      installation = create :enterprise_installation, owner: @business
      5.times do
        account = create :enterprise_installation_user_account,
          enterprise_installation: installation
        create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: account
      end

      assert_difference "EnterpriseInstallation.count", -1 do
        assert_difference "EnterpriseInstallationUserAccount.count", -5 do
          assert_difference "EnterpriseInstallationUserAccountEmail.count", -5 do
            perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
              installation.destroy
            end
          end
        end
      end
    end

    test "destroys dependent user_accounts_uploads records in the background" do
      installation = create :enterprise_installation, owner: @business
      5.times do
        account = create :enterprise_installation_user_accounts_upload,
          business: @business, enterprise_installation: installation
      end

      assert_difference "EnterpriseInstallation.count", -1 do
        assert_difference "EnterpriseInstallationUserAccountsUpload.count", -5 do
          perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
            installation.destroy
          end
        end
      end
    end
  end

  context "licensing" do
    include HydroTestHelpers

    test "publishes a license snapshot messages when an enterprise account owned installation is destroyed" do
      reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs(only: [Licensing::SnapshotLicensesJob, DestroyDependentRecordsJob]) do
        @business_installation.reload.destroy
      end

      assert_hydro_messages(count: 1, schema: "github.billing.v0.LicenseSnapshot")
    end

    test "does not publish a license snapshot messages when an organization owned installation is destroyed" do
      enterprise_installation = create(:enterprise_installation, owner: create(:organization))

      reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        enterprise_installation.destroy
      end

      assert_hydro_messages(count: 0, schema: "github.billing.v0.LicenseSnapshot")
    end
  end if GitHub.billing_enabled?
end
