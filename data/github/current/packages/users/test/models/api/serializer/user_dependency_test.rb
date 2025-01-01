# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class UserSerializersTest < Api::SerializerTestCase
  fixtures do
    @user = create :user, login: "kilgore"
    # NOTE: doing this in one call fails with NoMethodError for location_changed?
    #       because creating a profile tries to save the user before setting the association
    @user.update!(profile_name: "Kilgore Trout")
    add_profile_email(@user, "kilgore@example.com")

    @employee = preview_user
    enable_cache_storage
    reset_cache
  end

  teardown do
    reset_cache
  end

  context "#simple_user_hash" do
    test "constructs hash for given user" do
      user = User.new login: "abc"
      user.id = 123

      output = T.unsafe(self).simple_user(user)
      assert_equal "User", output["type"]
      assert_match /\/users\/abc$/, output["url"]
      assert_equal 123, output["id"]
    end

    test "constructs hash for given mannequins" do
      mannequin_user = Mannequin.new login: "1gUzTIm1YKPjGwJanS9Lfph8qr2MnCwKF0wgX7T"
      mannequin_user.id = 123

      output = T.unsafe(self).simple_user(mannequin_user)
      assert_equal "Mannequin", output["type"]
      assert_match /\/users\/1gUzTIm1YKPjGwJanS9Lfph8qr2MnCwKF0wgX7T$/, output["url"]
      assert_equal mannequin_user.login_for_api(use: :unique), output["login"]
    end

    test "encodes bot urls correctly" do
      integration = create(:integration)
      bot_user = integration.bot
      output = T.unsafe(self).simple_user(bot_user)
      url_keys = %w[
        url
        followers_url
        following_url
        gists_url
        starred_url
        subscriptions_url
        organizations_url
        repos_url
        events_url
        received_events_url
      ]

      url_keys.each do |key|
        assert_match(/%5Bbot%5D/, output[key])
      end
    end

    test "gets avatar url" do
      user = User.new
      user.id = 1
      output = T.unsafe(self).simple_user(user)
      browser_version = GitHub.browser_avatar_version(user.primary_avatar_path)
      query_params = { v: 2, b: browser_version }
      query_params[:jwt] = private_avatar_jwt if TestEnv.test_all_features?
      query_string = query_params.to_query
      assert_equal "#{GitHub.alambic_avatar_url}/u/1?#{query_string}", output["avatar_url"]
    end

    test "indicates if users are site admins" do
      Api::Serializer.stubs(:github_employee_user_ids).returns([@employee.id])

      user = create(:user)

      data = T.unsafe(self).simple_user(user)
      refute_predicate user, :employee?
      refute data["site_admin"]

      data = T.unsafe(self).simple_user(@employee)
      assert_predicate @employee, :employee?
      assert data["site_admin"]
    end unless GitHub.enterprise?

    test "indicates if users are site admins on Enterprise" do
      GitHub.stubs(:require_two_factor_for_site_admin?).returns(false)

      user = create(:user)
      admin = create :staff_admin_user

      data = T.unsafe(self).simple_user(user)
      refute data["site_admin"]

      data = T.unsafe(self).simple_user(admin)
      assert data["site_admin"]
    end if GitHub.enterprise?

    test "does not make extra database calls with a warm employees cache" do
      reset_cache
      T.unsafe(self).simple_user(@employee)
      user = User.find_by_login(@employee.login)
      user.employee? # warm the employee cache since staff are now employees

      assert_no_queries do
        T.unsafe(self).simple_user(user)
      end
    end

    test "it uses new global ids when configured" do
      data = T.unsafe(self).simple_user(@user)
      assert_equal @user.global_relay_id, data["node_id"], "It defaults to old IDs"

      data2 = T.unsafe(self).simple_user(@user, { global_id_selection: { user_preference: true, user_opt_out: false } })
      assert_equal @user.next_global_id, data2["node_id"], "It uses a new ID when `:global_id_selection` is given with the correct settings"
    end

    test "serializes the unique login for non multi tenant environments", skip_enterprise: true do
      emu = create :emu
      data = T.unsafe(self).simple_user(emu)

      assert_equal emu.login, emu.display_login
      assert_equal emu.login, data["login"]
    end

    test "serializes the unique login for internal multi tenant consumers", skip_enterprise: true do
      on_multi_tenant_enterprise do
        GitHub.stubs(:proxima_internal_api_unique_logins_required?).returns(true)

        emu = create :emu
        data = T.unsafe(self).simple_user(emu)

        refute_equal emu.login, emu.display_login
        assert_equal emu.login, data["login"]
      end
    end

    test "serializes the display_login for external multi tenant consumers", skip_enterprise: true do
      on_multi_tenant_enterprise do
        emu = create :emu
        data = T.unsafe(self).simple_user(emu)

        refute_equal emu.login, emu.display_login
        assert_equal emu.display_login, data["login"]
      end
    end
  end

  SimpleUserQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($id: ID!) {
      node(id: $id) {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }
    }
  GRAPHQL

  context "#graphql_simple_user_hash" do
    test "constructs hash for given user" do
      results = Api::App::PlatformClient.query(SimpleUserQuery, variables: { "id": @user.global_relay_id })
      output = T.unsafe(self).graphql_simple_user(results.data.node)

      assert_equal "User", output["type"]
      assert_match /\/users\/#{@user.login}$/, output["url"]
      assert_equal @user.id, output["id"]
    end

    test "gets avatar url" do
      results = Api::App::PlatformClient.query(SimpleUserQuery, variables: { "id": @user.global_relay_id })
      output = T.unsafe(self).graphql_simple_user(results.data.node)

      browser_version = GitHub.browser_avatar_version(@user.primary_avatar_path)
      query_params = { v: 2, b: browser_version }
      query_params[:jwt] = private_avatar_jwt if TestEnv.test_all_features?
      query_string = query_params.to_query
      assert_equal "#{GitHub.alambic_avatar_url}/u/#{@user.id}?#{query_string}", output["avatar_url"]
    end

    # See https://github.com/github/github/issues/93032#issuecomment-407761734
    test "properly renders bots (using the [bot] suffix) with the owner_scoped_github_apps flag disabled" do
      disable_feature_flag(:owner_scoped_github_apps)
      integration = create(:integration)
      bot_user = integration.bot
      results = Api::App::PlatformClient.query(SimpleUserQuery, variables: { "id": bot_user.global_relay_id })
      output = T.unsafe(self).graphql_simple_user(results.data.node)

      assert_equal "Bot", output["type"]
      assert_equal bot_user.display_login, output["login"]
      login_with_suffix = "#{bot_user.slug}%5Bbot%5D"
      assert_match /\/users\/#{login_with_suffix}$/, output["url"]
      html_url_prefix = GitHub.enterprise? ? "github-apps" : "apps"
      assert_match /\/#{html_url_prefix}\/#{bot_user.slug}$/, output["html_url"]
      assert_match /\/users\/#{login_with_suffix}\/followers$/, output["followers_url"]
      assert_match /\/users\/#{login_with_suffix}\/following{\/other_user}$/, output["following_url"]
      assert_match /\/users\/#{login_with_suffix}\/gists{\/gist_id}$/, output["gists_url"]
      assert_match /\/users\/#{login_with_suffix}\/starred{\/owner}{\/repo}$/, output["starred_url"]
      assert_match /\/users\/#{login_with_suffix}\/subscriptions$/, output["subscriptions_url"]
      assert_match /\/users\/#{login_with_suffix}\/orgs$/, output["organizations_url"]
      assert_match /\/users\/#{login_with_suffix}\/repos$/, output["repos_url"]
      assert_match /\/users\/#{login_with_suffix}\/events{\/privacy}$/, output["events_url"]
      assert_match /\/users\/#{login_with_suffix}\/received_events$/, output["received_events_url"]
    end

    # See https://github.com/github/ecosystem-apps/issues/5966
    # /user/* URLs will be changing when apps are migrated to be owner-scoped
    # (like repos). Where the owner_scoped_github_apps feature flag is enabled
    # (E.g. Proxima), bot actors cannot be fetched via /user/* endpoints
    # because the REST API does not support them yet.
    test "properly renders bots (using the app owner and [bot] suffix) with the owner_scoped_github_apps flag enabled" do
      enable_feature_flag(:owner_scoped_github_apps)
      integration = create(:integration)
      bot_user = integration.bot
      results = Api::App::PlatformClient.query(SimpleUserQuery, variables: { "id": bot_user.global_relay_id })
      output = T.unsafe(self).graphql_simple_user(results.data.node)

      assert_equal "Bot", output["type"]
      assert_equal bot_user.display_login, output["login"]
      login_with_suffix = "#{bot_user.slug}%5Bbot%5D"
      assert_match /\/users\/#{login_with_suffix}$/, output["url"]
      html_url_prefix = GitHub.enterprise? ? "github-apps" : "apps"
      assert_match /\/#{html_url_prefix}\/#{integration.owner}\/#{bot_user.slug}$/, output["html_url"]
      assert_match /\/users\/#{login_with_suffix}\/followers$/, output["followers_url"]
      assert_match /\/users\/#{login_with_suffix}\/following{\/other_user}$/, output["following_url"]
      assert_match /\/users\/#{login_with_suffix}\/gists{\/gist_id}$/, output["gists_url"]
      assert_match /\/users\/#{login_with_suffix}\/starred{\/owner}{\/repo}$/, output["starred_url"]
      assert_match /\/users\/#{login_with_suffix}\/subscriptions$/, output["subscriptions_url"]
      assert_match /\/users\/#{login_with_suffix}\/orgs$/, output["organizations_url"]
      assert_match /\/users\/#{login_with_suffix}\/repos$/, output["repos_url"]
      assert_match /\/users\/#{login_with_suffix}\/events{\/privacy}$/, output["events_url"]
      assert_match /\/users\/#{login_with_suffix}\/received_events$/, output["received_events_url"]
    end

    test "properly renders bots for Proxima synced apps", skip_enterprise: true, feature_enabled: :proxima_synced_avatar_url do
      on_multi_tenant_enterprise do
        integration = create(:synchronized_integration)
        bot_user = integration.bot
        assert ProximaAppSynchronization.synchronized?(integration)
        refute_nil integration.canonical_avatar_url

        results = Api::App::PlatformClient.query(SimpleUserQuery, variables: { "id": bot_user.global_relay_id })
        output = T.unsafe(self).graphql_simple_user(results.data.node)

        assert_equal "Bot", output["type"]
        assert_equal bot_user.display_login, output["login"]
        login_with_suffix = "#{bot_user.slug}%5Bbot%5D"
        assert output["url"].ends_with?("/users\/#{login_with_suffix}")
        assert_match integration.canonical_avatar_url, output["avatar_url"]
      end
    end

    test "properly renders mannequins" do
      mannequin_user = create(:mannequin)
      results = Api::App::PlatformClient.query(SimpleUserQuery, variables: { "id": mannequin_user.global_relay_id })
      output = T.unsafe(self).graphql_simple_user(results.data.node)

      assert_equal "Mannequin", output["type"]
      assert_equal mannequin_user.source_login, output["login"]
      assert_match /\/users\/ghost$/, output["url"]
      assert_match /\/users\/ghost$/, output["html_url"]
      assert_match /\/users\/ghost\/followers$/, output["followers_url"]
      assert_match /\/users\/ghost\/following{\/other_user}$/, output["following_url"]
      assert_match /\/users\/ghost\/gists{\/gist_id}$/, output["gists_url"]
      assert_match /\/users\/ghost\/starred{\/owner}{\/repo}$/, output["starred_url"]
      assert_match /\/users\/ghost\/subscriptions$/, output["subscriptions_url"]
      assert_match /\/users\/ghost\/orgs$/, output["organizations_url"]
      assert_match /\/users\/ghost\/repos$/, output["repos_url"]
      assert_match /\/users\/ghost\/events{\/privacy}$/, output["events_url"]
      assert_match /\/users\/ghost\/received_events$/, output["received_events_url"]
    end

    test "indicates if users are site admins" do
      user = create(:user)
      admin = create :staff_admin_user

      results = Api::App::PlatformClient.query(SimpleUserQuery, variables: { "id": user.global_relay_id })
      output = T.unsafe(self).graphql_simple_user(results.data.node)

      refute_predicate user, :employee?
      refute output["site_admin"]

      results = Api::App::PlatformClient.query(SimpleUserQuery, variables: { "id": admin.global_relay_id })
      output = T.unsafe(self).graphql_simple_user(results.data.node)

      assert_predicate admin, :employee?
      assert output["site_admin"]
    end unless GitHub.enterprise?

    test "indicates if users are site admins on Enterprise" do
      GitHub.stubs(:require_two_factor_for_site_admin?).returns(false)
      GitHub.auth.stubs(:ldap?).returns(true)

      user = create(:user)
      user.map_ldap_entry "uid=alice,ou=users,dc=github,dc=com"
      admin = create :staff_admin_user
      admin.map_ldap_entry "uid=bob,ou=users,dc=github,dc=com"

      results = Api::App::PlatformClient.query(SimpleUserQuery, variables: { "id": user.global_relay_id })
      output = T.unsafe(self).graphql_simple_user(results.data.node)
      refute output["site_admin"]
      assert_equal output["ldap_dn"], "uid=alice,ou=users,dc=github,dc=com"

      results = Api::App::PlatformClient.query(SimpleUserQuery, variables: { "id": admin.global_relay_id })
      output = T.unsafe(self).graphql_simple_user(results.data.node)
      assert output["site_admin"]
      assert_equal output["ldap_dn"], "uid=bob,ou=users,dc=github,dc=com"
    end if GitHub.enterprise?

    if GitHub.enterprise?
      test "organization does not check for ldap_dn" do
        GitHub.stubs(:require_two_factor_for_site_admin?).returns(false)
        GitHub.auth.stubs(:ldap?).returns(true)

        user = create(:user)
        user.map_ldap_entry "uid=alice,ou=users,dc=github,dc=com"
        org = create(:organization)

        results = Api::App::PlatformClient.query(SimpleUserQuery, variables: { "id": user.global_relay_id })
        output = T.unsafe(self).graphql_simple_user(results.data.node)
        assert_equal output["ldap_dn"], "uid=alice,ou=users,dc=github,dc=com"

        results = Api::App::PlatformClient.query(SimpleUserQuery, variables: { "id": org.global_relay_id })
        output = T.unsafe(self).graphql_simple_user(results.data.node)
        refute output["ldap_dn"]
      end
    end
  end

  context "#user_hash" do
    test "can include user identity information" do
      @user.profile # trigger the profile to be loaded before serialization
      output = T.unsafe(self).user(@user, mime_params: Set[:'user-identity'])
      assert_equal "Kilgore Trout", output["name"]
      assert_equal "kilgore@example.com", output["email"]
    end

    test "provides null values for profile fields, when full hash is requested and user has no profile" do
      user = create :user, login: "abc"

      output = T.unsafe(self).user(user, full: true)
      assert_equal "User", output["type"]
      assert_match /\/users\/abc$/, output["url"]
      assert_nil output["name"]
      assert_nil output["email"]
      assert_nil output["twitter_username"]
    end

    test "provides null values for empty profile fields, when full hash is requested and user has a profile" do
      user = create :user, login: "abc"
      create(:profile, user: user, email: "")

      output = T.unsafe(self).user(user, full: true)

      assert_equal "User", output["type"]
      assert_match /\/users\/abc$/, output["url"]
      assert_nil output["email"]
      assert_nil output["twitter_username"]
    end

    test "includes the user's profile email by default" do
      user = create :user, login: "tom-robbins"
      create(:profile, user: user, email: "tom.robbins@cowgirls.com")

      output = T.unsafe(self).user(user, full: true)
      assert_equal output["email"], "tom.robbins@cowgirls.com"
    end

    test "includes the user's twitter_username by default" do
      user = create :user
      twitter_username = "horse_js"
      create(:profile, user: user, twitter_username: twitter_username)

      output = T.unsafe(self).user(user, full: true)
      assert_equal twitter_username, output["twitter_username"]
    end

    unless GitHub.enterprise?
      test "excludes the user's profile email with appropriate flag" do
        user = create :user, login: "tom-robbins"
        create(:profile, user: user, email: "tom.robbins@cowgirls.com")

        output = T.unsafe(self).user(user, full: true, exclude_email: true)
        assert_nil output["email"]
      end
    end

    test "excludes user identity information by default" do
      output = T.unsafe(self).user(@user)
      refute output.key?("name")
    end

    test "includes primary email with shortcode for EMU with unclaimed email when check_email_claimed is true", skip_enterprise: true, skip_in_multitenant_mode: true do
      emu = create :emu, email: "primary@example.com"
      primary_email = emu.primary_user_email
      refute_predicate primary_email, :claimed?

      output = T.unsafe(self).user(emu, full: true, check_email_claimed: true)
      assert_equal primary_email.email, output["email"]
    end

    test "includes profile email without shortcode for EMU with unclaimed email when check_email_claimed is false or not passed", skip_enterprise: true, skip_in_multitenant_mode: true do
      emu = create :emu, email: "primary@example.com"
      refute_predicate emu.primary_user_email, :claimed?
      profile_email = emu.profile_email

      output = T.unsafe(self).user(emu, full: true)
      assert_equal profile_email, output["email"]

      output = T.unsafe(self).user(emu, full: true, check_email_claimed: false)
      assert_equal profile_email, output["email"]
    end

    test "excludes primary email for EMU with appropriate flag when check_email_claimed is true", skip_enterprise: true do
      emu = create :emu, email: "primary@example.com"

      output = T.unsafe(self).user(emu, full: true, check_email_claimed: true, exclude_email: true)
      assert_nil output["email"]
    end

    test "includes profile email without shortcode for EMU with claimed email when check_email_claimed is true", skip_enterprise: true, skip_in_multitenant_mode: true do
      emu = create :emu, email: "primary@example.com"
      emu.primary_user_email.update!(claimed: true)
      profile_email = emu.profile_email

      output = T.unsafe(self).user(emu, full: true, check_email_claimed: true)
      assert_equal profile_email, output["email"]
    end

    test "includes notification_email with profile email when check_email_claimed is true", skip_enterprise: true do
      emu = create :emu, email: "primary@example.com"
      profile_email = emu.profile_email

      output = T.unsafe(self).user(emu, full: true, check_email_claimed: true)
      assert_equal profile_email, output["notification_email"]

      user = create :user, login: "tom-robbins"
      create(:profile, user: user, email: "tom.robbins@cowgirls.com")

      output = T.unsafe(self).user(user, full: true, check_email_claimed: true)
      assert_equal "tom.robbins@cowgirls.com", output["notification_email"]
    end

    test "excludes notification_email property when check_email_claimed is false", skip_enterprise: true do
      emu = create :emu, email: "primary@example.com"

      output = T.unsafe(self).user(emu, full: true, check_email_claimed: false)
      refute output.key?("notification_email")

      user = create :user, login: "tom-robbins"
      create(:profile, user: user, email: "tom.robbins@cowgirls.com")

      output = T.unsafe(self).user(user, full: true, check_email_claimed: false)
      refute output.key?("notification_email")
    end
  end

  context "#collaborator_hash" do
    test "includes a permissions hash with pull=true when the user has read on the repo" do
      collab = create(:user, login: "collaborator")
      org    = create(:organization)
      repo   = create(:repository, owner: org)
      repo.add_member(collab, action: :read)

      output = T.unsafe(self).collaborator(collab, repo: repo)

      permissions = output["permissions"]
      assert_equal true, permissions["pull"]
      assert_equal false, permissions["push"]
      assert_equal false, permissions["admin"]
    end

    test "includes a permissions hash with pull=true and push=true when the user has write on the repo" do
      collab = create(:user, login: "collaborator")
      repo   = create(:repository)
      repo.add_member(collab, action: :write)

      output = T.unsafe(self).collaborator(collab, repo: repo)

      permissions = output["permissions"]
      assert_equal true, permissions["pull"]
      assert_equal true, permissions["push"]
      assert_equal false, permissions["admin"]
    end

    test "includes a permissions hash with admin=true when the user is a repo admin" do
      owner = create(:user, login: "owner")
      repo   = create(:repository, owner: owner)
      repo.add_member(owner, action: :admin)

      output = T.unsafe(self).collaborator(owner, repo: repo)

      permissions = output["permissions"]
      assert_equal true, permissions["pull"]
      assert_equal true, permissions["push"]
      assert_equal true, permissions["admin"]
    end

    test "includes role_name" do
      owner = create(:user, login: "owner")
      repo   = create(:repository, owner: owner)
      repo.add_member(owner, action: :admin)

      output = T.unsafe(self).collaborator(owner, repo: repo)

      permissions = output["permissions"]
      assert_equal true, permissions["pull"]
      assert_equal true, permissions["push"]
      assert_equal true, permissions["admin"]

      assert_equal "admin", output["role_name"]
    end

    test "returns nil if no user is present" do
      output = T.unsafe(self).collaborator(nil)
      assert_nil output
    end

    test "returns nil if no repo is present" do
      collab = create(:user, login: "collaborator")
      output = T.unsafe(self).collaborator(collab, nil)
      assert_nil output
    end
  end
