# typed: true
# frozen_string_literal: true

require "test_helper"

class AutocompleteQueryTest < GitHub::TestCase
  fixtures do
    setup_search

    @actor = create(:user)
    @member = create(:user, email: "private@github.com")
    @profile = create(:profile, email: "public@github.com", user: @member)
    @organization = create :organization, login: "peek", admin: @actor

    @repo = create(:repository, owner: @organization)

    @suspended_user = create(:suspended_user)

    make_searchable(@actor, @member)

    unless GitHub.single_business_environment?
      @emu_user = create(:emu, :owner, login: "testuser-emu")
      @emu_enterprise = @emu_user.enterprise_managed_business
      @emu_user_suspended = create(:emu, business: @emu_enterprise, login: "testuser-emu-suspended")
      @emu_user_suspended.update(suspended_at: Time.now)
      @non_emu_enterprise = create(:business)
      @non_emu_user = create(:user, login: "testuser-non-emu")
      @non_emu_enterprise.add_user_accounts([@non_emu_user.id])
      @emu_organization = create(:enterprise_linked_organization, business: @emu_enterprise, admin: @emu_user)

      make_searchable(@emu_user, @non_emu_user)
    end
  end

  setup do
    setup_search
  end

  teardown { teardown_search }

  def query(query, organization: @organization, friends: nil, include_teams: false,
    org_members_only: false, orgs_only: false, with_orgs: false, actor: @actor,
    include_integration_installations: false, with_businesses: false, scope_businesses_to_ids: nil,
    repository: nil, exclude_suspended: false, business: nil, include_outside_collaborators: false,
    teams_only: false
  )
    AutocompleteQuery.new(
      actor,
      query,
      organization: organization,
      friends: friends,
      include_teams: include_teams,
      org_members_only: org_members_only,
      orgs_only: orgs_only,
      with_orgs: with_orgs,
      include_integration_installations: include_integration_installations,
      repository: repository,
      exclude_suspended: exclude_suspended,
      business: business,
      include_outside_collaborators: include_outside_collaborators,
      teams_only: teams_only,
      with_businesses: with_businesses,
      scope_businesses_to_ids: scope_businesses_to_ids
    )
  end

  context "#suggestions" do
    test "includes owners" do
      query = query(@actor.login)

      assert_includes query.suggestions, @actor
    end

    test "returns members when looked up by exact login" do
      query = query(@member.display_login)
      make_searchable(@member)
      refute @organization.member?(@member), "should not be member of org"
      assert_equal [@member], query.suggestions
    end

    test "returns members when looked up by partial match" do
      party = create(:user, login: "party")
      partial = create(:user, login: "partial")
      make_searchable(party, partial)
      query = query("part")

      assert_same_elements [party, partial], query.suggestions
    end

    test "returns non-members when looked up by profile email" do
      query = query(@member.profile_email)

      refute @organization.member?(@member), "should not be member of org"
      assert_equal [@member], query.suggestions
    end

    test "does not return members when looked up by non-profile emails" do
      query = query("private@github.com")

      refute @organization.member?(@member), "should not be member of org"
      refute query.suggestions?, "should not have any suggestions"
    end

    test "does not return members actor has blocked" do
      @member.block(@actor)
      query = query(@member.login)

      assert @actor.blocked_by?(@member), "member should be blocking actor"
      refute query.suggestions?, "should not have any suggestions"
    end

    unless TestEnv.test_with_all_emus?
      test "prioritizes users actor is following" do
        defiler = create(:user, login: "defiler")
        default = create(:user, login: "default")
        make_searchable(defiler, default)
        @actor.follow(default)

        query = query("def", organization: nil)

        assert_equal [default, defiler], query.suggestions
      end

      test "returns outside collaborators" do
        priv_repo = create(:private_repository, owner: @organization)
        collaborator = create(:user, login: "outsider")
        priv_repo.add_member(collaborator)

        query = query("out", organization: @organization, include_outside_collaborators: true)

        assert_equal [collaborator], query.suggestions
      end
    end

    # previously, outside collaborator suggestions were unbounded (could return hundreds or
    # thousands of teams), so this test guards against that from happening again
    test "returns a limited set of outside collaborators" do
      priv_repo = create(:private_repository, owner: @organization)
      (1..25).each do |i|
        collaborator = create(:collaborator, repository: priv_repo, login: "collaborator#{i}")
      end

      query = query("collab", organization: @organization, include_outside_collaborators: true)
      assert_equal 10, query.suggestions.size
    end

    test "excludes outside collaborators" do
      priv_repo = create(:private_repository, owner: @organization)
      collaborator = create(:user, login: "outsider")
      priv_repo.add_member(collaborator)

      query = query("out", organization: @organization)

      assert_empty query.suggestions
    end

    context "include_teams" do
      test "does not return teams if include_teams option is false" do
        friends = create :team, organization: @organization, name: "friends"
        foes = create :team, organization: @organization, name: "foes"
        query = query("peek/friends", include_teams: false)

        assert_empty query.suggestions
      end

      test "matches org/team will only return team suggestions" do
        friends = create :team, organization: @organization, name: "friends"
        foes = create :team, organization: @organization, name: "foes"
        query = query("peek/friends", include_teams: true)

        assert_same_elements [friends], query.suggestions, "should have friends team"
      end

      test "matches org/any will return org teams in suggestions" do
        friends = create :team, organization: @organization, name: "friends"
        foes = create :team, organization: @organization, name: "foes"
        query = query("peek/", include_teams: true)

        assert_same_elements @organization.teams, query.suggestions, "should return all org teams"
      end

      test "when enabled will match both teams and users" do
        friends_team = create :team, organization: @organization, name: "friends"
        friends_user = create :user, login: "friends"
        make_searchable(friends_user)
        query = query("friends", include_teams: true)

        refute @organization.member?(friends_user)
        assert_same_elements [friends_team, friends_user], query.suggestions, "should have user and team friends"
      end

      test "when disabled will only search for users" do
        query = query("dewski", include_teams: true)

        refute query.suggestions?, "should be no suggestions"
      end

      test "does not match team when provided an email address query" do
        friends = create :team, organization: @organization, name: "friends"
        query = query("friends@example.com", include_teams: true)

        assert_empty query.suggestions, "should be empty"
      end

      # previously, team_suggestions were unbounded (could return hundreds or
      # thousands of teams), so this test guards against that happening again
      test "returns a limited set of teams" do
        (1..25).each do |i|
          team = create :team, organization: @organization, name: "team#{i}"
        end

        # query size should be limited to 10, similar to other suggestions
        query = query("team", include_teams: true)
        assert_equal 10, query.suggestions.size
      end

      test "teams with exact prefix matches are returned first" do
        (1..25).each do |i|
          team = create :team, organization: @organization, name: "#{i}oneofmany"
        end
        exact_team = create :team, organization: @organization, name: "oneofmany"
        team_b = create :team, organization: @organization, name: "oneofmany-b"
        team_a = create :team, organization: @organization, name: "oneofmany-a"

        query = query("oneofmany", include_teams: true)
        assert_equal query.suggestions[0..2].map(&:name), [exact_team.name, team_a.name, team_b.name]
        assert_equal 10, query.suggestions.size
      end
    end

    context "teams_only" do
      test "when enabled will match only teams" do
        friends_team = create :team, organization: @organization, name: "friends"

        friends_user = create :user, login: "friends"
        make_searchable(friends_user)

        query = query("friends", teams_only: true)

        refute @organization.member?(friends_user)
        assert_same_elements [friends_team], query.suggestions, "should have team 'friends' and no users"

        query = query("peek/friends", teams_only: true)
        assert_same_elements [friends_team], query.suggestions, "should have team 'friends' and no users"
      end

      test "when disabled will match based on other options" do
        friends_team = create :team, organization: @organization, name: "friends"

        friends_user = create :user, login: "friends"
        make_searchable(friends_user)

        query = query("friends", teams_only: false)

        refute @organization.member?(friends_user)
        assert_same_elements [friends_user], query.suggestions, "should not have teams in this instance"
      end
    end

    context "org_members_only" do
      test "returns all org members when actor is an org member" do
        org_user = create(:user, login: "abcd")
        private_org_user = create(:user, login: "abcd-private")
        non_org_user = create(:user, login: "abcde")

        make_searchable(org_user, non_org_user, private_org_user)

        @organization.add_member(@actor)
        @organization.add_member(org_user)
        @organization.add_member(private_org_user)
        @organization.publicize_member(org_user)
        @organization.conceal_member(private_org_user)

        assert @organization.member?(org_user)
        assert @organization.member?(private_org_user)
        refute @organization.member?(non_org_user)

        query = query("abc", org_members_only: true, actor: @actor)

        assert_same_elements [org_user, private_org_user], query.suggestions
      end

      test "returns only public org members when actor is outside collaborator" do
        org_user = create(:user, login: "abcd")
        private_org_user = create(:user, login: "abcd-private")
        non_org_user = create(:user, login: "abcde")
        searcher = create(:user)

        make_searchable(org_user, non_org_user, private_org_user)

        @organization.add_member(org_user)
        @organization.add_member(private_org_user)

        @repo.add_member(searcher)

        @organization.publicize_member(org_user)
        @organization.conceal_member(private_org_user)

        assert @organization.member?(org_user)
        refute @organization.member?(non_org_user)
        refute @organization.member?(searcher)

        query = query("abc", org_members_only: true, actor: searcher)

        assert_equal [org_user], query.suggestions
      end

      test "when org_members_only is false, no org filtering is done on the results" do
        org_user = create(:user, login: "abcd")
        private_org_user = create(:user, login: "abcd-private")
        non_org_user = create(:user, login: "abcde")
        searcher = create(:user)

        make_searchable(org_user, non_org_user, private_org_user)

        @organization.add_member(@actor)
        @organization.add_member(org_user)
        @organization.add_member(private_org_user)

        @repo.add_member(searcher)

        @organization.publicize_member(org_user)
        @organization.conceal_member(private_org_user)

        assert @organization.member?(org_user)
        refute @organization.member?(non_org_user)
        refute @organization.member?(searcher)

        query = query("abc", org_members_only: false, actor: searcher)

        assert_same_elements [org_user, private_org_user, non_org_user], query.suggestions
      end
    end

    context "orgs_only" do
      if TestEnv.test_with_all_emus?
        test "returns nothing" do
          org_one = create :organization, login: "suggested-org-one"
          org_two = create :organization, login: "suggested-org-two"
          user_one = create :user, login: "suggested-org-not-an-org-though"
          make_searchable org_one, org_two, user_one

          query = query "suggested-org", orgs_only: true, actor: @actor

          assert_same_elements [], query.suggestions
        end
      else
        test "returns orgs only" do
          org_one = create :organization, login: "suggested-org-one"
          org_two = create :organization, login: "suggested-org-two"
          user_one = create :user, login: "suggested-org-not-an-org-though"
          make_searchable org_one, org_two, user_one

          query = query "suggested-org", orgs_only: true, actor: @actor

          assert_same_elements [org_one, org_two], query.suggestions
        end

        test "does not return soft-deleted orgs", skip_enterprise: true do
          org_one = create :organization, login: "suggested-org-one"
          soft_deleted_org = create :organization, :soft_deleted, login: "suggested-org-soft-deleted"
          make_searchable org_one, soft_deleted_org

          query = query "suggested-org", orgs_only: true, actor: @actor

          assert_same_elements [org_one], query.suggestions
        end
      end
    end

    context "with_orgs" do
      if TestEnv.test_with_all_emus?
        test "returns nothing" do
          org_one = create :organization, login: "suggested-org-one"
          org_two = create :organization, login: "suggested-org-two"
          user_one = create :user, login: "suggested-org-not-an-org-though"
          make_searchable org_one, org_two, user_one

          query = query "suggested-org", with_orgs: true, actor: @actor

          assert_same_elements [], query.suggestions
        end
      else
        test "returns orgs" do
          org_one = create :organization, login: "suggested-org-one"
          org_two = create :organization, login: "suggested-org-two"
          user_one = create :user, login: "suggested-org-not-an-org-though"
          make_searchable org_one, org_two, user_one

          query = query "suggested-org", with_orgs: true, actor: @actor

          assert_same_elements [org_one, org_two, user_one], query.suggestions
        end

        test "does not return soft-deleted orgs", skip_enterprise: true do
          org_one = create :organization, login: "suggested-org-one"
          soft_deleted_org = create :organization, :soft_deleted, login: "suggested-org-soft-deleted"
          make_searchable org_one, soft_deleted_org

          query = query "suggested-org", with_orgs: true, actor: @actor

          assert_same_elements [org_one], query.suggestions
        end
      end
    end

    context "include_integration_installations" do
      test "does not return integration installations if include_integration_installations option is false" do
        app = create(:integration, name: "Appy App")
        make_integration_installation(integration: app, repository: @repo, permissions: { "contents" => :write })
        query = query("App", include_integration_installations: false, repository: @repo)

        assert_empty query.suggestions
      end

      test "matches integration installations by integration name or slug" do
        app = create(:integration, name: "Appy App")
        other_app = create(:integration, name: "Other App")
        other_repo = create(:repository, owner: @organization)
        app_installation = make_integration_installation(integration: app, repository: @repo, permissions: { "contents" => :write })
        other_app_installation = make_integration_installation(integration: other_app, repository: other_repo, permissions: { "contents" => :write })

        repo_query = query("Appy App", include_integration_installations: true, repository: @repo)
        assert_equal [app_installation], repo_query.suggestions

        other_repo_query = query("other-app", include_integration_installations: true, repository: other_repo)
        assert_equal [other_app_installation], other_repo_query.suggestions
      end

      test "matches integrations by bot slug" do
        app = create(:integration, name: "Appy App")
        app_installation = make_integration_installation(integration: app, repository: @repo, permissions: { "contents" => :write })

        query = query(app.bot.slug, include_integration_installations: true, repository: @repo)
        assert_equal [app_installation], query.suggestions
      end

      test "only matches integrations that are installed on the repository" do
        app = create(:integration, name: "Appy App")
        other_app = create(:integration, name: "Other App")
        other_repo = create(:repository, owner: @organization)
        app_installation = make_integration_installation(integration: app, repository: @repo, permissions: { "contents" => :write })
        make_integration_installation(integration: other_app, repository: other_repo, permissions: { "contents" => :write })

        query = query("App", include_integration_installations: true, repository: @repo)
        assert_equal [app_installation], query.suggestions
      end

      # GitHub Apps cannot be set to private if owner is enterprise managed.
      test "matches internal integrations that are installed on the repository", skip_with_all_emus: true do
        app = create(:integration, :private, name: "Internal App", owner: @repo.owner)
        installation = make_integration_installation(integration: app, repository: @repo, permissions: { "contents" => :write })

        query = query("Internal App", include_integration_installations: true, repository: @repo)
        assert_equal [installation], query.suggestions
      end

      test "excludes non user installable integrations that are installed on the repository" do
        non_installable_app = create_privileged_app_with_capabilities(
          capabilities: { user_installable: false },
          options: { name: "Non-installable App" }
        )
        make_integration_installation(integration: non_installable_app, repository: @repo, permissions: { "contents" => :write })

        query = query("Non-installable App", include_integration_installations: true, repository: @repo)
        assert_equal [], query.suggestions
      end
    end

    context "include_teams and include_integration_installations" do
      test "matches users, teams and integration installations" do
        team = create(:team, organization: @organization, name: "Squirrel Team")
        user = create(:user, login: "squirrel-user")
        make_searchable(user)
        app = create(:integration, name: "Squirrel App")
        app_installation = make_integration_installation(integration: app, repository: @repo, permissions: { "contents" => :write })

        query = query("squirrel", include_teams: true, include_integration_installations: true, repository: @repo)
        assert_equal [team, user, app_installation], query.suggestions
      end
    end

    context "exclude_suspended" do
      unless TestEnv.test_with_all_emus?
        test "result includes suspended when exclude_suspended: false" do
          make_searchable(@suspended_user)
          query = query(@suspended_user.display_login[0..8], exclude_suspended: false)
          assert_includes query.suggestions.map(&:display_login), @suspended_user.display_login
        end
      end

      test "result excludes suspended when exclude_suspended: true" do
        make_searchable(@suspended_user)
        query = query(@suspended_user.display_login[0..8], exclude_suspended: true)
        refute_includes query.suggestions.map(&:display_login), @suspended_user.display_login
      end
    end

    context "business" do
      unless GitHub.single_business_environment?
        test "returns enterprise managed users when passed an EMU business" do
          assert_predicate @emu_user, :is_enterprise_managed?

          query = query("testuser", business: @emu_enterprise)
          make_searchable(@emu_user)

          # @non_emu_user is not included in the suggestions
          assert_same_elements query.suggestions, [@emu_user]
        end

        test "do not return suspended EMU users when performing search as an EMU user" do
          assert_predicate @emu_user, :is_enterprise_managed?

          query = query("testuser", actor: @emu_user, business: @emu_enterprise)
          make_searchable(@emu_user, @emu_user_suspended)

          # @non_emu_user and @emu_user_suspended are not included in the suggestions
          assert_same_elements query.suggestions, [@emu_user]
        end

        test "does not return users from other EMU business" do
          @emu_user_2 = create(:emu, :owner, login: "testuser-emu-2")
          @emu_enterprise_2 = @emu_user_2.enterprise_managed_business

          make_searchable(@emu_user_2)

          assert_predicate @emu_user, :is_enterprise_managed?
          assert_predicate @emu_user_2, :is_enterprise_managed?

          query = query("testuser", business: @emu_enterprise_2)

          # @non_emu_user and @emu_user are not included in the suggestions
          assert_same_elements query.suggestions, [@emu_user_2]
        end

        test "returns matching businesses" do
          business = create(:business, name: "business")
          make_searchable(business)
          query = query("business", with_businesses: true)
          assert_same_elements query.suggestions, [business]
        end

        test "returns matching businesses limited to given ids" do
          business1 = create(:business, name: "business-1")
          business2 = create(:business, name: "business-2")
          make_searchable(business1, business2)

          query = query("business", with_businesses: true)
          assert_same_elements query.suggestions, [business1, business2]

          query = query("business", with_businesses: true, scope_businesses_to_ids: [business1.id])
          assert_same_elements query.suggestions, [business1]
        end
      end
    end
  end

  context "#user_query?" do
    test "returns true when matching non-email input" do
      query = query("dewski")
      assert query.user_query?, "should be user query"

      query = query("special-case")
      assert query.user_query?, "should be user query with hyphen"

      query = query("dewski ")
      assert query.user_query?, "should be user query with trailing space"
    end

    test "returns false when matching email input" do
      query = query("dewski@github.com")
      refute query.user_query?, "should be user query"

      query = query("dewski@localhost")
      refute query.user_query?, "should be user query"
    end
  end

  context "#email_query?" do
    test "returns true when matching email input" do
      query = query("dewski@github.com")
      assert query.email_query?, "should be email query"

      query = query("dewski@localhost")
      assert query.email_query?, "should be email query"

      query = query("dewski@localhost ")
      assert query.email_query?, "should be email query with trailing space"

      query = query(" dewski@localhost")
      assert query.email_query?, "should be email query with leading space"

      query = query(" dewski@localhost ")
      assert query.email_query?, "should be email query with spaces"
    end

    test "returns false when matching non-email input" do
      query = query("dewski")
      refute query.email_query?, "should be email query"

      query = query("special case")
      refute query.email_query?, "should be email query"
    end
  end

  context "#allow_email_invites?" do
    test "returns false when an organization is not present" do
      query = query("irrelevant", organization: nil)
      refute_predicate query, :allow_email_invites?
    end

    unless TestEnv.test_with_all_emus?
      test "returns true when the organization is present" do
        GitHub.stubs(:bypass_org_invites_enabled?).returns(false)
        query = query("irrelevant")
        assert_predicate query, :allow_email_invites?
      end
    end

    test "returns false when bypass_org_invites_enabled" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)
      query = query("irrelevant")
      refute_predicate query, :allow_email_invites?
    end

    test "returns false when organization belongs to EMU enterprise", skip_enterprise: true do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(false)

      query = query("irrelevant", organization: @emu_organization, actor: @emu_user)
      refute_predicate query, :allow_email_invites?
    end
  end

  context "#email_invitation?" do
    test "returns true when there no results" do
      query = query("garrett@github.com")

      assert query.email_query?, "should be email query"
      refute query.suggestions?, "should not be any results"
      assert query.email_invitation?, "should be email invitation"
    end

    test "returns false when there are results" do
      @organization.add_member(@member)
      query = query(@member.profile_email)

      assert query.email_query?, "should be email query"
      assert query.suggestions?, "should have results"
      refute query.email_invitation?, "should not be email invitation"
    end

    test "needs to be email query" do
      @organization.add_member(@member)
      query = query(@actor.login)

      assert query.suggestions?, "should have results"
      refute query.email_query?, "should not be email query"
      refute query.email_invitation?, "should not be email invitation"
    end

    test "returns false when prefixed with mailto:" do
      query = query("mailto:garrett@github.com")

      assert_predicate query, :email_query?, "should be email query"
      refute_predicate query, :suggestions?, "should not be any results"
      refute_predicate query, :email_invitation?, "should be email invitation"
    end
  end

  context "#friends" do
    test "returns org members when organization is present" do
      @organization.add_member(@member)
      query = query(@member.login)

      assert_same_elements [@actor, @member], query.friends
    end

    test "returns users being followed by viewer when organization not present" do
      @organization.add_member(@member)
      query = query(@member.login, organization: nil)
      someone_to_follow = create(:user, login: "leader")
      make_searchable(someone_to_follow)
      @actor.follow(someone_to_follow)

      assert_same_elements @actor.following, query.friends
    end
  end
end
