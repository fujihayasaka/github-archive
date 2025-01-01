# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotContentExclusion < GitHub::TestCase
  include CopilotTestHelper
  include DogstatsTestHelpers

  def paths_from_rules(urls)
    urls.map { |rules| rules.map { |_config, rules| rules.collect(&:patterns) }.flatten.uniq }
  end

  fixtures do
    # rules_for_repo_urls fixtures
    @user = create(:user)

    @org = create(:copilot_for_business_enabled_organization)
    @org_b = create(:organization)

    @org.add_member(@user, action: :admin)
    @org_b.add_member(@user, action: :admin)

    @business = @org.business
    @business.add_organization(@org_b)

    Copilot::Organization.new(@org).seat_management_allow_all!
    Copilot::Organization.new(@org_b).seat_management_allow_all!
    Copilot::Business.new(@business).enable_copilot!

    # Sets up 3 orgs:
    # 2 enabled through a busines
    # 1 in the business, but not enabled

    @enabled_org_one = create(:copilot_for_business_enabled_organization, login: "enabled-org-one")
    @business = @enabled_org_one.business
    @enabled_org_two = create(:organization, login: "enabled-org-two")
    @disabled_org = create(:organization, login: "disabled-org")

    @repo = create(:repository, owner: @enabled_org_one)

    @standalone_business = create(:business, seats_plan_type: :basic)

    create(:copilot_content_exclusion_configuration, :organization, resource: @enabled_org_one)
    create(:copilot_content_exclusion_configuration, :organization, resource: @enabled_org_two)
    create(:copilot_content_exclusion_configuration, :repository, resource: @repo)
    create(:copilot_content_exclusion_configuration, :business, resource: @standalone_business)

    @business.add_organization(@enabled_org_two)
    @business.add_organization(@disabled_org)

    Copilot::Business.new(@business).enable_copilot_for_selected_organizations!([@enabled_org_one.id, @enabled_org_two.id])
    Copilot::Business.new(@standalone_business).enable_copilot!

    Copilot::Organization.new(@enabled_org_one).enable_copilot!
    Copilot::Organization.new(@enabled_org_two).enable_copilot!
  end

  test "fixture test" do
    assert Copilot::Organization.new(@enabled_org_one).copilot_enabled?
    assert Copilot::Organization.new(@enabled_org_two).copilot_enabled?
    refute Copilot::Organization.new(@disabled_org).copilot_enabled?
  end

  context "is_available?" do
    test "should return true for a repository that is part of an organization with the feature available" do
      assert Copilot::ContentExclusion.is_available?(@repo)
    end

    test "should return true for a standalone organization with the feature available" do
      org = create(:copilot_for_business_enabled_non_enterprise_organization)
      assert Copilot::ContentExclusion.is_available?(org)
    end

    test "should return false for a repository not part of any organization" do
      refute Copilot::ContentExclusion.is_available?(create(:repository, :user_owned_public))
    end

    test "should return false for a repository with a nil owner" do
      assert Copilot::ContentExclusion.is_available?(@repo) # precondition

      # Sorbet has this the owner nilable, so lets test we handle this
      @repo.owner = nil

      refute Copilot::ContentExclusion.is_available?(@repo)
    end

    test "should return false for a repository in an organization without CFB access" do
      Copilot::Business.new(@business).disable_copilot!
      refute Copilot::ContentExclusion.is_available?(@repo)
    end
  end

  context "#content_exclusion_rules_for_repo_urls" do
    test "matches single repo" do
      repo = create(:repository, owner: @org)

      create(:copilot_content_exclusion_configuration, :repository, document: <<~YAML, resource: repo)
        - "repo-level"
      YAML

      create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org)
        "*": ["org-level-wildcard"]
        #{repo.ssh_url_for_api}: ["org-level-for-repo"]
      YAML

      paths = paths_from_rules Copilot::ContentExclusion.rules_for_repo_urls([repo.ssh_url_for_api], organization_ids: [@org.id])

      assert_equal [
        %w(org-level-wildcard org-level-for-repo repo-level)
      ], paths
    end

    test "resolves paths across orgs within the same business" do
      create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org)
        "*": ["org-level-wildcard"]
      YAML

      create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org_b)
        https://bitbucket.com/team/repo: ["org-level-for-bitbucket"]
      YAML

      paths = paths_from_rules Copilot::ContentExclusion.rules_for_repo_urls(["https://bitbucket.com/team/repo"], organization_ids: [@org.id])
      assert_equal [
        %w(org-level-wildcard org-level-for-bitbucket)
      ], paths
    end

    test "works with nwo through enterprise" do
      repo = create(:repository, owner: @org)

      create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org_b)
        #{repo.ssh_url_for_api}: ["org-level-for-repo"]
      YAML

      paths = paths_from_rules Copilot::ContentExclusion.rules_for_repo_urls([repo.ssh_url_for_api], organization_ids: [@org.id])
      assert_equal [
        %w(org-level-for-repo)
      ], paths
    end

    test "fail to return paths for a random repo the user doesnt have access too" do
      repo = create(:repository)

      paths = paths_from_rules Copilot::ContentExclusion.rules_for_repo_urls([repo.ssh_url_for_api], organization_ids: [@org.id])
      assert_equal [[]], paths
    end

    test "matches for multiple repos :: only org level" do
      create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org)
        git@my-git.com:team/repo-a: ["repo-a"]
        git@my-git.com:team/repo-b: ["org-a_repo-b"]
      YAML

      create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org_b)
        git@my-git.com:team/repo-b: ["repo-b"]
      YAML

      paths = paths_from_rules Copilot::ContentExclusion.rules_for_repo_urls(["https://my-git.com/team/repo-a", "https://my-git.com/team/repo-b"], organization_ids: [@org.id, @org_b.id])
      assert_equal [
        %w(repo-a),
        %w(org-a_repo-b repo-b),
      ], paths
    end

    test "matches for multiple repos :: only repo level" do
      repo_a = create(:repository, owner: @org)
      repo_b = create(:repository, owner: @org_b)

      create(:copilot_content_exclusion_configuration, :repository, document: <<~YAML, resource: repo_a)
        ["repo-a"]
      YAML

      create(:copilot_content_exclusion_configuration, :repository, document: <<~YAML, resource: repo_b)
        ["repo-b"]
      YAML

      paths = paths_from_rules Copilot::ContentExclusion.rules_for_repo_urls([repo_a.ssh_url_for_api, repo_b.ssh_url_for_api], organization_ids: [@org.id, @org_b.id])
      assert_equal [
        %w(repo-a),
        %w(repo-b),
      ], paths
    end

    test "matches for multiple repos" do
      repo_a = create(:repository, owner: @org)

      create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org)
        #{repo_a.ssh_url_for_api}: ["org-level-for-repo"]
        git@my-git.com:team/repo-b: ["org-a_repo-b"]
      YAML

      create(:copilot_content_exclusion_configuration, :repository, document: <<~YAML, resource: repo_a)
        ["repo-a"]
      YAML

      paths = paths_from_rules Copilot::ContentExclusion.rules_for_repo_urls([repo_a.ssh_url_for_api, "git@my-git.com:team/repo-b"], organization_ids: [@org.id])
      assert_equal [
        %w(org-level-for-repo repo-a),
        %w(org-a_repo-b),
      ], paths
    end

    test "does not return rules for repo a user does not have access too" do
      create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org)
        "*": ["org-level-wildcard"]
      YAML

      config = create(:copilot_content_exclusion_configuration, :repository, document: <<~YAML)
        ["repo-a"]
      YAML

      random_repo_url_that_does_exist = config.resource.ssh_url_for_api

      paths = paths_from_rules Copilot::ContentExclusion.rules_for_repo_urls([random_repo_url_that_does_exist], organization_ids: [@org.id])
      assert_equal [
        %w(org-level-wildcard),
      ], paths
    end

    test "returns content exclusion rules for user with no org-level configuration set" do
      user = create(:user)

      org = create(:copilot_for_business_enabled_organization)
      org.add_member(user, action: :admin)
      Copilot::Organization.new(org).seat_management_allow_all!

      repo = create(:repository, owner: org)

      create(:copilot_content_exclusion_configuration, :repository, document: <<~YAML, resource: repo)
          - "*.js"
          - "/**/*.js"
      YAML

      assert_empty Copilot::ContentExclusionConfiguration.for_organization(org)
      assert Copilot::ContentExclusionConfiguration.for_repository(repo).any?

      paths = paths_from_rules Copilot::ContentExclusion.rules_for_repo_urls([repo.ssh_url_for_api], organization_ids: [org.id])

      assert_equal [
        [
          "*.js",
          "/**/*.js",
        ]
      ], paths
    end

    test "returns content exclusion rules for user with no org-level configuration set but through an enterprise" do
      user = create(:user)

      org = create(:copilot_for_business_enabled_organization)
      org_b = create(:organization)

      org.add_member(user, action: :admin)
      org_b.add_member(user, action: :admin)

      org.business.add_organization(org_b)
      Copilot::Organization.new(org).seat_management_allow_all!
      Copilot::Organization.new(org_b).seat_management_disable!

      # Note; User only has a seat in org_a, but the org_b is part of the same business
      repo = create(:repository, owner: org_b)

      create(:copilot_content_exclusion_configuration, :repository, document: <<~YAML, resource: repo)
        - "*.js"
        - "/**/*.js"
      YAML

      assert_empty Copilot::ContentExclusionConfiguration.for_organization(org)
      assert Copilot::ContentExclusionConfiguration.for_repository(repo).any?

      paths = paths_from_rules Copilot::ContentExclusion.rules_for_repo_urls([repo.ssh_url_for_api], organization_ids: [org.id])

      assert_equal [
        [
          "*.js",
          "/**/*.js"
        ]
      ], paths
    end

    context "ga enhancements" do
      test "logs when the user is feature flagged with a neighbour" do
        Copilot::Organization.new(@org_b).seat_management_selected_teams_and_users!(keep_assignments: false)

        create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org)
          git@github.com:monalisa/smile: ["org_a_rules"]
        YAML
        create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org_b)
          git@github.com:monalisa/smile: ["org_b_rules"]
        YAML

        logs = capture_logs do
          rules = T.must(Copilot::ContentExclusion.rules_for_repo_urls(["git@github.com:monalisa/smile"], organization_ids: [@org.id], neighbour_influence: true).first)

          assert_equal 2, rules.count
        end

        # one was a neighbour, becuase the user does not have a seat there
        assert_dogstats_increment(1, "copilot.content_exclusion.returned_rules", tags: ["is_neighbour:false", "has_wildcard:false", "shares_enterprise:true"])
        assert_dogstats_increment(1, "copilot.content_exclusion.returned_rules", tags: ["is_neighbour:true", "has_wildcard:false", "shares_enterprise:true"])

        assert_includes logs, "Content exclusions returned rules for a neighbouring organization"
        assert_log_matches logs, {
          "gh.org.id" => @org_b.id,
          "has_wildcard" => false,
          "shares_enterprise" => true
        }
      end

      test "does not log when the user isnt feature flagged" do
        Copilot::Organization.new(@org_b).seat_management_selected_teams_and_users!(keep_assignments: false)

        create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org)
          git@github.com:monalisa/smile: ["org_a_rules"]
        YAML
        create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org_b)
          git@github.com:monalisa/smile: ["org_b_rules"]
        YAML

        logs = capture_logs do
          rules = T.must(Copilot::ContentExclusion.rules_for_repo_urls(["git@github.com:monalisa/smile"], organization_ids: [@org.id], neighbour_influence: false).first)
          assert_equal 2, rules.count
        end

        refute_dogstats_increment("copilot.content_exclusion.returned_rules")

        refute_includes logs, "Content exclusions returned rules for a neighbouring organization"
      end

      test "logs when the user is feature flagged without a neighbour" do
        create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org)
          git@github.com:monalisa/smile: ["org_a_rules"]
        YAML
        create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org_b)
          git@github.com:monalisa/smile: ["org_b_rules"]
        YAML

        logs = capture_logs do
          rules = T.must(Copilot::ContentExclusion.rules_for_repo_urls(["git@github.com:monalisa/smile"], organization_ids: [@org.id, @org_b.id], neighbour_influence: true).first)

          assert_equal 2, rules.count
        end

        assert_dogstats_increment(2, "copilot.content_exclusion.returned_rules", tags: ["is_neighbour:false", "has_wildcard:false", "shares_enterprise:true"])

        refute_includes logs, "Content exclusions returned rules for a neighbouring organization"
      end

      test "logs when the user is feature flagged and has a wildcard" do
        Copilot::Organization.new(@org_b).seat_management_selected_teams_and_users!(keep_assignments: false)

        create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org)
          "*": ["org_a_rules"]
        YAML
        create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org_b)
          git@github.com:monalisa/smile: ["org_b_rules"]
        YAML

        logs = capture_logs do
          rules = T.must(Copilot::ContentExclusion.rules_for_repo_urls(["git@github.com:monalisa/smile"], organization_ids: [@org.id], neighbour_influence: true).first)

          assert_equal 2, rules.count
        end

        assert_dogstats_increment(1, "copilot.content_exclusion.returned_rules", tags: ["is_neighbour:false", "has_wildcard:true", "shares_enterprise:true"])
        assert_dogstats_increment(1, "copilot.content_exclusion.returned_rules", tags: ["is_neighbour:true", "has_wildcard:false", "shares_enterprise:true"])

        assert_includes logs, "Content exclusions returned rules for a neighbouring organization"
        assert_log_matches logs, {
          "gh.org.id" => @org_b.id,
          "has_wildcard" => false,
          "shares_enterprise" => true
        }
      end

      test "logs when the user is feature flagged and has a wildcard on the neighbour" do
        Copilot::Organization.new(@org_b).seat_management_selected_teams_and_users!(keep_assignments: false)

        create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org)
          git@github.com:monalisa/smile: ["org_a_rules"]
        YAML
        create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org_b)
          "*": ["org_b_rules"]
        YAML

        logs = capture_logs do
          rules = T.must(Copilot::ContentExclusion.rules_for_repo_urls(["git@github.com:monalisa/smile"], organization_ids: [@org.id], neighbour_influence: true).first)

          assert_equal 2, rules.count
        end

        assert_dogstats_increment(1, "copilot.content_exclusion.returned_rules", tags: ["is_neighbour:false", "has_wildcard:false", "shares_enterprise:true"])
        assert_dogstats_increment(1, "copilot.content_exclusion.returned_rules", tags: ["is_neighbour:true", "has_wildcard:true", "shares_enterprise:true"])

        assert_includes logs, "Content exclusions returned rules for a neighbouring organization"
        assert_log_matches logs, {
          "gh.org.id" => @org_b.id,
          "has_wildcard" => true,
          "shares_enterprise" => true
        }
      end

      test "logs when its from an org outside the enterprise as well" do
        Copilot::Organization.new(@org_b).seat_management_selected_teams_and_users!(keep_assignments: false)

        org_c = create(:copilot_for_business_enabled_organization)
        org_c.add_member(@user, action: :admin)

        Copilot::Organization.new(org_c).seat_management_allow_all!

        copilot_user = Copilot::User.new(@user)

        assert Copilot::Organization.new(org_c).copilot_enabled?
        assert_includes copilot_user.copilot_organizations.pluck(:id), org_c.id

        create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org)
          git@github.com:monalisa/smile: ["org_a_rules"]
        YAML
        create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: @org_b)
          git@github.com:monalisa/smile: ["org_b_rules"]
        YAML
        create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML, resource: org_c)
          "*": ["org_c_rules"]
        YAML


        logs = capture_logs do
          rules = T.must(Copilot::ContentExclusion.rules_for_repo_urls(["git@github.com:monalisa/smile"], organization_ids: [@org.id, org_c.id], neighbour_influence: true).first)

          assert_equal 3, rules.count
        end

        assert_dogstats_increment(1, "copilot.content_exclusion.returned_rules", tags: ["is_neighbour:false", "has_wildcard:false", "shares_enterprise:false"])
        assert_dogstats_increment(1, "copilot.content_exclusion.returned_rules", tags: ["is_neighbour:true", "has_wildcard:false", "shares_enterprise:false"])
        assert_dogstats_increment(1, "copilot.content_exclusion.returned_rules", tags: ["is_neighbour:false", "has_wildcard:true", "shares_enterprise:false"])

        assert_includes logs, "Content exclusions returned rules for a neighbouring organization"
        assert_log_matches logs, {
          "gh.org.id" => @org_b.id,
          "has_wildcard" => false,
          "shares_enterprise" => false,
        }
      end
    end

    context "when copilot standalone", skip_enterprise: true do
      test "returns content exclusion rules for standalone businesses" do
        business = create(:business, :default_managed, seats_plan_type: :basic)
        user = business.owners.first

        ent_team = create(:enterprise_team, business:)
        business.add_user_accounts([user.id], business_roles_bitfield: 0)
        ent_team.enterprise_team_memberships.create!(user_id: user.id)

        Copilot::Business.new(business).enable_copilot!

        seat_assignment = create(:copilot_seat_assignment,
          :enterprise_team,
          supplied_business: business,
          assignable: ent_team,
        )
        seat_assignment.convert_to_seats

        create(:copilot_content_exclusion_configuration, :business, document: <<~YAML, resource: business)
          "*": ["business-level-wildcard"]
        YAML

        paths = paths_from_rules Copilot::ContentExclusion.rules_for_repo_urls(["https://bitbucket.com/team/repo"], business_ids: [business.id])
        assert_equal [
          %w(business-level-wildcard)
        ], paths
      end

      test "returns content exclusion rules for standalone businesses when user also belongs to organizations" do
        business = create(:business, :default_managed, seats_plan_type: :basic)
        user = business.owners.first

        ent_team = create(:enterprise_team, business:)
        business.add_user_accounts([user.id], business_roles_bitfield: 0)
        ent_team.enterprise_team_memberships.create!(user_id: user.id)

        Copilot::Business.new(business).enable_copilot!

        seat_assignment = create(:copilot_seat_assignment,
          :enterprise_team,
          supplied_business: business,
          assignable: ent_team,
        )
        seat_assignment.convert_to_seats

        @org.add_member(user, action: :admin)

        create(:copilot_content_exclusion_configuration, :business, document: <<~YAML, resource: business)
          "*": ["business-level-wildcard"]
        YAML

        copilot_user = Copilot::User.new(user)

        assert copilot_user.copilot_organizations.count, 2

        paths = paths_from_rules Copilot::ContentExclusion.rules_for_repo_urls(["https://bitbucket.com/team/repo"], business_ids: [business.id])
        assert_equal [
          %w(business-level-wildcard)
        ], paths
      end
    end
  end

  context "#all_relevant_configurations"  do
    test "should return true for organization with neighboring configurations but no direct configuration" do
      org_1 = create(:copilot_for_business_enabled_organization)
      org_2 = create(:organization)

      org_1.business.add_organization(org_2)
      Copilot::Business.new(org_1.business).enable_copilot_for_all_organizations!

      create(:copilot_content_exclusion_configuration, :organization, resource: org_2)

      # not passing org_2, to simulate a user who is ONLY a member of org_1 and not org_2
      assert Copilot::ContentExclusion.all_relevant_configurations(organization_ids: [org_1.id]).any?
    end

    test "should return false for organization without any configurations or neighbors" do
      org = create(:copilot_for_business_enabled_organization)
      refute Copilot::ContentExclusion.all_relevant_configurations(organization_ids: [org.id]).any?
    end

    test "should return true for organization with CFB access and active configurations" do
      assert Copilot::ContentExclusion.all_relevant_configurations(organization_ids: [@enabled_org_one.id]).any?
    end

    test "should return true for standalone businesses with active rules" do
      assert Copilot::ContentExclusion.all_relevant_configurations(business_ids: [@standalone_business.id]).any?
    end

    test "should return false for non-standalone businesses with active rules" do
      non_standalone_business = create(:business, seats_plan_type: :full)
      create(:copilot_content_exclusion_configuration, :business, resource: non_standalone_business)

      refute Copilot::ContentExclusion.all_relevant_configurations(business_ids: [non_standalone_business.id]).any?
    end

    test "should return false for organization with configurations but without CFB access" do
      # This scneario mimics the case where an org was in a trial and tried the feature, but never purchased
      Copilot::Business.new(@business).disable_copilot!

      refute Copilot::ContentExclusion.all_relevant_configurations(organization_ids: [@enabled_org_one.id]).any?
    end

    test "should return false when passed an empty organization array" do
      refute Copilot::ContentExclusion.all_relevant_configurations(organization_ids: []).any?
    end

    test "should return false when the rules are empty" do
      org = create(:copilot_for_business_enabled_organization)
      config = create(:copilot_content_exclusion_configuration, :organization, resource: org)
      assert Copilot::ContentExclusion.all_relevant_configurations(organization_ids: [org.id]).any?
      config.update(document: "")
      refute Copilot::ContentExclusion.all_relevant_configurations(organization_ids: [org.id]).any?
    end

    test "returns configurations for enabled orgs" do
      configs = Copilot::ContentExclusion.all_relevant_configurations(organization_ids: [@enabled_org_one.id])

      assert_equal 3, configs.count
      assert_equal [@enabled_org_one.id, @enabled_org_two.id, @repo.id].sort, configs.map(&:resource_id).sort
    end

    test "does not return configurations for disabled orgs" do
      configs = Copilot::ContentExclusion.all_relevant_configurations(organization_ids: [@disabled_org.id])

      assert_equal 3, configs.count # we should see two because the org belongs to an enterprise with 2 available configs
      assert_equal [@enabled_org_one.id, @enabled_org_two.id, @repo.id].sort, configs.map(&:resource_id).sort
    end

    test "returns configurations for enabled standalone businesses" do
      configs = Copilot::ContentExclusion.all_relevant_configurations(business_ids: [@standalone_business.id], organization_ids: [])

      assert_equal 1, configs.count
      assert_equal [@standalone_business.id].sort, configs.map(&:resource_id).sort
    end

    test "does not return configurations for non-standalone businesses" do
      configs = Copilot::ContentExclusion.all_relevant_configurations(business_ids: [@business.id], organization_ids: [])

      assert_equal 0, configs.count
    end

    test "does not return configurations for disabled businesses" do
      standalone_disabled_business = create(:business, seats_plan_type: :basic)
      Copilot::Business.new(standalone_disabled_business).disable_copilot!

      create(:copilot_content_exclusion_configuration, :business, resource: standalone_disabled_business)

      configs = Copilot::ContentExclusion.all_relevant_configurations(business_ids: [standalone_disabled_business.id], organization_ids: [])

      assert_equal 0, configs.count
    end

    test "returns configurations for standalone orgs" do
      org = create(:copilot_for_business_enabled_non_enterprise_organization)
      create(:copilot_content_exclusion_configuration, :organization, resource: org)

      configs = Copilot::ContentExclusion.all_relevant_configurations(organization_ids: [org.id])

      assert_equal 1, configs.count
      assert_equal org.id, T.must(configs.first).resource_id
    end

    test "returns the union of enterprise orgs and standalone orgs" do
      org = create(:copilot_for_business_enabled_non_enterprise_organization)
      create(:copilot_content_exclusion_configuration, :organization, resource: org)

      configs = Copilot::ContentExclusion.all_relevant_configurations(organization_ids: [org.id, @enabled_org_two.id]) # purposely using org two here so we traverse up the enterprise

      assert_equal 4, configs.count
      assert_equal [@enabled_org_one.id, @enabled_org_two.id, org.id, @repo.id].sort, configs.map(&:resource_id).sort
    end
  end