end

class UserEmailSerializersTest < Api::SerializerTestCase
  setup do
    @email = UserEmail.new email: "foo@bar.com",
      primary: false, state: "verified"
  end

  test "renders beta format when only the beta media type is requested" do
    media_types = ["application/vnd.github.beta+json"]
    output = T.unsafe(self).user_email(@email, accept_mime_types: media_types)
    assert_equal "foo@bar.com", output
  end

  test "renders v3 format when the beta media type and the v3 media type are requested" do
    media_types = [
      "application/vnd.github.v3+json",
      "application/vnd.github.beta+json",
    ]
    output = T.unsafe(self).user_email(@email, accept_mime_types: media_types)
    assert_same_elements %w[email primary verified visibility], output.keys
  end

  test "renders user_email object format when beta media type is requested and changeset is active" do
    media_types = ["application/vnd.github.beta+json"]
    with_changeset "deprecate_beta_media_type" do
      output = T.unsafe(self).user_email(@email, accept_mime_types: media_types)
      assert_same_elements %w[email primary verified visibility], output.keys
    end
  end

  test "renders v3 format when the v3 media type is requested" do
    media_types = ["application/vnd.github.v3+json"]
    output = T.unsafe(self).user_email(@email, accept_mime_types: media_types)
    assert_same_elements %w[email primary verified visibility], output.keys
  end

  test "renders v3 format when a preview media type is requested" do
    Api::MediaType.stub_const(:SemanticVersions, Api::MediaType::SemanticVersions << "superman-preview") do
      media_types = ["application/vnd.github.superman-preview+json"]
      output = T.unsafe(self).user_email(@email, accept_mime_types: media_types)
      assert_same_elements %w[email primary verified visibility], output.keys
    end
  end

  test "returns verified: true for GHE UserEmails whose state is unverified" do
    GitHub.stubs(:email_verification_enabled?).returns(false)

    @email = UserEmail.new(
      email: "unverified@example.org",
      primary: false,
      state: "unverified",
    )

    output = T.unsafe(self).user_email(@email)
    assert output["verified"], "all GHE UserEmails should be marked as verified"
  end

  test "returns verified: false if the UserEmail state is unverified" do
    GitHub.stubs(:email_verification_enabled?).returns(true)

    @email = UserEmail.new(
      email: "unverified@example.org",
      primary: false,
      state: "unverified",
    )

    output = T.unsafe(self).user_email(@email)
    assert_equal false, output["verified"]
  end
