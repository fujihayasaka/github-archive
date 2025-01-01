# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"
require "test_helpers/privileged_app_helper"

class OauthAuthorizationTest < GitHub::TestCase
  include PermissionsHelper
  include HydroTestHelpers

  fixtures do
    @user = create(:user, login: "user")
    @org = create(:organization, admin: @user)
    @app = create :oauth_application
    @scopes = %w(user repo)
    @github_org = make_trusted_oauth_apps_owner

    @ios_app = Apps::Privileged.oauth_application(:ios_mobile)
    @ios_app ||= create(
      :oauth_application,
      user_id: GitHub.trusted_oauth_apps_owner,
      name: "GitHub iOS",
    )
    PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :ios_mobile, app: @ios_app)
    @ios_access = make_oauth(@user, ["user"], @ios_app)

    @android_app = Apps::Privileged.oauth_application(:android_mobile)
    @android_app ||= create(
      :oauth_application,
      user_id: GitHub.trusted_oauth_apps_owner,
      name: "GitHub Android",
    )
    PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :android_mobile, app: @android_app)
    @android_access = make_oauth(@user, ["user"], @android_app)
  end

  setup do
    ActionMailer::Base.deliveries.clear
  end

  test "requires user" do
    authorization = build(:oauth_authorization, user: nil)
    refute authorization.valid?
    assert authorization.errors[:user_id].any?
  end

  test "rejects an Organization as user" do
    authorization = build(:oauth_authorization, user: @org)
    refute authorization.valid?
    assert authorization.errors[:user_id].any?
  end

  test "requires valid scopes" do
    authorization = build(:oauth_authorization, scopes: ["user", :booya])
    assert !authorization.valid?
    assert authorization.errors[:scopes].any?
  end

  test "requires application" do
    authorization = build(:oauth_authorization, application: nil)
    assert !authorization.valid?
    assert authorization.errors[:application_id].any?
  end

  test "deleting an authorization deletes all associated objects" do
    repo = create(:repository, :minimal, owner: @user)
    access = create(:personal_token_oauth_access_with_token, user: @user, application: @app)
    authorization = access.authorization
    user = User.with_oauth_hashed_token(access.hashed_token)
    assert_equal @user, user
    public_key = user.public_keys.create_with_verification(
      key: Sham.ssh_public_key,
      oauth_authorization: authorization,
      verifier: user,
    )

    deploy_key = repo.public_keys.create_with_verification(
      key: Sham.ssh_public_key,
      oauth_authorization: authorization,
      verifier: user,
    )

    authorization.reload

    refute_nil authorization
    assert_equal authorization, public_key.oauth_authorization

    assert_difference "PublicKey.count", -2 do
      assert_difference [
        "OauthAuthorization.count",
        "OauthAccess.count",
      ], -1 do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { authorization.destroy }
      end
    end

    refute PublicKey.find_by(id: public_key.id)
    refute PublicKey.find_by(id: deploy_key.id)
  end

  test "deleting an authorization removes associated permission records" do
    integration = create(:integration, default_permissions: { "emails" => :read })
    access = create(:oauth_access, user: @user, application: integration)

    authorization = access.authorization
    subject       = @user.resources.emails

    assert_predicate access, :valid?
    assert_able authorization, :read, subject

    assert_granted_in_permissions_table(
      actor_id:     authorization.ability_id,
      actor_type:   authorization.ability_type,
      subject_id:   subject.ability_id,
      subject_type: subject.ability_type,
    )

    assert_equal 1, @user.oauth_accesses.where(id: access.id).count
    assert_equal 1, integration.accesses.where(user: @user).count

    authorization.destroy

    refute authorization.accesses.any?
    assert_equal 0, @user.oauth_accesses.where(id: access.id).count
    refute integration.accesses.where(user: @user).any?

    refute_granted_in_permissions_table(
      actor_id:     authorization.ability_id,
      actor_type:   authorization.ability_type,
      subject_id:   subject.ability_id,
      subject_type: subject.ability_type,
    )
  end

  test "deleting a GitHub Mobile authorization removes associated oauth record" do
    Notifyd::DeviceTokensService.expects(:delete_all).with(user_id: @user.id).once.returns(true)

    authorization = @ios_access.authorization
    assert_predicate @ios_access, :valid?

    assert_equal 1, @user.oauth_accesses.where(id: @ios_access.id).count

    authorization.destroy

    assert_equal 0, @user.oauth_accesses.where(id: @ios_access.id).count
  end

  test "deleting the GitHub iOS authorization also removes the user's mobile device auth key" do
    Notifyd::DeviceTokensService.expects(:delete_all).with(user_id: @user.id).once.returns(true)

    authorization = @ios_access.authorization

    access_ids = @user.oauth_accesses.where(application: @ios_app).pluck(:id)
    assert_equal 1, access_ids.count

    Timecop.freeze do
      assert_enqueued_with job: DestroyMobileAuthDeviceKeysJob, args: [@user, authorization.id, @ios_app, access_ids] do
        authorization.destroy
        assert_equal 0, @user.oauth_accesses.where(id: @ios_access.id).count
      end
    end
  end

  test "deleting the GitHub Android authorization also removes the user's mobile device auth key" do
    Notifyd::DeviceTokensService.expects(:delete_all).with(user_id: @user.id).once.returns(true)

    authorization = @android_access.authorization

    access_ids = @user.oauth_accesses.where(application: @android_app).pluck(:id)
    assert_equal 1, access_ids.count

    Timecop.freeze do
      assert_enqueued_with job: DestroyMobileAuthDeviceKeysJob, args: [@user, authorization.id, @android_app, access_ids] do
        authorization.destroy
        assert_equal 0, @user.oauth_accesses.where(id: @android_access.id).count
        assert_equal 1, @user.oauth_accesses.where(id: @ios_access.id).count
      end
    end
  end

  test "deleting an authorization that is not for a GitHub mobile app does not enqueue a job" do
    Notifyd::DeviceTokensService.expects(:delete_all).with(user_id: @user.id).never

    integration = create(:integration, default_permissions: { "emails" => :read })
    access = create(:oauth_access, user: @user, application: integration)

    authorization = access.authorization

    Timecop.freeze do
      assert_enqueued_jobs(0, only: [DestroyMobileAuthDeviceKeysJob]) do
        authorization.destroy
        assert_empty @user.oauth_accesses.where(application: authorization.application)
      end
    end
  end

  test "#bump enqueues job to do the write" do
    with_cache_enabled do
      Timecop.freeze(Time.zone.now) do
        oauth_authorization = create(:oauth_authorization, accessed_at: nil)
        assert_nil GitHub.cache.get("oauth_authorizations:last_accessed:#{oauth_authorization.id}")

        oauth_authorization.bump

        assert_enqueued_jobs 1, only: OauthAuthorizationBumpJob, queue: :oauth_authorization_bumps
        assert_nil oauth_authorization.reload.accessed_at
        assert_equal Time.zone.now, GitHub.cache.get("oauth_authorizations:last_accessed:#{oauth_authorization.id}")
      end
    end
  end

  test "#bump can update for a specific time" do
    perform_enqueued_jobs(only: [OauthAuthorizationBumpJob]) do
      with_cache_enabled do
        now = Time.at(1542131343)
        Timecop.freeze(now) do
          oauth_authorization = create(:oauth_authorization, accessed_at: nil)
          assert_nil GitHub.cache.get("oauth_authorizations:last_accessed:#{oauth_authorization.id}")

          oauth_authorization.bump(now)

          assert_equal now.to_i, oauth_authorization.reload.accessed_at.to_i
          assert_equal now, GitHub.cache.get("oauth_authorizations:last_accessed:#{oauth_authorization.id}")
        end
      end
    end
  end

  context "#can_have_granular_user_permissions" do
    test "returns true for integration application types" do
      integration   = create(:integration)
      authorization = create(:oauth_access, user: @user, application: integration).authorization

      assert_predicate authorization, :integration_application_type?
      assert_predicate authorization, :can_have_granular_user_permissions?
    end

    test "returns false for oauth application types" do
      authorization = create(:oauth_access, user: @user, application: @app).authorization

      refute_predicate authorization, :integration_application_type?
      refute_predicate authorization, :can_have_granular_user_permissions?
    end
  end

  context "upgradedable_without_user_permission?" do
    test "returns false if the authorization doesn't have an integration version" do
      integration   = create(:integration)
      authorization = create(:oauth_access, user: @user, application: integration).authorization

      authorization.update(integration_version_number: nil)
      authorization.reload

      assert_nil authorization.integration_version_number
      refute_predicate authorization, :upgradedable_without_user_permission?
    end

    test "returns true if the authorization's version is not outdated" do
      integration   = create(:integration)
      authorization = create(:oauth_access, user: @user, application: integration).authorization

      assert_equal authorization.integration_version_number, integration.latest_version.number
      assert_predicate authorization, :upgradedable_without_user_permission?
    end

    test "returns false if user permissions were added" do
      integration   = create(:integration)
      authorization = create(:oauth_access, user: @user, application: integration).authorization
      integration.versions.create(default_permissions: { "emails" => :read })

      assert_predicate authorization.reload, :outdated?
      refute_predicate authorization, :upgradedable_without_user_permission?
    end

    test "returns false if user permissions were upgraded" do
      integration   = create(:integration, default_permissions: { "emails" => :read })
      authorization = create(:oauth_access, user: @user, application: integration).authorization
      integration.versions.create(default_permissions: { "emails" => :write })

      assert_predicate authorization.reload, :outdated?
      refute_predicate authorization, :upgradedable_without_user_permission?
    end

    test "returns true if user permissions were removed" do
      integration   = create(:integration, default_permissions: { "emails" => :read })
      authorization = create(:oauth_access, user: @user, application: integration).authorization
      integration.versions.create

      assert_predicate authorization.reload, :outdated?
      assert_predicate authorization, :upgradedable_without_user_permission?
    end

    test "returns true if user permissions were downgraded" do
      integration   = create(:integration, default_permissions: { "emails" => :write })
      authorization = create(:oauth_access, user: @user, application: integration).authorization
      integration.versions.create(default_permissions: { "emails" => :read })

      assert_predicate authorization.reload, :outdated?
      assert_predicate authorization, :upgradedable_without_user_permission?
    end

    test "returns true if user permissions were not changed" do
      integration   = create(:integration, default_permissions: { "emails" => :write })
      authorization = create(:oauth_access, user: @user, application: integration).authorization
      integration.versions.create(default_permissions: { "emails" => :write })

      assert_predicate authorization.reload, :outdated?
      assert_predicate authorization, :upgradedable_without_user_permission?
    end
  end

  context "accesses" do
    test "requires access user to match authorization user" do
      access = create :oauth_access
      assert_equal access.user, access.authorization.user
      access.user = create(:user)
      refute access.valid?
      assert access.errors[:user_id].any?
    end

    test "creating an access creates an authorization" do
      assert_difference "OauthAuthorization.count", 1 do
        access = create(:oauth_access, user: @user, application: @app)
        refute_nil access.authorization
        assert_equal @app, access.authorization.application
        assert_equal @user, access.authorization.user
      end
    end

    test "creating more than one access for an application does not create new authorization " do
      assert_difference "OauthAuthorization.count", 1 do
        access1 = create(:oauth_access, user: @user, application: @app)
        access2 = create(:oauth_access, user: @user, application: @app)
        refute_nil access1.authorization
        refute_nil access2.authorization
        assert_equal access1.authorization, access2.authorization
      end
    end

    test "creating a personal access token always creates a new authorization " do
      assert_difference "OauthAuthorization.count", 2 do
        access1 = create(:personal_token_oauth_access, user: @user)
        access2 = create(:personal_token_oauth_access, user: @user)
        refute_nil access1.authorization
        refute_nil access2.authorization
        refute_equal access1.authorization, access2.authorization
        assert_equal OauthApplication::PERSONAL_TOKENS_APPLICATION_ID, access1.authorization.application_id
        assert_equal OauthApplication::PERSONAL_TOKENS_APPLICATION_ID, access2.authorization.application_id
      end
    end

    test "creating an access with an integration that has user permissions grants them to the new authorization" do
      integration = create(:integration, default_permissions: { "emails" => :read })
      access = create(:oauth_access, user: @user, application: integration)

      assert_predicate access, :valid?
      assert @user.resources.emails.readable_by?(access)
    end

    test "creating an access with an integration that has new non user permissions grants them a new authorization" do
      integration = create(:integration, default_permissions: { "issues" => :read })
      access = create(:oauth_access, user: @user, application: integration)

      assert_predicate access, :valid?
      assert_empty access.authorization.abilities
    end

    context "adding permissions" do
      test "user permissions can be added to an existing authorization" do
        integration = create(:integration)
        access = create(:oauth_access, user: @user, application: integration)

        assert_predicate access, :valid?
        refute @user.resources.emails.readable_by?(access)

        integration.versions.create(default_permissions: { "emails" => :read })
        access = create(:oauth_access, user: @user, application: integration)

        assert_predicate access, :valid?
        assert @user.resources.emails.readable_by?(access)
      end
    end

    test "authorizations will be upgraded if there are only non user permissions added" do
      integration        = create(:integration)
      access             = create(:oauth_access, user: @user, application: integration)
      old_version_number = access.authorization.integration_version.number

      assert_predicate access, :valid?
      assert_empty access.authorization.abilities

      integration.versions.create(default_permissions: { "issues" => :read })
      access = create(:oauth_access, user: @user, application: integration)

      assert_predicate access, :valid?
      assert_empty access.authorization.abilities
      assert access.authorization.integration_version_number > old_version_number
    end

    context "removing permissions" do
      test "is successful for an existing authorization" do
        integration = create(:integration, default_permissions: { "emails" => :read })
        access = create(:oauth_access, user: @user, application: integration)

        assert_predicate access, :valid?
        assert @user.resources.emails.readable_by?(access)

        integration.versions.create
        access = create(:oauth_access, user: @user, application: integration)

        assert_predicate access, :valid?
        refute @user.resources.emails.readable_by?(access)
      end
    end

    test "authorizations will be upgraded if there are non user permissions removed" do
      integration        = create(:integration, default_permissions: { "issues" => :read })
      access             = create(:oauth_access, user: @user, application: integration)
      old_version_number = access.authorization.integration_version.number

      assert_predicate access, :valid?
      assert_empty access.authorization.abilities

      integration.versions.create
      access = create(:oauth_access, user: @user, application: integration)

      assert_predicate access, :valid?
      assert_empty access.authorization.abilities
      assert access.authorization.integration_version_number > old_version_number
    end

    context "upgrading permissions" do
      test "is successful for an existing authorization" do
        integration = create(:integration, default_permissions: { "emails" => :read })
        access = create(:oauth_access, user: @user, application: integration)

        assert_predicate access, :valid?
        assert @user.resources.emails.readable_by?(access)

        integration.versions.create(default_permissions: { "emails" => :write })
        access = create(:oauth_access, user: @user, application: integration)

        assert_predicate access, :valid?
        assert @user.resources.emails.writable_by?(access)
      end
    end

    test "authorizations will be upgraded if there are non user permissions upgraded" do
      integration        = create(:integration, default_permissions: { "issues" => :read })
      access             = create(:oauth_access, user: @user, application: integration)
      old_version_number = access.authorization.integration_version.number

      assert_predicate access, :valid?
      assert_empty access.authorization.abilities

      integration.versions.create(default_permissions: { "issues" => :write })
      access = create(:oauth_access, user: @user, application: integration)

      assert_predicate access, :valid?
      assert_empty access.authorization.abilities
      assert access.authorization.integration_version_number > old_version_number
    end

    context "downgrading permissions" do
      test "is successful for an existing authorization" do
        integration = create(:integration, default_permissions: { "emails" => :write })
        access = create(:oauth_access, user: @user, application: integration)

        assert_predicate access, :valid?
        assert @user.resources.emails.writable_by?(access)

        integration.versions.create(default_permissions: { "emails" => :read })
        access = create(:oauth_access, user: @user, application: integration)

        assert_predicate access, :valid?
        assert @user.resources.emails.readable_by?(access)
      end
    end

    test "authorizations will be upgraded if there are non user permissions downgraded" do
      integration        = create(:integration, default_permissions: { "issues" => :read })
      access             = create(:oauth_access, user: @user, application: integration)
      old_version_number = integration.latest_version.number

      assert_predicate access, :valid?
      assert_empty access.authorization.abilities

      integration.versions.create(default_permissions: { "issues" => :write })
      access = create(:oauth_access, user: @user, application: integration)

      assert_predicate access, :valid?
      assert_empty access.authorization.abilities
      assert access.authorization.integration_version_number > old_version_number
    end

    test "trying to associate an additional personal access token with an existing authorization fails" do
      access1 = create(:personal_token_oauth_access, user: @user)
      access2 = create(:personal_token_oauth_access, user: @user)
      access2.authorization = access1.authorization
      refute access2.valid?
      assert access2.errors[:authorization_id].any?
    end

    test "does not delete authorization until the last access is destroyed" do
      access1 = T.let(nil, T.nilable(OauthAccess))
      access2 = T.let(nil, T.nilable(OauthAccess))

      assert_difference "OauthAuthorization.count", 1 do
        access1 = create(:oauth_access, user: @user, application: @app)
        access2 = create(:oauth_access, user: @user, application: @app)
      end

      access1 = T.must(access1)
      access2 = T.must(access2)

      assert_difference "OauthAuthorization.count", 0 do
        access2.destroy
      end

      assert_difference "OauthAuthorization.count", -1 do
        access1.destroy
      end

      assert_equal access1.authorization_id, access2.authorization_id
      assert_nil OauthAuthorization.find_by(id: access1.authorization_id)
    end

    test "changing scopes for an access updates the scopes in the authorization" do
      access = create(:oauth_access, user: @user, application: @app, scopes: @scopes.slice(0, 1))
      assert_same_elements @scopes.slice(0, 1), access.authorization.scopes
      access.scopes = @scopes.slice(1, 1)
      access.save!
      assert_same_elements @scopes, access.authorization.scopes
    end

    test "changing scopes for a personal access token replaces the scopes in the authorization" do
      access = create(:personal_token_oauth_access, description: "Note1", scopes: @scopes.slice(0, 1))
      assert_same_elements @scopes.slice(0, 1), access.authorization.scopes
      access.scopes = @scopes.slice(1, 1)
      access.save!
      assert_same_elements @scopes.slice(1, 1), access.authorization.scopes
    end

    test "adding different scopes to two different accesses updates the authorization" do
      access1 = create(:oauth_access, user: @user, application: @app, scopes: @scopes.slice(0, 1))
      access2 = create(:oauth_access, user: @user, application: @app, scopes: @scopes.slice(1, 1))
      access1.reload
      refute_nil access1.authorization
      assert_equal access1.authorization, access2.authorization
      assert_same_elements @scopes, access1.authorization.scopes
    end

    test "deleting an access does not remove scopes from the authorization" do
      access1 = create(:oauth_access, user: @user, application: @app, scopes: @scopes.slice(0, 1))
      access2 = create(:oauth_access, user: @user, application: @app, scopes: @scopes.slice(1, 1))
      access1.reload
      assert_same_elements @scopes, access1.authorization.scopes
      assert_difference "OauthAccess.count", -1 do
        access2.destroy
      end
      assert_same_elements @scopes, access1.authorization.scopes
    end

    test "changing description of a personal access token updates the authorization description" do
      access = create(:personal_token_oauth_access, description: "Note1")
      assert_equal "Note1", access.authorization.description
      access.description = "Note2"
      access.save!
      assert_equal "Note2", access.authorization.description
    end

    test "changing description of a third-party access does not update the authorization description" do
      access = create(:oauth_access, description: "Note1")
      assert_nil access.authorization.description
      access.description = "Note2"
      access.save!
      assert_nil access.authorization.description
    end
  end

  # Tests related to how public keys relate to an OauthAuthorization
  context "public keys" do
    test "creating a public key from an access authenticated user associates it with an authorization" do
      access = create(:oauth_access_with_token, user: @user, application: @app)
      user = User.with_oauth_hashed_token(access.hashed_token)
      assert_equal @user, user
      public_key = user.public_keys.create_with_verification(
        title: "Test1",
        key: Sham.ssh_public_key,
        oauth_authorization: user.oauth_access.authorization,
        verifier: user,
      )
      refute_nil access.authorization
      assert_equal access.authorization, public_key.oauth_authorization
    end

    test "both the public key and access must be deleted to delete the authorization" do
      access = create(:oauth_access_with_token, user: @user, application: @app)
      user = User.with_oauth_hashed_token(access.hashed_token)
      assert_equal @user, user
      public_key = user.public_keys.create_with_verification(
        key: Sham.ssh_public_key,
        oauth_authorization: user.oauth_access.authorization,
        verifier: user,
      )

      assert_difference "OauthAuthorization.count", 0 do
        public_key.destroy
      end

      assert_difference "OauthAuthorization.count", -1 do
        access.destroy
      end

      access = create(:oauth_access_with_token, user: @user, application: @app)
      user = User.with_oauth_hashed_token(access.hashed_token)
      assert_equal @user, user
      public_key = user.public_keys.create_with_verification(
        key: Sham.ssh_public_key,
        oauth_authorization: user.oauth_access.authorization,
        verifier: user,
      )

      assert_difference "OauthAuthorization.count", 0 do
        access.destroy
      end

      assert_difference "OauthAuthorization.count", -1 do
        public_key.destroy
      end
    end

    # Personal access tokens only ever have one access associated with them. So,
    # when the access is destroyed, all resources associated with the personal
    # access token should also be destroyed.
    test "only the access must be deleted to delete the authorization for personal access tokens" do
      access = create(:personal_token_oauth_access_with_token, user: @user)
      user = User.with_oauth_hashed_token(access.hashed_token)
      assert_equal @user, user
      public_key = user.public_keys.create_with_verification(
        key: Sham.ssh_public_key,
        oauth_authorization: user.oauth_access.authorization,
        verifier: user,
      )

      assert_difference "OauthAuthorization.count", 0 do
        public_key.destroy
      end

      assert_difference "OauthAuthorization.count", -1 do
        access.destroy
      end

      access = create(:personal_token_oauth_access_with_token, user: @user)
      user = User.with_oauth_hashed_token(access.hashed_token)
      assert_equal @user, user
      public_key = user.public_keys.create_with_verification(
        key: Sham.ssh_public_key,
        oauth_authorization: user.oauth_access.authorization,
        verifier: user,
      )

      assert_difference "OauthAuthorization.count", -1 do
        access.destroy
      end
    end
  end

  context "instrumentation" do
    test "instruments creation" do
      events = subscribe "oauth_authorization.create"
      scopes = ["user"]
      access = create(:oauth_access,
        user: @user,
        application: @app,
        scopes: scopes,
      )

      expected_payload = {
        oauth_authorization_id: access.authorization.id,
        scopes: scopes,
        token_scopes: "user",
        application_id: @app.id,
        application_type: "OauthApplication",
        application_name: @app.name,
        org_id: [@org.id],
        org: [@org.login],
        user: @user.login,
        user_id: @user.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    # Testing PATs because they are unique in that there is no OauthApplication
    # associated with them. So, we want to make sure that `application_name` is
    # logged correctly.
    test "instruments creation for personal access token" do
      events = subscribe "oauth_authorization.create"
      scopes = ["user"]
      access = create(:personal_token_oauth_access,
        user: @user,
        scopes: scopes,
      )

      expected_payload = {
        oauth_authorization_id: access.authorization.id,
        scopes: scopes,
        token_scopes: "user",
        application_id: 0,
        application_type: "OauthApplication",
        application_name: access.description,
        org_id: [@org.id],
        org: [@org.login],
        user: @user.login,
        user_id: @user.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments creation for authorization belonging to an Integration" do
      integration = create(:integration)

      events = subscribe "oauth_authorization.create"
      access = create(:oauth_access,
        user: @user,
        application: integration,
        scopes: nil,
      )

      expected_payload = {
        oauth_authorization_id: access.authorization.id,
        scopes: nil,
        token_scopes: "",
        application_id: integration.id,
        application_type: "Integration",
        application_name: integration.name,
        user: @user.login,
        user_id: @user.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments update when scopes changes" do
      events = subscribe "oauth_authorization.update"

      scopes = ["user"]
      access = create(:oauth_access, user: @user, application: @app)
      assert_nil access.scopes
      access.change_scopes(scopes)

      expected_payload = {
        oauth_authorization_id: access.authorization.id,
        scopes: scopes,
        token_scopes: "user",
        application_id: @app.id,
        application_type: "OauthApplication",
        application_name: @app.name,
        org_id: [@org.id],
        org: [@org.login],
        user: @user.login,
        user_id: @user.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments authorization destroy when access is destroyed without explanation" do
      events = subscribe "oauth_authorization.destroy"

      access = create(:oauth_access, user: @user, application: @app)
      access.destroy

      expected_payload = {
        oauth_authorization_id: access.authorization.id,
        scopes: nil,
        token_scopes: "",
        application_id: @app.id,
        application_type: "OauthApplication",
        application_name: @app.name,
        org_id: [@org.id],
        org: [@org.login],
        user: @user.login,
        user_id: @user.id,
        explanation: nil,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments authorization destroy without explanation" do
      events = subscribe "oauth_authorization.destroy"

      access = create(:oauth_access, user: @user, application: @app)
      access.authorization.destroy

      expected_payload = {
        oauth_authorization_id: access.authorization.id,
        scopes: nil,
        token_scopes: "",
        application_id: @app.id,
        application_type: "OauthApplication",
        application_name: @app.name,
        org_id: [@org.id],
        org: [@org.login],
        user: @user.login,
        user_id: @user.id,
        explanation: nil,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "increments a stat indicating how an authorization is destroyed" do
      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:increment).with("account_security.oauth_authorization", has_entry(:tags, ["explanation:web-user", "action:destroy"]))
      access = create(:oauth_access, user: @user, application: @app)
      access.destroy_with_explanation(:web_user, entry_point: :test_case)
    end

    test "instruments authorization destroy when access is destroyed with specific explanation" do
      events = subscribe "oauth_authorization.destroy"

      access = create(:oauth_access, user: @user, application: @app)
      access.destroy_with_explanation(:stale, entry_point: :test_case)

      expected_payload = {
        oauth_authorization_id: access.authorization.id,
        scopes: nil,
        token_scopes: "",
        application_id: @app.id,
        application_type: "OauthApplication",
        application_name: @app.name,
        org_id: [@org.id],
        org: [@org.login],
        user: @user.login,
        user_id: @user.id,
        explanation: :stale,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments authorization destroy with specific explanation" do
      events = subscribe "oauth_authorization.destroy"

      access = create(:oauth_access, user: @user, application: @app)
      access.authorization.destroy_with_explanation(:stale, entry_point: :test_case)

      expected_payload = {
        oauth_authorization_id: access.authorization.id,
        scopes: nil,
        token_scopes: "",
        application_id: @app.id,
        application_type: "OauthApplication",
        application_name: @app.name,
        org_id: [@org.id],
        org: [@org.login],
        user: @user.login,
        user_id: @user.id,
        explanation: :stale,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    if GitHub.guard_audit_log_staff_actor?
      test "hides staff actor when instrumenting a destroy from a staff actor" do
        events = subscribe "oauth_authorization.destroy"

        employee = create(:staff_admin_user)
        GitHub.context.push(actor_id: employee.id)
        access = create(:oauth_access, user: @user, application: @app)
        access.authorization.destroy

        expected_payload = {
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
          staff_actor: employee.login,
          staff_actor_id: employee.id,
          oauth_authorization_id: access.authorization.id,
          scopes: nil,
          token_scopes: "",
          application_id: @app.id,
          application_type: "OauthApplication",
          application_name: @app.name,
          org_id: [@org.id],
          org: [@org.login],
          user: @user.login,
          user_id: @user.id,
          explanation: nil,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    # Testing PATs because they are unique in that there is no OauthApplication
    # associated with them. So, we want to make sure that `application_name` is
    # logged correctly.
    test "instruments destroy for personal access token" do
      events = subscribe "oauth_authorization.destroy"

      access = create(:personal_token_oauth_access, user: @user)
      access.destroy

      expected_payload = {
        oauth_authorization_id: access.authorization.id,
        scopes: nil,
        token_scopes: "",
        application_id: 0,
        application_type: "OauthApplication",
        application_name: access.description,
        org_id: [@org.id],
        org: [@org.login],
        user: @user.login,
        user_id: @user.id,
        explanation: nil,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  def assert_notification
    assert_difference "ActionMailer::Base.deliveries.count", 1 do
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        yield
      end
    end
  end

  def refute_notification
    assert_no_difference "ActionMailer::Base.deliveries.count" do
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        yield
      end
    end
  end

  context "creation notifications" do
    test "emails are sent upon creation of OauthAccess with high risk scope" do
      assert_notification do
        create(:oauth_access, user: @user, application: @app, scopes: %w(repo user))
      end
      assert_includes ActionMailer::Base.deliveries.last.subject, "A third-party OAuth application has been added to your account"
      assert_includes ActionMailer::Base.deliveries.last.body, "To see this and other security events for your account"
    end

    test "emails are not sent if a PATs scope doesn't change" do
      authorization = create(:personal_token_oauth_access, user: @user, scopes: %w(read:user)).authorization

      refute_notification do
        authorization.description = "fooooooooo"
        authorization.save!
      end
    end

    test "are sent if authorizations gain new privileges" do
      access = T.let(nil, T.nilable(OauthAccess))

      assert_notification do
        access = create(:oauth_access, user: @user, application: @app, scopes: [])
      end

      access = T.must(access)
      authorization = T.must(access.authorization)

      assert_notification do
        authorization.add_scopes! %w(repo user)
      end

      assert_includes ActionMailer::Base.deliveries.last.subject, "A previously authorized third-party OAuth application has been granted additional scopes"
      assert_includes ActionMailer::Base.deliveries.last.body, @app.name
      assert_includes ActionMailer::Base.deliveries.last.body, "To see this and other security events for your account"
    end

    test "include the previous scopes, not just the difference between the current scopes and what was added" do
      access = create(:oauth_access, user: @user, application: @app, scopes: %w(read:user))

      assert_notification do
        access.authorization.add_scopes! %w(repo user)
      end

      assert_includes ActionMailer::Base.deliveries.last.body, "had read:user scope"
    end

    test "are not sent if authorizations only gain read:user access" do
      assert_notification do
        create(:oauth_access, user: @user, application: @app, scopes: [])
      end

      refute_notification do
        create(:oauth_access, user: @user, application: @app, scopes: %w(read:user))
      end
    end

    test "are sent if authorizations are created with read:user and additional access" do
      assert_notification do
        create(:oauth_access, user: @user, application: @app, scopes: OauthAuthorization::PUBLIC_DATA_SCOPES.to_a + ["notifications"])
      end
    end

    test "are sent if authorizations gain read:user and additional access" do
      authorization = create(:oauth_access, user: @user, application: @app, scopes: %w(repo)).authorization
      assert_notification do
        authorization.add_scopes! OauthAuthorization::PUBLIC_DATA_SCOPES.to_a + ["notifications"]
      end
    end

    test "are not sent for updates to integrations" do
      integration = create(:integration)
      authorization = create(:oauth_access, user: @user, application: integration).authorization
      refute_notification do
        authorization.description = SecureRandom.hex
        authorization.save!
      end
    end

    test "emails include the app that created them" do
      assert_notification do
        create(:oauth_access, user: @user, application: @app, scopes: %w(repo user))
        assert_includes ActionMailer::Base.deliveries.last.body, @app.name
      end
    end

    test "emails include the integration that created them" do
      user_permissions = { blocking: :read }
      integration = create(:integration, default_permissions: user_permissions)
      assert_notification do
        create(:oauth_access, user: @user, application: integration)
      end
      assert_includes ActionMailer::Base.deliveries.last.body, integration.name
    end

    test "emails are sent upon creation of OauthAccess with no scope" do
      assert_notification do
        access = build(:oauth_access, user: @user, application: @app)
        access.save!
      end
    end

    test "emails are sent upon creation of OauthAccess with read:user scope" do
      assert_notification do
        access = build(:oauth_access, user: @user, application: @app)
        access.grant("read:user")
        access.save!
      end
    end

    test "emails are not sent when scopes are removed" do
      access = create(:oauth_access, user: @user, application: @app, scopes: %w(repo user))
      refute_notification do
        access.authorization.scopes = %w(repo)
        access.authorization.save!
      end
    end

    test "emails are not sent when scopes are removed for PATs" do
      access = create(:personal_token_oauth_access, user: @user, scopes: %w(repo user))
      refute_notification do
        access.authorization.scopes = %w(repo)
        access.authorization.save!
      end
    end

    context "emails are not sent for internal Apps" do
      test "oauth apps on creation" do
        refute_notification do
          gist = create(:gist_oauth_app) # Gist is configured in the Apps::Privileged registry
          create(:oauth_access, user: @user, application: gist, scopes: %w(repo user))
        end
      end

      test "integrations on created" do
        user_permissions = { blocking: :read }
        integration = create(:integration, default_permissions: user_permissions, owner: @github_org)
        Apps::Privileged::Registry.configure(
          app_alias: :some_internal_app,
          app: integration,
          id: ->(*_) { integration.id },
          capabilities: {
            skip_notification_of_user_permission_changes: true
          }
        )

        refute_notification do
          create(:oauth_access, user: @user, application: integration)
        end
      end

      test "integrations when new permissions are added" do
        user_permissions = { blocking: :read }
        integration = create(:integration, default_permissions: user_permissions, owner: @github_org)
        Apps::Privileged::Registry.configure(
          app_alias: :some_internal_app,
          app: integration,
          id: ->(*_) { integration.id },
          capabilities: {
            skip_notification_of_user_permission_changes: true
          }
        )
        integration.default_permissions = { blocking: :write, email: :read }

        refute_notification do
          create(:oauth_access, user: @user, application: integration)
        end
      end
    end
  end

  test ".third_party scope only returns authorizations unrelated to GitHub-owned Apps" do
    # github owned, oauth app
    github = make_trusted_oauth_apps_owner
    github_owned_oauth_app = create(:oauth_application, user: github)
    github_related_oauth_authorization = create(:oauth_authorization, application: github_owned_oauth_app)
    # github owned, github app
    github_owned_app = create(:integration, owner: github)
    github_related_authorization = create(:oauth_authorization, application: github_owned_app)

    # third party, oauth app
    not_github = create(:organization, login: "not-github")
    third_party_oauth_app = create(:oauth_application, user: not_github)
    third_party_oauth_authorization = create(:oauth_authorization, application: third_party_oauth_app)
    # third party, github app
    third_party_app = create(:integration, owner: not_github)
    third_party_authorization = create(:oauth_authorization, application: third_party_app)

    authorizations = OauthAuthorization.third_party
    assert_includes authorizations, third_party_oauth_authorization
    refute_includes authorizations, github_related_oauth_authorization
    refute_includes authorizations, third_party_authorization
    refute_includes authorizations, github_related_authorization
  end

  test ".third_party_github_apps scope only returns authorizations for github apps unrelated to GitHub-owned Apps" do
    # github owned, oauth app
    github = make_trusted_oauth_apps_owner
    github_owned_oauth_app = create(:oauth_application, user: github)
    github_related_oauth_authorization = create(:oauth_authorization, application: github_owned_oauth_app)
    # github owned, github app
    github_owned_app = create(:integration, owner: github)
    github_related_authorization = create(:oauth_authorization, application: github_owned_app)

    # third party, oauth app
    not_github = create(:organization, login: "not-github")
    third_party_oauth_app = create(:oauth_application, user: not_github)
    third_party_oauth_authorization = create(:oauth_authorization, application: third_party_oauth_app)
    # third party, github app
    third_party_app = create(:integration, owner: not_github)
    third_party_authorization = create(:oauth_authorization, application: third_party_app)

    authorizations = OauthAuthorization.third_party_github_apps
    assert_includes authorizations, third_party_authorization
    refute_includes authorizations, github_related_authorization
    refute_includes authorizations, third_party_oauth_authorization
    refute_includes authorizations, github_related_oauth_authorization
  end

  test ".github_owned scope only returns authorizations related to GitHub-owned Apps" do
    github = make_trusted_oauth_apps_owner
    github_owned_app = create(:oauth_application, user: github)
    github_related_authorization = create(:oauth_authorization, application: github_owned_app)

    not_github = create(:organization, login: "not-github")
    third_party_app = create(:oauth_application, user: not_github)
    third_party_authorization = create(:oauth_authorization, application: third_party_app)

    authorizations = OauthAuthorization.github_owned
    refute_includes authorizations, third_party_authorization
    assert_includes authorizations, github_related_authorization
  end

  test ".user_revocable scope only returns authorizations for OauthApplications that can be revoked by users" do
    revocable = create(:oauth_application)
    irrevocable = create(:oauth_application)
    revocable_authorization = create(:oauth_authorization, application: revocable)
    irrevocable_authorization = create(:oauth_authorization, application: irrevocable)

    Apps::Privileged::Registry.configure(
      app_alias: :some_irrevocable_app,
      app: irrevocable,
      id: ->(*_) { irrevocable.id },
      capabilities: { can_auto_approve_oauth_authorization: true }
    )

    authorizations = OauthAuthorization.user_revocable(OauthApplication)
    assert_includes authorizations, revocable_authorization
    refute_includes authorizations, irrevocable_authorization
  end

  test ".user_revocable scope only returns authorizations for Integrations that can be revoked by users" do
    revocable = create(:integration)
    irrevocable = create(:integration)
    revocable_authorization = create(:oauth_authorization, application: revocable)
    irrevocable_authorization = create(:oauth_authorization, application: irrevocable)

    Apps::Privileged::Registry.configure(
      app_alias: :some_irrevocable_app,
      app: irrevocable,
      id: ->(*_) { irrevocable.id },
      capabilities: { can_auto_approve_oauth_authorization: true }
    )

    authorizations = OauthAuthorization.user_revocable(Integration)
    assert_includes authorizations, revocable_authorization
    refute_includes authorizations, irrevocable_authorization
  end
end