end if GitHub.copilot_enabled?

class CopilotContentExclusionBase < GitHub::TestCase
  include CopilotTestHelper

  fixtures do
    # A user cannot be both a standalone enterprise user and a user in a GitHub enterprise, so we need to create two users
    @user = create(:user)
    @standalone_user = create(:user)

    # To test the flow thoroughly we need to create every possible combination of orgs and businesses
    # that a user could be attempt to access the repositories of. This includes:
    # 1. An org in a business that gives the user a seat
    @org_seated = create(:copilot_for_business_enabled_organization)
    @org_seated.add_member(@user, action: :admin)
    # 2. The parent business of that org
    @business_parent = @org_seated.business
    # 3. A neighbor org in the same business that the user does not have a seat in
    @org_neighbor = create(:copilot_for_business_enabled_organization, business: @business_parent)
    # 4. A foreign org in a different business that the user does not have a seat in
    @org_foreign = create(:copilot_for_business_enabled_organization)
    # 5. The parent business of the foreign org
    @business_foreign = @org_foreign.business
    # 6. A non-enterprise org that the user has a seat in
    @org_non_ent_seated = create(:copilot_for_business_enabled_non_enterprise_organization)
    @org_non_ent_seated.add_member(@user, action: :admin)
    # 7. A non-enterprise org that the user does not have a seat in
    @org_non_ent_unseated = create(:copilot_for_business_enabled_non_enterprise_organization)

    # 8. A standalone business that the standalone user has a seat in
    @business_standalone_seated = create(:business, :default_managed, seats_plan_type: :basic)
    enterprise_team = create(:enterprise_team, business: @business_standalone_seated)
    @business_standalone_seated.add_user_accounts([@standalone_user.id], business_roles_bitfield: 0)
    enterprise_team.enterprise_team_memberships.create!(user_id: @standalone_user.id)
    Copilot::Business.new(@business_standalone_seated).enable_copilot!
    create(:copilot_seat_assignment, :enterprise_team, supplied_business: @business_standalone_seated, assignable: enterprise_team).convert_to_seats

    # Note: We don't need a standalone business that the user does not have a seat in, as
    #       they do not have internal repositories and so would have no control over users
    #       outside of their own members.

    # Some helper arrays to make it easier to iterate over all the businesses and orgs
    @all_businesses = [@business_parent, @business_foreign, @business_standalone_seated]
    @all_orgs = [@org_seated, @org_neighbor, @org_foreign, @org_non_ent_seated, @org_non_ent_unseated]

    @all_orgs.each do |org|
      copilot_org = Copilot::Organization.new(org)
      copilot_org.seat_management_allow_all!
    end

    # Every org can have repositories, so lets create them now. Only business orgs can have internal visibility
    @repo_public_org_seated = create(:public_repository, owner: @org_seated)
    @repo_private_org_seated = create(:private_repository, owner: @org_seated)
    @repo_internal_org_seated = create(:internal_repository, owner: @org_seated)

    @repo_public_org_neighbor = create(:public_repository, owner: @org_neighbor)
    @repo_private_org_neighbor = create(:private_repository, owner: @org_neighbor)
    @repo_internal_org_neighbor = create(:internal_repository, owner: @org_neighbor)

    @repo_public_org_foreign = create(:public_repository, owner: @org_foreign)
    @repo_private_org_foreign = create(:private_repository, owner: @org_foreign)
    @repo_internal_org_foreign = create(:internal_repository, owner: @org_foreign)

    @repo_public_org_non_ent_seated = create(:public_repository, owner: @org_non_ent_seated)
    @repo_private_org_non_ent_seated = create(:private_repository, owner: @org_non_ent_seated)

    @repo_public_org_non_ent_unseated = create(:public_repository, owner: @org_non_ent_unseated)
    @repo_private_org_non_ent_unseated = create(:private_repository, owner: @org_non_ent_unseated)

    # We also need to check when we target external repositories, so lets create a representative one
    @external_repo_url = "git@fake-website.com:fake/repo.git"

    @all_repos = [
      @repo_public_org_seated, @repo_private_org_seated, @repo_internal_org_seated,
      @repo_public_org_neighbor, @repo_private_org_neighbor, @repo_internal_org_neighbor,
      @repo_public_org_foreign, @repo_private_org_foreign, @repo_internal_org_foreign,
      @repo_public_org_non_ent_seated, @repo_private_org_non_ent_seated,
      @repo_public_org_non_ent_unseated, @repo_private_org_non_ent_unseated
    ]

    @all_entities = @all_businesses + @all_orgs + @all_repos

    # Now we need to create content exclusion rules for each of these entities. We make every set of rules
    # target every repository, so that we can test that the correct rules are returned for each case.
    @all_entities.each { |entity| generate_content_exclusion_configuration(entity) }
  end

  # Generate a content exclusion configuration for a given resource.
  # Can be Business, Organization, or Repository
  def generate_content_exclusion_configuration(resource)
    prefix = "#{resource.class}-#{resource.id}"
    document = if resource.is_a?(::Repository)
      # For repositories, we only reference itself since we can't target other repositories
      "- \"/#{prefix}/repo\""
    else
      # For businesses and organizations, we target every possible repository even if we don't have access
      [
        "\"*\": [\"/#{prefix}/scope/wildcard\"]",
        "#{@external_repo_url}: [\"/#{prefix}/scope/external\"]",
        @all_repos.map { |repo| "#{repo.ssh_url_for_api}: [\"/#{prefix}/scope/repo-url\"]" },
        @all_repos.map { |repo| "#{repo.nwo}: [\"/#{prefix}/scope/repo-nwo\"]" },
        @all_repos.map { |repo| "#{repo.name}: [\"/#{prefix}/scope/repo-name\"]" },
      ].join("\n")
    end

    create(
      :copilot_content_exclusion_configuration,
      resource.class.to_s.downcase.to_sym,
      resource: resource,
      document: document
    )
  end

  # Verifies that the rules returned for a user and repository are correct
  # We check both the valid and invalid entities to ensure that the rules are correct
  def verify_rules_for_entities(user:, repo_url:, valid_entities:)
    copilot_user = Copilot::User.new(user)
    business_ids = copilot_user.content_exclusion_enabled_businesses.map(&:id)
    organization_ids = copilot_user.copilot_organizations.map(&:id)

    rules = Copilot::ContentExclusion
      .rules_for_repo_urls([repo_url], organization_ids:, business_ids:)
      .map { |rules| rules.map { |_config, rules| rules.collect(&:patterns) }.flatten.uniq }
      .flatten

    invalid_entities = @all_entities - valid_entities

    # All valid entities rules pertaining to the repo URI should be present
    valid_entities.each do |entity|
      if entity.is_a?(::Repository)
        # Repos only have repo rules
        run_test(assert_includes: true, rules:, entity:, type: "repo", repo_url:)
      else
        # Businesses and orgs have scoped rules
        run_test(assert_includes: true, rules:, entity:, type: "scope/wildcard", repo_url:)

        is_external = repo_url == @external_repo_url

        run_test(assert_includes: is_external, rules:, entity:, type: "scope/external", repo_url:)
        run_test(assert_includes: !is_external, rules:, entity:, type: "scope/repo-url", repo_url:)
        run_test(assert_includes: !is_external, rules:, entity:, type: "scope/repo-nwo", repo_url:)

        # Repo name scoped rules only get applied when the repo exists within the org, as the org-name
        # is prefixed automatically to the scope. Example:
        # Org `monalisa` has a repo `smile`. The scope `smile` will be treated as `monalisa/smile`
        # If org `blah` uses the scope `smile`, it will be treated as `blah/smile` and will not match
        should_match = entity.is_a?(::Organization) && entity.repositories.map(&:ssh_url_for_api).include?(repo_url)
        run_test(assert_includes: should_match, rules:, entity:, type: "scope/repo-name", repo_url:)
      end
    end

    # All invalid entities rules pertaining to the repo URI should not be present
    invalid_entities.each do |entity|
      # Repos only have repo rules
      if entity.is_a?(::Repository)
        run_test(assert_includes: false, rules:, entity:, type: "repo", repo_url:)
      else
        # Businesses and orgs have scoped rules
        run_test(assert_includes: false, rules:, entity:, type: "scope/wildcard", repo_url:)
        run_test(assert_includes: false, rules:, entity:, type: "scope/ssh-url", repo_url:)
        run_test(assert_includes: false, rules:, entity:, type: "scope/nwo-path", repo_url:)
        run_test(assert_includes: false, rules:, entity:, type: "scope/repo-name", repo_url:)
        run_test(assert_includes: false, rules:, entity:, type: "scope/external", repo_url:)
      end
    end
  end

  def run_test(assert_includes:, rules:, entity:, type:, repo_url:)
    error_message = "#{assert_includes ? "Expected" : "Didn't expect"} '#{type}' rule for #{entity.class}##{entity.id} using URL '#{repo_url}'"

    if assert_includes
      assert_includes rules, "/#{entity.class}-#{entity.id}/#{type}", error_message
    else
      refute_includes rules, "/#{entity.class}-#{entity.id}/#{type}", error_message
    end
  end