end

class PublicKeySerializersTest < Api::SerializerTestCase
  test "for a user-owned key" do
    user = create :user, login: "a-user"
    key  = user.public_keys.create! key: Sham.ssh_public_key,
                                    title: "a-title"

    output = T.unsafe(self).public_key(key)
    assert_equal "a-title", output["title"]
    assert_match %r(/user/keys/\d+\z), output["url"]
  end

  test "for a repository-owned deploy key" do
    user = create :user, login: "a-user"
    repo = create :repository, owner: user, name: "a-repo"
    deploy_key_attributes = {
      title: "a-title",
      key: Sham.ssh_public_key,
      verifier: user,
      read_only: false
    }
    key = repo.public_keys.create_with_verification(deploy_key_attributes)
    output = T.unsafe(self).public_key(key)
    assert_equal "a-title", output["title"]
    assert_match %r(/repos/a-user/a-repo/keys/\d+\z), output["url"]
    assert_equal "a-user", output["added_by"]
    assert_nil output["last_used"]
  end

  test "for a repository-owned deploy key that has been used" do
    Timecop.freeze(Time.now) do
      user = create :user, login: "a-user"
      repo = create :repository, owner: user, name: "a-repo"
      deploy_key_attributes = {
        title: "a-title",
        key: Sham.ssh_public_key,
        verifier: user,
        read_only: false
      }

      key = repo.public_keys.create_with_verification(deploy_key_attributes)
      key.accessed_at = 1.day.ago
      key.save!

      output = T.unsafe(self).public_key(key)
      assert_equal "a-title", output["title"]
      assert_match %r(/repos/a-user/a-repo/keys/\d+\z), output["url"]
      assert_equal "a-user", output["added_by"]
      assert_equal 1.day.ago.strftime("%Y-%m-%dT%H:%M:%SZ"), output["last_used"]
    end
  end

  test "for a repository-owned deploy key where the creator is not present" do
    user = create :user, login: "a-user"
    repo = create :repository, owner: user, name: "a-repo"
    deploy_key_attributes = {
      title: "a-title",
      key: Sham.ssh_public_key,
      verifier: user,
      read_only: false
    }

    # a 'creator' is marked as part of 'create_with_verification', which is what is used to create
    # public keys across the codebase. this test creates a public key record manually (with `create!`)
    # which tests a potential edge case where the creator is not present on a given key
    key = repo.public_keys.create! key: Sham.ssh_public_key,
                                    title: "a-title"

    output = T.unsafe(self).public_key(key)
    assert_equal "a-title", output["title"]
    assert_match %r(/repos/a-user/a-repo/keys/\d+\z), output["url"]
    assert_nil output["added_by"]
    assert_nil output["last_used"]
  end

  test "provides the 'read_only' attribute for a repository-owned key" do
    requestor = create :user, login: "requestor"
    owner = create :user, login: "repo-owner"
    repo = create :repository, owner: owner, name: "a-repo"
    key = repo.public_keys.create! key: Sham.ssh_public_key,
                                   read_only: true

    output = T.unsafe(self).public_key(key, current_user: requestor)
    assert_equal true, output["read_only"]
  end

  context "#mentionable_user_hash" do
    test "payload is valid" do
      user = create :user
      output = T.unsafe(self).mentionable_user(user)
      assert_same_elements %w[login name email avatar_url], output.keys

    end

    test "returns nil when user isn't passed" do
      assert_nil T.unsafe(self).mentionable_user(nil)
    end
  end

  context "OAuth Serializers" do
    context "#oauth_authorization_hash" do
      test "payload is valid" do
        authorization = create(:oauth_authorization)
        output = T.unsafe(self).oauth_authorization(authorization)
        assert_same_elements %w[id url app created_at updated_at scopes], output.keys
        assert output["scopes"].include? "read:user"

      end
    end

    context "#oauth_access_hash" do
      test "payload is valid" do
        access = create(:oauth_access, scopes: ["public_repo"])
        output = T.unsafe(self).oauth_access(access)
        assert output.key?("id")
        assert output["scopes"].include? "public_repo"

      end

      test "works for a GitHub App OAuth access" do
        access = create(:github_app_access, scopes: [])
        output = T.unsafe(self).oauth_access(access)
        assert output.key?("id")
        assert output["app"]

      end

      test "works with optional user" do
        access = create(:oauth_access, scopes: [])
        output = T.unsafe(self).oauth_access(access, { user: access.user })
        assert output.key?("id")
        assert output["app"]
        assert output.key?("user")
      end

      test "does not require a user" do
        access = create(:oauth_access, scopes: [])
        output = T.unsafe(self).oauth_access(access)
        assert output.key?("id")
        assert output["scopes"].blank?
      end

      test "token can be true" do
        access = create(:oauth_access, scopes: [])
        output = T.unsafe(self).oauth_access(access, { token: true })
        assert output.key?("id")
        assert_equal "true", output["token"]

      end

      test "token can be false" do
        access = create(:oauth_access, scopes: [])
        output = T.unsafe(self).oauth_access(access, { token: false })
        assert output.key?("id")
        assert_equal "false", output["token"]
      end
    end
  end
end

HovercardQuery = Api::App::PlatformClient.parse <<-'GRAPHQL'
  query($userId: ID!) {
    node(id: $userId) {
      ... on User {
        hovercard {
          ...Api::Serializer::UserDependency::HovercardFragment
        }
      }
    }
  }
GRAPHQL

class GraphqlHovercardHashTest < Api::SerializerTestCase
  test "payload is valid" do
    user = create :user
    results = Api::App::PlatformClient.query(HovercardQuery, variables: { "userId": user.global_relay_id })
    output = T.unsafe(self).graphql_hovercard(results.data.node.hovercard)
    assert_same_elements %w[message octicon], output["contexts"].first.keys

  end
end

class SocialAccountSerializersTest < Api::SerializerTestCase
  setup do
    @facebook_account = create(:social_account_facebook, url: "https://facebook.com/monalisa")
  end

  test "payload is valid" do
    output = T.unsafe(self).social_account(@facebook_account)
    assert_equal "facebook", output["provider"]
    assert_equal "https://facebook.com/monalisa", output["url"]
  end

  test "returns nil if social account does not exist" do
    assert_nil T.unsafe(self).social_account(nil)
  end
end
