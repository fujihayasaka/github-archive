# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsSearcherTest < GitHub::TestCase
  include AuditLogHelpers
  include GpgKeyHelper

  setup do
    setup_search
    deleted_user = create(:user, :with_instrumentation, login: "deleted-user", email: "deleted-user@acme.com")
    @deleted_user_id = deleted_user.id
    renamed_user = create(:user, :with_instrumentation, login: "renamed-user")
    renamed_user1 = create(:user, :with_instrumentation, login: "CaseSensitiveUser")

    with_es_refresh do
      deleted_user.destroy
      renamed_user.rename! "foobar"
      renamed_user1.rename! "new-user-name"
    end
  end

  teardown do
    teardown_search
  end

  fixtures do
    @user = create :user, :with_instrumentation, login: "silver-searcher"
    @gpg_key = create_gpg_key(user: @user)

    @user_with_primary_email = create :user, login: "primary-searcher1", email: "primary@github.com"
    @user_with_primary_email.add_email("external@github.com")

    on_multi_tenant_enterprise do
      @emu_user1 = create :emu, login: "silversearcherone"
      @emu_user1.update_column(:display_login, "silversearcher")
      @emu_user1.update_column(:business_id, @emu_user1.enterprise_managed_business.id)
      @emu_user2 = create :emu, login: "silversearchertwo"
      @emu_user2.update_column(:display_login, "silversearcher")
      @emu_user2.update_column(:business_id, @emu_user2.enterprise_managed_business.id)
    end

    # Note: set the business ID to unique from the user, repo, and customer IDs
    @business = create :business, name: "haha business", id: 2342235
    # Note: set the customer ID to unique from the user, repo, and business IDs
    @customer = create(:customer, :zuora, business: @business, id: 33646323)

    @user_with_coupon = create :user
    @coupon = create :coupon
    @user_with_coupon.redeem_coupon(@coupon)

    @team = create :team

    gist_contents = [{ name: "1", value: "random content" }]
    @gist = GistHelpers.generate contents: gist_contents, user: @user
    @gist1  = GistHelpers.generate contents: gist_contents

    @app1 = create :oauth_application
    @app2 = create :oauth_application
    @app3 = create :oauth_application
    create(:oauth_access, application: @app1, user: @user)
    create(:oauth_access, application: @app2, user: @user)
    create(:oauth_access, application: @app3, user: @user)

    @integ1 = create(:integration, id: 47, name: "pokemon teleporter")
    @integ2 = create(:integration, id: 59, name: "elephant trampoline")
  end

  context "#search_for_gpg_key" do
    test "query does not match GPG_KEY_PATTERN" do
      query = "does not match GPG_KEY_PATTERN"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_gpg_key
      assert_nil searcher.results.gpg_keys
      assert_nil searcher.results.gpg_key_users
    end

    test "gpg_keys are set" do
      query = @gpg_key.hex_key_id
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_gpg_key
      assert_equal searcher.results.gpg_keys, [@gpg_key]
    end

    test "gpg_key_users is set" do
      query = @gpg_key.hex_key_id
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_gpg_key
      assert_equal searcher.results.gpg_key_users, [@user]
    end
  end

  context "#search_for_users" do
    test "standard user search in multitenant mode searches via display_login" do
      on_multi_tenant_enterprise
      GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
      # stafftool controller queries are unscoped so simulating the same here
      GitHub::CurrentTenant.unscope do
        query = @emu_user1.display_login
        searcher = ::Stafftools::Searcher.new(query, @emu_user1)
        searcher.search_for_users
        assert_equal searcher.results.users, [@emu_user1, @emu_user2]
      end
    end

    test "standard user search in multitenant mode searches via login if the query contains the user name with a tenant suffix" do
      on_multi_tenant_enterprise
      GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
      # stafftool controller queries are unscoped so simulating the same here
      GitHub::CurrentTenant.unscope do
        query = @emu_user1.login
        searcher = ::Stafftools::Searcher.new(query, @emu_user1)
        searcher.search_for_users
        assert_equal searcher.results.users, [@emu_user1]
      end
    end

    test "standard user search finds user by email" do
      query = @user.email
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_users
      assert_equal searcher.results.users, [@user]
    end

    test "ignores soft deleted organizations when searching by email" do
      with_es_refresh do
        soft_deleted_org = create(:organization, :soft_deleted, organization_billing_email: @user.email)
        soft_deleted_org_2 = create(:organization, :soft_deleted, organization_billing_email: @user.email)
      end

      searcher = ::Stafftools::Searcher.new(@user.email, @user)
      assert_query_count_per_table({ soft_deleted_organizations: 2 }) do
        searcher.search_for_users
      end
      assert_equal searcher.results.users, [@user]
    end

    test "ignores soft deleted organizations in fuzzy search" do
      soft_deleted_org = create(:organization, :soft_deleted, login: "test-org-1")
      soft_deleted_org_2 = create(:organization, :soft_deleted, login: "test-org-2")
      active_organization = create(:organization, login: "test-org-3")

      make_searchable soft_deleted_org, soft_deleted_org_2, active_organization

      query = "test-org"
      searcher = ::Stafftools::Searcher.new(query, @user)
      assert_query_count_per_table({ soft_deleted_organizations: 3 }) do
        searcher.search_for_users
      end
      assert_equal active_organization, searcher.results.fuzzy_users.first["_model"]
    end

    context "standard user search finds emus by profile email" do
      test "when users have the same profile email" do
        emu_profile_email = "common_profile_email@fabrikam.com"

        emu_business = create :business, :enterprise_managed
        create :business_saml_provider, business: emu_business
        emu_user1 = create :emu, business: emu_business
        emu_user1.profile.email = emu_profile_email
        emu_user1.profile.save!
        emu_user2 = create :emu, business: emu_business
        emu_user2.profile.email = emu_profile_email
        emu_user2.profile.save!

        query = emu_profile_email
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_users
        assert_same_elements searcher.results.users, [emu_user1, emu_user2]
      end

      test "when users have distinct profile emails" do
        emu_profile_email1 = "common_profile_email1@fabrikam.com"
        emu_profile_email2 = "common_profile_email2@fabrikam.com"

        emu_business = create :business, :enterprise_managed
        create :business_saml_provider, business: emu_business
        emu_user1 = create :emu, business: emu_business
        emu_user1.profile.email = emu_profile_email1
        emu_user1.profile.save!
        emu_user2 = create :emu, business: emu_business
        emu_user2.profile.email = emu_profile_email2
        emu_user2.profile.save!

        query = emu_profile_email1
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_users
        assert_same_elements searcher.results.users, [emu_user1]
      end
    end unless GitHub.single_business_environment?

    test "user search does not find mannequin by email" do
      mannequin = create(:mannequin, email: @user.email)
      searcher = ::Stafftools::Searcher.new(@user.email, @user)
      searcher.search_for_users
      refute_includes searcher.results.users, mannequin
    end

    test "standard user search finds user by user login" do
      query = "silver-searcher"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_users
      assert_equal searcher.results.users, [@user]
    end

    test "standard user search finds user by user id" do
      query = "#{@user.id}"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_users
      assert_equal searcher.results.users, [@user]
    end

    test "standard user search finds user by sdn screening id" do
      profile = create(:account_screening_profile)
      query = profile.external_uuid
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_users
      assert_includes searcher.results.users, profile.owner
    end

    test "coupon users search finds user by coupon code" do
      query = @coupon.code
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_users
      assert_equal searcher.results.users, [@user_with_coupon]
    end

    test "spammy users search finds user by complete email" do
      user = create :user
      make_searchable user
      spammy_user = user.mark_as_spammy
      query = user.email
      searcher = ::Stafftools::Searcher.new(query, user)
      searcher.search_for_users
      assert_equal searcher.results.users, [user]
    end

    test "spammy users search removes partial hits from results" do
      user = create :user
      make_searchable user
      spammy_user = user.mark_as_spammy
      query = user.email[2..-1]
      searcher = ::Stafftools::Searcher.new(query, user)
      searcher.search_for_users
      assert_empty searcher.results.users
    end

    test "deleted users search finds deleted user by user_id" do
      query = "#{@deleted_user_id}"
      phrase = "(user:#{query} OR org:#{query} OR user_id:#{query} OR org_id:#{query}) AND (action:user.delete OR action:org.delete)"

      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_users

      assert_equal @deleted_user_id, searcher.results.deleted_users.first.user_id
    end

    test "soft deleted organizations are included in deleted_users" do
      with_es_refresh do
        @soft_deleted_org = create(:organization, :with_instrumentation, :soft_deleted, organization_billing_email: @user.email)
      end

      searcher = ::Stafftools::Searcher.new("#{@soft_deleted_org.id}", @user)
      searcher.search_for_users

      assert_equal @soft_deleted_org.id, searcher.results.deleted_users.first.org_id
    end

    test "finds soft deleted organizations by email" do
      with_es_refresh do
        @soft_deleted_org = create(:organization, :with_instrumentation, :soft_deleted, organization_billing_email: @user.email)
      end

      searcher = ::Stafftools::Searcher.new(@soft_deleted_org.billing_email, @user)
      searcher.search_for_users

      assert_equal @soft_deleted_org.id, searcher.results.deleted_users.first.org_id
    end

    test "soft deleted organizations are include in deleted_users" do
      with_es_refresh do
        @soft_deleted_org = create(:organization, :with_instrumentation, :soft_deleted, organization_billing_email: @user.email)
      end

      searcher = ::Stafftools::Searcher.new("#{@soft_deleted_org.id}", @user)
      searcher.search_for_users

      assert_equal @soft_deleted_org.id, searcher.results.deleted_users.first.org_id
    end

    test "deleted users search finds deleted user by email" do
      query = "deleted-user@acme.com"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_users

      assert_equal @deleted_user_id, searcher.results.deleted_users.first.user_id
      refute searcher.results.deleted_users.first.data["legal_hold"]
    end

    test "deleted users search finds deleted user by login" do
      query = "deleted-user"
      phrase = "(user:#{query} OR org:#{query}) AND (action:user.delete OR action:org.delete)"

      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_users

      assert_equal @deleted_user_id, searcher.results.deleted_users.first.user_id
    end

    test "deleted users search includes legal hold information in its results" do
      deleted_user = User.new(id: @deleted_user_id, login: "deleted-user")
      deleted_user.place_legal_hold(actor: @user)

      query = deleted_user.id.to_s
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_users

      assert_equal deleted_user.id, searcher.results.deleted_users.first.user_id
      assert searcher.results.deleted_users.first.data["legal_hold"]
    end

    test "uses case-insensitive search for deleted users when using ADE as data source" do
      GitHub.stubs(:driftwood_enabled?).returns(true)

      expectations = [
        {
          query: "deleted-user",
          phrase: <<~KQL
            webevents
            | where user =~ "deleted-user" or org =~ "deleted-user"
            | where action in ("user.delete", "org.delete", "org.soft_delete", "org.async_delete", "org.destroy")
          KQL
        },
        {
          query: "deleted-user@acme.com",
          phrase: <<~KQL
            webevents
            | where data.email =~ "deleted-user@acme.com"
            | where action in ("user.delete", "org.delete", "org.soft_delete", "org.async_delete", "org.destroy")
          KQL
        },
        {
          query: @deleted_user_id.to_s,
          phrase: <<~KQL
            webevents
            | where user =~ "#{@deleted_user_id}" or org =~ "#{@deleted_user_id}" or user_id == "#{@deleted_user_id}" or org_id == "#{@deleted_user_id}"
            | where action in ("user.delete", "org.delete", "org.soft_delete", "org.async_delete", "org.destroy")
          KQL
        },
      ]

      expectations.each do |expectation|
        Audit::Driftwood::Query.expects(:new_stafftools_query).with(
          phrase: expectation[:phrase],
          current_user: @user,
        ).returns(stub(execute: []))

        searcher = ::Stafftools::Searcher.new(expectation[:query], @user)
        searcher.search_for_users
      end
    end unless GitHub.enterprise?

    test "finds user by non-primary email" do
      query = "external@github.com"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_users

      assert_same_elements [@user_with_primary_email], searcher.results.users
    end

    test "finds user by non-primary email when they have more than one additional email" do
      query = "external_two@github.com"
      @user_with_primary_email.add_email(query)
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_users

      assert_same_elements [@user_with_primary_email], searcher.results.users
    end

    test "finds multiple users matching an external billing email" do
      user_with_primary_2 = create :user, email: "primary2@github.com"
      new_email = create :billing_external_email, owner: user_with_primary_2, email: "external@github.com"
      query = "external@github.com"

      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_users

      assert_same_elements [@user_with_primary_email, user_with_primary_2], searcher.results.users
    end

    test "does not find any user with the same user id as a business external billing email" do
      user_with_primary_2 = create :user, email: "primary2@github.com"
      new_email = create :billing_external_email, owner: @business, email: "external@github.com"
      new_email.update_attribute(:owner_id, user_with_primary_2.id)
      query = "external@github.com"

      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_users

      assert_same_elements [@user_with_primary_email], searcher.results.users
    end
  end

  context "#search_for_businesses" do
    if GitHub.single_business_environment?
      test "doesn't find a business by slug if GitHub.single_business_environment?" do
        query = "haha-business"
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_businesses
        assert_equal searcher.results.businesses, []
      end
    else
      test "finds business by ID" do
        query = @business.id.to_s
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_businesses
        assert_equal searcher.results.businesses, [@business]
      end

      test "finds business by slug" do
        query = "haha-business"
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_businesses
        assert_equal searcher.results.businesses, [@business]
      end

      test "fuzzy businesses search" do
        one = create :business, name: "ACME"
        two = create :business, name: "Acme, Inc"
        three = create :business, name: "Acme Enterprises, Ltd"
        make_searchable one, two, three, type: "enterprise"

        query = "acme"
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_businesses
        assert_same_elements [one, two, three], searcher.results.businesses
      end

      test "finds soft-deleted businesses" do
        active = create :business, name: "Random Studios"
        make_searchable active, type: "enterprise"
        deleted = create :business, name: "Random Industries, Ltd"
        deleted.soft_delete!

        searcher = ::Stafftools::Searcher.new("random", @user)
        searcher.search_for_businesses

        assert_same_elements [active], searcher.results.businesses
        assert_same_elements [deleted], searcher.results.deleted_businesses
      end

      test "finds business by SDN screening ID" do
        profile = create(:account_screening_profile, :with_business)
        query = profile.external_uuid
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_businesses
        assert_includes searcher.results.businesses, profile.owner
      end
    end
  end

  context "#search_for_customers" do
    if GitHub.single_business_environment?
      test "doesn't find a customer by ID if GitHub.single_business_environment?" do
        query = "1"
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_customers
        assert_equal searcher.results.customers, []
      end
    else
      test "finds customer by ID" do
        query = @customer.id.to_s
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_customers
        assert_equal searcher.results.customers, [@customer]
      end

      test "finds customer by Zuora subscription number" do
        query = @customer.zuora_account_number
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_customers
        assert_equal searcher.results.customers, [@customer]
      end

      test "finds customer by Azure subscription ID" do
        query = @customer.zuora_account_id
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_customers
        assert_equal searcher.results.customers, [@customer]
      end
    end
  end

  context "#search_for_renamed_users" do
    test "audit log results is called" do
      query = "renamed-user"
      phrase = "(user:#{query} OR org:#{query})"
      searcher = ::Stafftools::Searcher.new(query, @user)

      searcher.search_for_renamed_users
    end

    test "renamed_user and old_name variables are not set when no logs match" do
      query = @user.login
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_renamed_users

      assert_nil searcher.results.renamed_user
      assert_nil searcher.results.old_name
    end

    test "renamed_user and old_name variables are correctly set" do
      previous_name = "renamed-user"
      searcher = ::Stafftools::Searcher.new(previous_name, @user)
      searcher.search_for_renamed_users

      assert_equal previous_name, searcher.results.old_name
      assert_equal "foobar", searcher.results.renamed_user.login
    end

    # https://github.com/github/github/issues/173639
    test "renamed_user1 search case insensitive" do
      previous_name_not_matching_old_case = "casesensitiveuser"
      searcher = ::Stafftools::Searcher.new(previous_name_not_matching_old_case, @user)
      searcher.search_for_renamed_users

      assert_equal previous_name_not_matching_old_case, searcher.results.old_name
      assert_equal "new-user-name", searcher.results.renamed_user.login
    end

    # https://github.com/github/github/issues/173639
    test "renamed_user1 search with sensitive casing test" do
      previous_name_not_matching_old_case = "CaseSensitiveUser"
      searcher = ::Stafftools::Searcher.new(previous_name_not_matching_old_case, @user)
      searcher.search_for_renamed_users

      assert_equal previous_name_not_matching_old_case, searcher.results.old_name
      assert_equal "new-user-name", searcher.results.renamed_user.login
    end
  end

  context "#search_for_repositories" do
    test "fuzzy repository search" do
      repo1 = create :repository, name: "slash_hack"
      repo2 = create :repository, name: "github"
      repo3 = create :repository, name: "stafftools"
      make_searchable(repo1, repo2, repo3)
      query = "slash"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_repositories

      assert_equal searcher.results.repositories, [repo1]
    end

    test "fuzz repository search has no match" do
      create :repository, :minimal, name: "github"
      query = "slash"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_repositories

      assert_empty searcher.results.repositories
    end

    test "repos search finds repo using full repository name" do
      repo = create :repository, :minimal, name: "stafftools", owner: @user
      repo1 = create(:repository, :minimal)
      query = "#{@user.login}/#{repo.name}"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_repositories

      assert_equal searcher.results.repositories, [repo]
    end

    test "repos search finds repo using repo id" do
      repo = create :repository, :minimal, name: "stafftools"
      repo1 = create(:repository, :minimal)
      query = "#{repo.id}"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_repositories

      assert_equal searcher.results.repositories, [repo]

      # delete the first repo and create another with the same name
      repo.remove(User.ghost, synchronous: true)
      repo2 = create :repository, :minimal, name: "stafftools"

      # should fail to find the original repo by id
      query = "#{repo.id}"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_repositories

      assert_empty searcher.results.repositories

      # should find the new repo by id
      query = "#{repo2.id}"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_repositories

      assert_equal searcher.results.repositories, [repo2]
    end

    test "results are unique" do
      repo1 = create :repository, name: "slash_hack"
      repo2 = create :repository, name: "slash"
      make_searchable(repo1, repo2)
      query = "slash"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_repositories

      assert_equal searcher.results.repositories, [repo2, repo1]
    end
  end

  context "#search_for_gists" do
    test "finds gists using owner" do
      query = "#{@user.login}/#{@gist.repo_name}"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_gists

      assert_equal searcher.results.gists, [@gist]
    end

    test "finds gists using repo name" do
      query = @gist.repo_name
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_gists

      assert_equal searcher.results.gists, [@gist]
    end

    test "finds archived gists using owner" do
      @gist.stub(:remove_from_disk, nil) do
        archived_gist = @gist.remove(async: false)

        refute @gist.active?

        query = "#{@user.login}/#{@gist.repo_name}"
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_gists

        assert_equal searcher.results.gists, [archived_gist]
      end
    end

    test "finds archived gists using repo name" do
      @gist.stub(:remove_from_disk, nil) do
        archived_gist = @gist.remove(async: false)

        refute @gist.active?

        query = @gist.repo_name
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_gists

        assert_equal searcher.results.gists, [archived_gist]
      end
    end
  end

  context "#search_for_oauth_application" do
    test "does not set oauth_apps when there are no apps" do
      query = "invalid_app_id_and_name"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_oauth_application

      assert_empty searcher.results.oauth_app_user_counts
      assert_empty searcher.results.oauth_apps
    end

    test "finds apps using app id" do
      query = @app1.id.to_s
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_oauth_application

      assert_equal searcher.results.oauth_app_user_counts, { @app1.id => 1 }
      assert_equal searcher.results.oauth_apps, [@app1]
    end

    test "finds apps using app name" do
      query = @app2.name
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_oauth_application

      assert_equal searcher.results.oauth_app_user_counts, { @app2.id => 1 }
      assert_equal searcher.results.oauth_apps, [@app2]
    end

    test "find apps using the app's name when there are no users" do
      app = create(:oauth_application)
      query = app.name
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_oauth_application

      assert_predicate searcher.results.oauth_app_user_counts, :empty?
      assert_equal searcher.results.oauth_apps, [app]
    end

    test "find apps using the app id when there are no users" do
      app = create(:oauth_application)
      query = app.id.to_s
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_oauth_application

      assert_predicate searcher.results.oauth_app_user_counts, :empty?
      assert_equal searcher.results.oauth_apps, [app]
    end
  end

  context "#search_for_teams" do
    test "finds a team using organization/team" do
      query = "#{@team.organization.login}/#{@team.slug}"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_teams

      assert_equal searcher.results.teams, [@team]
    end

    test "finds a team using database ID" do
      query = @team.id.to_s
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_teams

      assert_equal searcher.results.teams, [@team]
    end

    test "empty if GraphQL ID is not of a team" do
      query = @business.global_relay_id
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_teams

      assert_empty searcher.results.teams
    end

    test "empty if organization/team is not a match" do
      %W(foo/bar
         #{@team.organization.login}/bar
         foo/#{@team.slug}).each do |query|
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_for_teams

        assert_empty searcher.results.teams, "#{query} should not match"
      end
    end

    test "empty if number is not a database ID for a team" do
      query = (Team.order(:id).last.id + 1).to_s
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_teams

      assert_empty searcher.results.teams
    end
  end

  context "#search_for_integrations" do
    test "finds integrations using id" do
      query = "59"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_integrations

      assert_equal searcher.results.integrations, [@integ2]
    end

    test "finds integrations using name" do
      query = "pokemon teleporter"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_integrations

      assert_equal searcher.results.integrations, [@integ1]
    end

    test "finds integration installations using id" do
      repo = create :repository, :minimal, name: "slash_hack", owner: @user
      install = @integ1.install_on(@user, repositories: [repo], installer: @user, entry_point: :test_case).installation

      query = install.id.to_s
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_integrations

      assert_equal searcher.results.integration_installations, [install]
    end

    test "only searches for installations if the query is a number" do
      query = "12345678999@163.com"
      searcher = ::Stafftools::Searcher.new(query, @user)

      searcher.expects(:integration_installations_search).never
      searcher.search_for_integrations
    end
  end

  context "#search_by_global_relay_id" do
    test "finds repositories" do
      repo = create(:repository, :minimal)
      query = repo.global_relay_id
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_by_global_relay_id
      assert_equal searcher.results.repositories, [repo]
    end

    test "finds integrations" do
      query = @integ1.global_relay_id
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_by_global_relay_id
      assert_equal searcher.results.integrations, [@integ1]
    end

    test "finds users" do
      query = @user.global_relay_id
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_by_global_relay_id
      assert_equal searcher.results.users, [@user]
    end

    test "finds organizations" do
      query = @team.organization.global_relay_id
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_by_global_relay_id
      assert_equal searcher.results.users, [@team.organization]
    end

    if GitHub.single_business_environment?
      test "doesn't find a business if GitHub.single_business_environment?" do
        query = @business.global_relay_id
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_by_global_relay_id
        assert_equal searcher.results.businesses, []
      end
    else
      test "finds business" do
        query = @business.global_relay_id
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_by_global_relay_id
        assert_equal searcher.results.businesses, [@business]
      end
    end

    test "finds teams" do
      query = @team.global_relay_id
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_by_global_relay_id
      assert_equal searcher.results.teams, [@team]
    end

    test "does not find anything if the ID decodes to something that does not exist in the DB" do
      objects = [
        Team.new(id: 0, organization_id: 0),
        Repository.new(id: 0),
        build(:integration, id: 0, owner: create(:organization)),
        User.new(id: 0),
        Business.new(id: 0),
        Organization.new(id: 0)
      ]

      objects.each do |object|
        query = object.global_relay_id
        searcher = ::Stafftools::Searcher.new(query, @user)
        searcher.search_by_global_relay_id

        results_name = object.is_a?(User) ? "users" : object.class.name.downcase.pluralize # organizations are users
        assert_empty searcher.results.send(results_name), "expected empty result set for #{object.name}"
      end
    end
  end

  context "#search_for_hook" do
    test "finds hooks by id" do
      repo = create :repository, :minimal, owner: @user
      repo_hook = create :hook, :web,
        installation_target: repo,
        config: { "url" => "http://example.com" },
        events: %w(push),
        creator: @user

      query = repo_hook.id.to_s
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_hook

      assert_equal searcher.results.hook, repo_hook
    end
  end

  context "#search_for_public_key" do
    test "finds key by fingerprint" do
      key = create(:public_key, user: @user)

      query = key.fingerprint_sha256
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_public_key

      assert_equal searcher.results.public_key, key
    end

    test "finds key by fingerprint with prefix" do
      key = create(:public_key, user: @user)

      query = key.fingerprint_sha256
      searcher = ::Stafftools::Searcher.new("SHA256:#{query}", @user)
      searcher.search_for_public_key

      assert_equal searcher.results.public_key, key
    end

    test "public key variable not set when no key is found" do
      query = "SHA256:b6tYdGNBEMDLkp1ij0yxsGle86YsYatp1OcvJYdoIkM"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_public_key

      assert_nil searcher.results.public_key
    end
  end

  context "#search_for_oauth_access_token" do
    test "returns early when query does not match token pattern" do
      query = "ABCDEFG0101234"
      searcher = ::Stafftools::Searcher.new(query, @user)
      result = searcher.search_for_oauth_access_token

      assert_equal searcher, result
      assert_nil searcher.results.oauth_access
    end

    test "finds and sets oauth_access variable" do
      app = create :oauth_application
      oa = create(:oauth_access, application: app, user: @user,
                            hashed_token: "F793xN7vBE69Mv0IfJFAccziY5MkN9C6Xr2qEbQ8pUY=")

      query = "abcdef1a2b3c4d5e6fa1b2c3d4e5f60123456789"
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_oauth_access_token

      assert_equal searcher.results.oauth_access, oa
    end
  end

  context "#search_for_oauth_application_by_key" do
    test "returns early when query does not match client id pattern" do
      query = "XXXXEFG0101234"
      searcher = ::Stafftools::Searcher.new(query, @user)
      result = searcher.search_for_oauth_application_by_key

      assert_equal searcher, result
      assert_nil searcher.results.oauth_application
    end

    test "finds and sets oauth_application variable" do
      app = create :oauth_application, user: @user

      query = app.key
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_oauth_application_by_key

      assert_equal searcher.results.oauth_application, app
    end
  end

  context "#search_for_integration_by_key" do
    test "returns early when query does not match client id pattern" do
      query = "XXXXEFG0101234"
      searcher = ::Stafftools::Searcher.new(query, @user)
      result = searcher.search_for_integration_by_key

      assert_equal searcher, result
      assert_nil searcher.results.integration
    end

    test "finds and sets integration variable" do
      app = create :integration, owner: @user

      query = app.key
      searcher = ::Stafftools::Searcher.new(query, @user)
      searcher.search_for_integration_by_key

      assert_equal searcher.results.integration, app
    end
  end
end