end

class CopilotContentExclusionOldFlow < CopilotContentExclusionBase
  context "is_available?" do
    context "should return true" do
      test "for repositories of an organization with copilot enabled" do
        assert @org_seated.repositories.any?
        @org_seated.repositories.each { |repo| assert Copilot::ContentExclusion.is_available?(repo) }
      end

      test "for an organization with copilot enabled" do
        assert Copilot::ContentExclusion.is_available?(@org_seated)
      end

      test "for a non-enterprise organization with copilot enabled" do
        assert Copilot::ContentExclusion.is_available?(@org_non_ent_seated)
      end

      test "for a copilot standalone business" do
        assert Copilot::ContentExclusion.is_available?(@business_standalone_seated)
      end
    end

    context "should return false" do
      test "for a repository not part of any organization" do
        refute Copilot::ContentExclusion.is_available?(create(:repository, :user_owned_public))
      end

      test "for a repository with a nil owner" do
        assert Copilot::ContentExclusion.is_available?(@repo_public_org_seated) # precondition
        @repo_public_org_seated.owner = nil

        refute Copilot::ContentExclusion.is_available?(@repo_public_org_seated)
      end

      test "for repositories of an organization with copilot disabled" do
        assert @org_seated.repositories.any?
        Copilot::Business.new(@org_seated.business).disable_copilot!
        @org_seated.repositories.each { |repo| refute Copilot::ContentExclusion.is_available?(repo) }
      end

      test "for an organization with copilot disabled" do
        Copilot::Business.new(@org_seated.business).disable_copilot!
        refute Copilot::ContentExclusion.is_available?(@org_seated)
      end

      test "for a non-enterprise organization with copilot disabled" do
        Copilot::Organization.new(@org_non_ent_seated).disable_copilot!
        refute Copilot::ContentExclusion.is_available?(@org_non_ent_seated)
      end

      test "for a non-standalone enterprise" do
        refute Copilot::ContentExclusion.is_available?(@business_parent)
      end
    end
  end

  context "#rules_for_repo_urls" do
    context "a copilot business user" do
      context "within an enterprise org" do
        test "where the user has a seat" do
          default_entities = [@org_seated, @org_neighbor, @org_non_ent_seated]

          verify_rules_for_entities(user: @user, repo_url: @repo_public_org_seated.ssh_url_for_api, valid_entities: default_entities + [@repo_public_org_seated])
          verify_rules_for_entities(user: @user, repo_url: @repo_private_org_seated.ssh_url_for_api, valid_entities: default_entities + [@repo_private_org_seated])
          verify_rules_for_entities(user: @user, repo_url: @repo_internal_org_seated.ssh_url_for_api, valid_entities: default_entities + [@repo_internal_org_seated])
        end

        test "where the user doesn't get a seat but is a member of the same enterprise" do
          default_entities = [@org_seated, @org_neighbor, @org_non_ent_seated]

          verify_rules_for_entities(user: @user, repo_url: @repo_public_org_neighbor.ssh_url_for_api, valid_entities: default_entities + [@repo_public_org_neighbor])
          verify_rules_for_entities(user: @user, repo_url: @repo_internal_org_neighbor.ssh_url_for_api, valid_entities: default_entities + [@repo_internal_org_neighbor])
          # We should not get repo-specific rules for the repos the user does not have access to
          verify_rules_for_entities(user: @user, repo_url: @repo_private_org_neighbor.ssh_url_for_api, valid_entities: default_entities + [@repo_private_org_neighbor])
        end

        test "where the user doesn't get a seat" do
          default_entities = [@org_seated, @org_neighbor, @org_non_ent_seated]

          verify_rules_for_entities(user: @user, repo_url: @repo_public_org_foreign.ssh_url_for_api, valid_entities: default_entities)
          verify_rules_for_entities(user: @user, repo_url: @repo_private_org_foreign.ssh_url_for_api, valid_entities: default_entities)
          verify_rules_for_entities(user: @user, repo_url: @repo_internal_org_foreign.ssh_url_for_api, valid_entities: default_entities)
        end
      end

      context "within a non-enterprise org" do
        test "where the user has a seat" do
          default_entities = [@org_seated, @org_neighbor, @org_non_ent_seated]

          verify_rules_for_entities(user: @user, repo_url: @repo_public_org_non_ent_seated.ssh_url_for_api, valid_entities: default_entities + [@repo_public_org_non_ent_seated])
          verify_rules_for_entities(user: @user, repo_url: @repo_private_org_non_ent_seated.ssh_url_for_api, valid_entities: default_entities + [@repo_private_org_non_ent_seated])
        end

        test "where the user doesn't have get a seat" do
          default_entities = [@org_seated, @org_neighbor, @org_non_ent_seated]

          verify_rules_for_entities(user: @user, repo_url: @repo_public_org_non_ent_unseated.ssh_url_for_api, valid_entities: default_entities)
          verify_rules_for_entities(user: @user, repo_url: @repo_private_org_non_ent_unseated.ssh_url_for_api, valid_entities: default_entities)
        end
      end

      test "with external repositories" do
        default_entities = [@org_seated, @org_neighbor, @org_non_ent_seated]

        verify_rules_for_entities(user: @user, repo_url: @external_repo_url, valid_entities: default_entities)
      end
    end

    context "a copilot standalone business user" do
      test "should only ever return rules for the standalone business" do
        valid_entities = [@business_standalone_seated]

        verify_rules_for_entities(user: @standalone_user, repo_url: @repo_public_org_seated.ssh_url_for_api, valid_entities:)
        verify_rules_for_entities(user: @standalone_user, repo_url: @repo_private_org_seated.ssh_url_for_api, valid_entities:)
        verify_rules_for_entities(user: @standalone_user, repo_url: @repo_internal_org_seated.ssh_url_for_api, valid_entities:)
        verify_rules_for_entities(user: @standalone_user, repo_url: @repo_public_org_neighbor.ssh_url_for_api, valid_entities:)
        verify_rules_for_entities(user: @standalone_user, repo_url: @repo_internal_org_neighbor.ssh_url_for_api, valid_entities:)
        verify_rules_for_entities(user: @standalone_user, repo_url: @repo_private_org_neighbor.ssh_url_for_api, valid_entities:)
        verify_rules_for_entities(user: @standalone_user, repo_url: @repo_public_org_foreign.ssh_url_for_api, valid_entities:)
        verify_rules_for_entities(user: @standalone_user, repo_url: @repo_private_org_foreign.ssh_url_for_api, valid_entities:)
        verify_rules_for_entities(user: @standalone_user, repo_url: @repo_internal_org_foreign.ssh_url_for_api, valid_entities:)
        verify_rules_for_entities(user: @standalone_user, repo_url: @repo_public_org_non_ent_seated.ssh_url_for_api, valid_entities:)
        verify_rules_for_entities(user: @standalone_user, repo_url: @repo_private_org_non_ent_seated.ssh_url_for_api, valid_entities:)
        verify_rules_for_entities(user: @standalone_user, repo_url: @repo_public_org_non_ent_unseated.ssh_url_for_api, valid_entities:)
        verify_rules_for_entities(user: @standalone_user, repo_url: @repo_private_org_non_ent_unseated.ssh_url_for_api, valid_entities:)
        verify_rules_for_entities(user: @standalone_user, repo_url: @external_repo_url, valid_entities:)
      end
    end
  end

  context "#rules_for_all_files_scope"  do
    context "a copilot business user" do
      test "should only return all seated org wildcard rules" do
        copilot_user = Copilot::User.new(@user)
        business_ids = copilot_user.content_exclusion_enabled_businesses.map(&:id)
        organization_ids = copilot_user.copilot_organizations.map(&:id)

        rules = Copilot::ContentExclusion
          .rules_for_all_files_scope(organization_ids:, business_ids:)
          .map { |_config, rules| rules.collect(&:patterns) }
          .flatten.uniq

        valid_entities = [@org_seated, @org_neighbor, @org_non_ent_seated]

        @all_entities.each do |entity|
          run_test(assert_includes: valid_entities.include?(entity), rules:, entity:, type: "scope/wildcard", repo_url: "")
        end
      end
    end

    context "a copilot standalone business user" do
      test "should only return all seated standalone business wildcard rules" do
        copilot_user = Copilot::User.new(@standalone_user)
        business_ids = copilot_user.content_exclusion_enabled_businesses.map(&:id)
        organization_ids = copilot_user.copilot_organizations.map(&:id)

        rules = Copilot::ContentExclusion
          .rules_for_all_files_scope(organization_ids:, business_ids:)
          .map { |_config, rules| rules.collect(&:patterns) }
          .flatten.uniq

        assert_equal 1, rules.count
        assert_equal "/Business-#{@business_standalone_seated.id}/scope/wildcard", rules.first
      end
    end
  end

  context "#all_relevant_configurations"  do
    test "should return empty when no organizations or businesses are passed" do
      res = Copilot::ContentExclusion.all_relevant_configurations(organization_ids: [], business_ids: [])

      assert_empty res
    end

    test "user gets all relevant org and repo-level configs" do
      copilot_user = Copilot::User.new(@user)
      business_ids = copilot_user.content_exclusion_enabled_businesses.map(&:id)
      organization_ids = copilot_user.copilot_organizations.map(&:id)

      res = Copilot::ContentExclusion.all_relevant_configurations(organization_ids:, business_ids:)

      res_business_ids = res.select { |r| r.resource_type == "Business" }.map(&:resource_id)
      res_organization_ids = res.select { |r| r.resource_type == "Organization" }.map(&:resource_id)
      res_repo_ids = res.select { |r| r.resource_type == "Repository" }.map(&:resource_id)

      assert_equal res.size, res_business_ids.size + res_organization_ids.size + res_repo_ids.size, "Expected all configurations to be returned"

      assert res_business_ids.empty?, "Expected no business-level configurations to be returned"

      assert res_organization_ids.include?(@org_seated.id), "org_seated should be included"
      assert res_organization_ids.include?(@org_neighbor.id), "org_neighbor should be included"
      assert res_organization_ids.exclude?(@org_foreign.id), "org_foreign should be excluded"
      assert res_organization_ids.include?(@org_non_ent_seated.id), "org_non_ent_seated should be included"
      assert res_organization_ids.exclude?(@org_non_ent_unseated.id), "org_non_ent_unseated should be excluded"

      assert res_repo_ids.include?(@repo_public_org_seated.id), "repo_public_org_seated should be included"
      assert res_repo_ids.include?(@repo_private_org_seated.id), "repo_private_org_seated should be included"
      assert res_repo_ids.include?(@repo_internal_org_seated.id), "repo_internal_org_seated should be included"
      assert res_repo_ids.include?(@repo_public_org_neighbor.id), "repo_public_org_neighbor should be included"
      assert res_repo_ids.include?(@repo_private_org_neighbor.id), "repo_private_org_neighbor should be included"
      assert res_repo_ids.include?(@repo_internal_org_neighbor.id), "repo_internal_org_neighbor should be included"
      assert res_repo_ids.exclude?(@repo_public_org_foreign.id), "repo_public_org_foreign should be excluded"
      assert res_repo_ids.exclude?(@repo_private_org_foreign.id), "repo_private_org_foreign should be excluded"
      assert res_repo_ids.exclude?(@repo_internal_org_foreign.id), "repo_internal_org_foreign should be excluded"
      assert res_repo_ids.include?(@repo_public_org_non_ent_seated.id), "repo_public_org_non_ent_seated should be included"
      assert res_repo_ids.include?(@repo_private_org_non_ent_seated.id), "repo_private_org_non_ent_seated should be included"
      assert res_repo_ids.exclude?(@repo_public_org_non_ent_unseated.id), "repo_public_org_non_ent_unseated should be excluded"
      assert res_repo_ids.exclude?(@repo_private_org_non_ent_unseated.id), "repo_private_org_non_ent_unseated should be excluded"
    end

    test "user still gets neighbor org configs when no direct configs exist" do
      user = create(:user)
      org_with_no_config = create(:copilot_for_business_enabled_organization, business: @business_parent)
      org_with_no_config.add_member(user, action: :admin)
      Copilot::Organization.new(org_with_no_config).seat_management_allow_all!

      copilot_user = Copilot::User.new(user)
      business_ids = copilot_user.content_exclusion_enabled_businesses.map(&:id)
      organization_ids = copilot_user.copilot_organizations.map(&:id)

      res = Copilot::ContentExclusion.all_relevant_configurations(organization_ids:, business_ids:)

      res_business_ids = res.select { |r| r.resource_type == "Business" }.map(&:resource_id)
      res_organization_ids = res.select { |r| r.resource_type == "Organization" }.map(&:resource_id)

      assert res_business_ids.empty?, "Expected no business-level configurations to be returned"
      assert res_organization_ids.include?(@org_seated.id), "org_seated should be included"
      assert res_organization_ids.include?(@org_neighbor.id), "org_neighbor should be included"
      assert res_organization_ids.exclude?(org_with_no_config.id), "org_with_no_config should be excluded"
    end

    test "should return empty when the document is empty" do
      user = create(:user)
      org_with_no_config = create(:copilot_for_business_enabled_organization)
      org_with_no_config.add_member(user, action: :admin)
      Copilot::Organization.new(org_with_no_config).seat_management_allow_all!

      create(:copilot_content_exclusion_configuration, :organization, resource: org_with_no_config, document: "")

      copilot_user = Copilot::User.new(user)
      business_ids = copilot_user.content_exclusion_enabled_businesses.map(&:id)
      organization_ids = copilot_user.copilot_organizations.map(&:id)

      assert_empty Copilot::ContentExclusion.all_relevant_configurations(organization_ids:, business_ids:)
    end

    test "standalone user gets only business config" do
      copilot_user = Copilot::User.new(@standalone_user)
      business_ids = copilot_user.content_exclusion_enabled_businesses.map(&:id)
      organization_ids = copilot_user.copilot_organizations.map(&:id)

      res = Copilot::ContentExclusion.all_relevant_configurations(organization_ids:, business_ids:)

      assert_equal 1, res.size, "Expected only business config to be returned"

      assert_equal res.first&.resource_id, @business_standalone_seated.id, "business_standalone_seated should be included"
    end
  end
end if GitHub.copilot_enabled?
