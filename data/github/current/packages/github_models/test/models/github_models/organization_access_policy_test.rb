# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::OrganizationAccessPolicyTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  fixtures do
    @org_admin = create(:user)
    @org = create(:organization, admin: @org_admin)
    @catalog_item, @catalog_item2 = create_pair(:github_models_catalog_item)
    @org.enable_models_access(@org_admin, instrument: false)
  end

  setup do
    enable_feature_flag(:github_models_read_access_for_orgs)
  end

  context "#allowed_models" do
    if GitHub.models_enabled?
      test "returns an empty list when org has only a global block rule" do
        create(:github_models_organization_access_rule, :block, organization: @org)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        assert_empty policy.allowed_models
      end

      test "returns an empty list when Models is turned off for the org" do
        assert @org.disable_models_access(@org_admin, instrument: false)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        assert_empty policy.allowed_models
      end

      test "handles when org has a global block rule and allows specific publishers" do
        publisher1, publisher2 = create_list(:github_models_publisher, 3)
        @catalog_item.update!(github_models_publisher_id: publisher1.id)
        @catalog_item2.update!(github_models_publisher_id: publisher2.id)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        create(:github_models_organization_access_rule, :block, organization: @org)
        create(:github_models_organization_access_rule, :allow, organization: @org, publisher: publisher1)

        result = policy.allowed_models

        allowed_model_keys = result.map(&:key)
        assert_includes allowed_model_keys, @catalog_item.key, "should have included model whose publisher is allowed"
        refute_includes allowed_model_keys, @catalog_item2.key, "should have omitted model due to global block rule"
        assert_equal 1, result.size
        assert_empty result.reject { |ci| policy.model_allowed?(ci) },
          "all returned models should get a truthy #model_allowed? result"
      end

      test "handles when org has a global block rule and allows specific models" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        create(:github_models_organization_access_rule, :block, organization: @org)
        create(:github_models_organization_access_rule, :allow, organization: @org, catalog_item: @catalog_item)

        result = policy.allowed_models

        allowed_model_keys = result.map(&:key)
        assert_includes allowed_model_keys, @catalog_item.key, "should have included model that is allowed"
        refute_includes allowed_model_keys, @catalog_item2.key, "should have omitted model due to global block rule"
        assert_equal 1, result.size
        assert_empty result.reject { |ci| policy.model_allowed?(ci) },
          "all returned models should get a truthy #model_allowed? result"
      end

      test "handles when org has a global block rule and a mixture of targeted allow and block rules" do
        blocked_publisher, allowed_publisher, random_publisher = create_list(:github_models_publisher, 3)
        @catalog_item.update!(github_models_publisher_id: blocked_publisher.id)
        allowed_catalog_item = create(:github_models_catalog_item, github_models_publisher_id: blocked_publisher.id)
        @catalog_item2.update!(github_models_publisher_id: allowed_publisher.id)
        random_catalog_item = create(:github_models_catalog_item, github_models_publisher_id: random_publisher.id)
        blocked_catalog_item = create(:github_models_catalog_item, github_models_publisher_id: allowed_publisher.id)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        create(:github_models_organization_access_rule, :block, organization: @org)
        create(:github_models_organization_access_rule, :block, organization: @org, publisher: blocked_publisher)
        create(:github_models_organization_access_rule, :allow, organization: @org,
          catalog_item: allowed_catalog_item)
        create(:github_models_organization_access_rule, :allow, organization: @org, publisher: allowed_publisher)
        create(:github_models_organization_access_rule, :block, organization: @org,
          catalog_item: blocked_catalog_item)

        result = assert_query_count_per_table({
          azure_models_catalog_items: 1,
          models_organization_access_rules: 1,
        }) do
          policy.allowed_models
        end

        allowed_model_keys = result.map(&:key)
        refute_includes allowed_model_keys, @catalog_item.key,
          "should have omitted model whose publisher was blocked"
        assert_includes allowed_model_keys, allowed_catalog_item.key,
          "should have included explicitly allowed model whose publisher was blocked"
        assert_includes allowed_model_keys, @catalog_item2.key,
          "should have included model whose publisher was allowed"
        refute_includes allowed_model_keys, random_catalog_item.key,
          "should have omitted model without any relevant targeted rules due to global block rule"
        refute_includes allowed_model_keys, blocked_catalog_item.key,
          "should have omitted explicitly blocked model whose publisher was allowed"
        assert_equal 2, result.size
        assert_empty result.reject { |ci| policy.model_allowed?(ci) },
          "all returned models should get a truthy #model_allowed? result"
      end
    end

    unless GitHub.models_enabled?
      test "returns an empty list" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        assert_empty policy.allowed_models
      end
    end
  end

  context "#use_allowlist" do
    if GitHub.models_enabled?
      test "no-op if the org already has a global block rule" do
        create(:github_models_organization_access_rule, :block, organization: @org)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
          assert policy.use_allowlist(actor: @org_admin)
        end

        assert policy.to_h[:isAllowlist]
      end

      test "creates a global block rule for an org without any existing rules" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_difference("GitHubModels::OrganizationAccessRule.count") do
          assert policy.use_allowlist(actor: @org_admin)
        end

        assert policy.to_h[:isAllowlist]
        assert_equal 1, @org.github_models_access_rules.count
      end

      test "creates a global block rule for the org without modifying existing targeted block or allow rules" do
        targeted_allow_rule = create(:github_models_organization_access_rule, :allow, :model_specific,
          organization: @org)
        targeted_block_rule = create(:github_models_organization_access_rule, :block, :publisher_specific,
          organization: @org)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_difference("GitHubModels::OrganizationAccessRule.count") do
          assert policy.use_allowlist(actor: @org_admin)
        end

        assert policy.to_h[:isAllowlist]
        assert_predicate targeted_allow_rule.reload, :allow?
        assert_equal @org, targeted_allow_rule.organization
        assert_equal "model", targeted_allow_rule.target_label
        refute_predicate targeted_block_rule.reload, :allow?
        assert_equal @org, targeted_block_rule.organization
        assert_equal "publisher", targeted_block_rule.target_label
      end

      test "returns false when global block rule cannot be saved" do
        GitHubModels::OrganizationAccessRule.any_instance.stubs(:save).returns(false)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        refute policy.use_allowlist(actor: @org_admin)
      end
    end

    unless GitHub.models_enabled?
      test "no-op when Models as a feature is not enabled" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
          assert policy.use_allowlist(actor: @org_admin)
        end

        refute policy.to_h[:isModelsEnabled]
      end
    end
  end

  context "#async_is_programmatic_actor_with_write_access?" do
    test "returns true when PAT v2 has Organizations/organization_models read permission" do
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
      patv2 = make_user_programmatic_access_with_grant(
        target: @org,
        requester: @org_admin,
        permissions: { "organization_models" => :read }
      )

      assert policy.async_is_programmatic_actor_with_write_access?(patv2).sync
    end

    test "returns false when PAT v2 does not have Organizations/organization_models read permission" do
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
      patv2 = make_user_programmatic_access_with_grant(
        target: @org,
        requester: @org_admin,
        permissions: { "issues" => :read }
      )

      refute policy.async_is_programmatic_actor_with_write_access?(patv2).sync
    end

    test "returns true when GitHub App token has Organizations/organization_models read permission" do
      fgp_installation_read = make_integration_installation(
        target: @org,
        permissions: { "organization_models" => :read }
      )
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert policy.async_is_programmatic_actor_with_write_access?(fgp_installation_read).sync
    end

    test "returns false when GitHub App token does not have Organizations/organization_models read permission" do
      fgp_installation_read = make_integration_installation(
        target: @org,
        permissions: { "issues" => :read }
      )
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      refute policy.async_is_programmatic_actor_with_write_access?(fgp_installation_read).sync
    end

    test "returns false when broad grained PAT v1 is passed in" do
      patv1 = make_personal_access_token(@org_admin, %w[repo])
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      refute policy.async_is_programmatic_actor_with_write_access?(patv1).sync
    end

    test "returns false with oauth app token is passed in" do
      oauth_app = make_oauth_app(@org)
      oauth_member_access = make_oauth(@org_admin, %w[repo], oauth_app)

      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      refute policy.async_is_programmatic_actor_with_write_access?(oauth_app).sync
    end
  end

  context "#use_blocklist" do
    if GitHub.models_enabled?
      test "no-op if the org does not have a global block rule" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
          assert policy.use_blocklist(actor: @org_admin)
        end

        refute policy.to_h[:isAllowlist]
      end

      test "deletes the org's global block rule if it exists" do
        global_block_rule = create(:github_models_organization_access_rule, :block, organization: @org)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_difference("GitHubModels::OrganizationAccessRule.count", -1) do
          assert policy.use_blocklist(actor: @org_admin)
        end

        refute policy.to_h[:isAllowlist]
        refute GitHubModels::OrganizationAccessRule.exists?(global_block_rule.id)
      end

      test "returns false when global block rule exists but cannot be deleted" do
        create(:github_models_organization_access_rule, :block, organization: @org)
        GitHubModels::OrganizationAccessRule.any_instance.stubs(:destroy).returns(false)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        refute policy.use_blocklist(actor: @org_admin)
      end
    end

    unless GitHub.models_enabled?
      test "no-op when Models as a feature is not enabled" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
          refute policy.use_blocklist(actor: @org_admin)
        end

        refute policy.to_h[:isModelsEnabled]
      end
    end
  end

  context "#model_allowed?" do
    if GitHub.models_enabled?
      test "returns true when org has no rules" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        assert_query_count_per_table({ azure_models_catalog_items: 0, models_organization_access_rules: 1 }) do
          assert policy.model_allowed?(@catalog_item)
        end
      end

      test "returns false when the Models config setting is disabled for the org" do
        assert @org.disable_models_access(@org_admin, instrument: false)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        refute policy.model_allowed?(@catalog_item)
      end

      test "returns true when org has an allow rule for the given model's publisher" do
        rule = create(:github_models_organization_access_rule, :publisher_specific, :allow, organization: @org)
        @catalog_item2.update!(github_models_publisher_id: rule.models_publisher_id)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_query_count_per_table({ azure_models_catalog_items: 0, models_organization_access_rules: 1 }) do
          assert policy.model_allowed?(@catalog_item2)
        end
      end

      test "returns true when org has an allow rule for the given model" do
        create(:github_models_organization_access_rule, :allow, organization: @org, catalog_item: @catalog_item)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_query_count_per_table({ azure_models_catalog_items: 0, models_organization_access_rules: 1 }) do
          assert policy.model_allowed?(@catalog_item)
        end
      end

      test "returns false when org has a global block rule and no model- or publisher-specific allow rule" do
        publisher = create(:github_models_publisher)
        @catalog_item.update!(github_models_publisher_id: publisher.id)
        create(:github_models_organization_access_rule, :block, organization: @org)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_query_count_per_table({ azure_models_catalog_items: 0, models_organization_access_rules: 1 }) do
          refute policy.model_allowed?(@catalog_item)
        end
      end

      test "returns false when org has a block rule for the given model's publisher" do
        rule = create(:github_models_organization_access_rule, :publisher_specific, :block, organization: @org)
        @catalog_item2.update!(github_models_publisher_id: rule.models_publisher_id)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_query_count_per_table({ azure_models_catalog_items: 0, models_organization_access_rules: 1 }) do
          refute policy.model_allowed?(@catalog_item2)
        end
      end

      test "returns true when org has a block rule for a publisher other than the given model's publisher" do
        publisher1, publisher2 = create_pair(:github_models_publisher)
        create(:github_models_organization_access_rule, :block, organization: @org, publisher: publisher1)
        @catalog_item2.update!(github_models_publisher_id: publisher2.id)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert policy.model_allowed?(@catalog_item2)
      end

      test "returns false when org has a block rule for the given model" do
        create(:github_models_organization_access_rule, :block, organization: @org, catalog_item: @catalog_item)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_query_count_per_table({ azure_models_catalog_items: 0, models_organization_access_rules: 1 }) do
          refute policy.model_allowed?(@catalog_item)
        end
      end

      test "returns true when org has a block rule for a model other than the given one" do
        create(:github_models_organization_access_rule, :block, organization: @org, catalog_item: @catalog_item)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_query_count_per_table({ azure_models_catalog_items: 0, models_organization_access_rules: 1 }) do
          assert policy.model_allowed?(@catalog_item2)
        end
      end

      test "returns false when org has an allow rule for the given model's publisher but blocks that specific model" do
        rule = create(:github_models_organization_access_rule, :publisher_specific, :allow, organization: @org)
        @catalog_item2.update!(github_models_publisher_id: rule.models_publisher_id)
        create(:github_models_organization_access_rule, :block, organization: @org,
          publisher: rule.publisher, catalog_item: @catalog_item2)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_query_count_per_table({ azure_models_catalog_items: 0, models_organization_access_rules: 1 }) do
          refute policy.model_allowed?(@catalog_item2)
        end
      end

      test "returns true when org has a block rule for the given model's publisher but allows that specific model" do
        rule = create(:github_models_organization_access_rule, :publisher_specific, :block, organization: @org)
        @catalog_item2.update!(github_models_publisher_id: rule.models_publisher_id)
        create(:github_models_organization_access_rule, :allow, organization: @org,
          publisher: rule.publisher, catalog_item: @catalog_item2)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_query_count_per_table({ azure_models_catalog_items: 0, models_organization_access_rules: 1 }) do
          assert policy.model_allowed?(@catalog_item2)
        end
      end
    end

    unless GitHub.models_enabled?
      test "returns false when Models is disabled as a feature" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_query_count(0) do
          refute policy.model_allowed?(@catalog_item)
        end
      end
    end
  end

  context "#block_models" do
    if GitHub.models_enabled?
      test "blocks many models at a time" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        catalog_item3 = create(:github_models_catalog_item)

        assert_difference("GitHubModels::OrganizationAccessRule.count", 3) do
          # 1 SELECT to load all the org's rules initially
          #   + 3 SELECTs to validate each rule's uniqueness on save
          #   + 3 INSERTs
          assert_query_count_per_table({ "models_organization_access_rules" => 7 }) do
            assert_equal 3, policy.block_models([@catalog_item, @catalog_item2, catalog_item3], actor: @org_admin)
          end
        end

        assert_query_count_per_table({
          "azure_models_catalog_items" => 0,
          "business_organization_memberships" => 1,
          "configuration_entries" => 1,
          "models_organization_access_rules" => 0,
          "models_publishers" => 0,
        }) do
          refute policy.model_allowed?(@catalog_item)
          refute policy.model_allowed?(@catalog_item2)
          refute policy.model_allowed?(catalog_item3)
        end
      end

      test "handles when some models are already blocked" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        create(:github_models_organization_access_rule, :block, organization: @org, catalog_item: @catalog_item)

        assert_difference("GitHubModels::OrganizationAccessRule.count") do
          # 1 SELECT to load all the org's rules initially
          #   + 1 SELECT to validate the new rule's uniqueness on save
          #   + 1 INSERT
          assert_query_count_per_table({ "models_organization_access_rules" => 3 }) do
            assert_equal 2, policy.block_models([@catalog_item, @catalog_item2], actor: @org_admin)
          end
        end

        assert_query_count_per_table({
          "azure_models_catalog_items" => 0,
          "business_organization_memberships" => 1,
          "configuration_entries" => 1,
          "models_organization_access_rules" => 0,
          "models_publishers" => 0,
        }) do
          refute policy.model_allowed?(@catalog_item)
          refute policy.model_allowed?(@catalog_item2)
        end
      end
    end
  end

  context "#block_model" do
    test "updates existing allow rule for that model if the org has one and there's no global block rule" do
      rule = create(:github_models_organization_access_rule, :allow, organization: @org, catalog_item: @catalog_item)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.block_model(@catalog_item, actor: @org_admin)
      end

      refute policy.model_allowed?(@catalog_item)
      refute_predicate rule.reload, :allow?
    end

    test "deletes existing allow rule for that model if the org has one and there's a global block rule" do
      create(:github_models_organization_access_rule, :block, organization: @org)
      allow_rule = create(:github_models_organization_access_rule, :allow, organization: @org, catalog_item: @catalog_item)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_difference("GitHubModels::OrganizationAccessRule.count", -1) do
        assert policy.block_model(@catalog_item, actor: @org_admin)
      end

      refute policy.model_allowed?(@catalog_item)
      refute GitHubModels::OrganizationAccessRule.exists?(allow_rule.id)
    end

    test "creates a new blocking rule for specified model when org doesn't already have a rule for that model and there's no global block rule" do
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.block_model(@catalog_item, actor: @org_admin)
      end

      refute policy.model_allowed?(@catalog_item)
      new_rule = GitHubModels::OrganizationAccessRule.for_org(@org).blocked.last
      refute_nil new_rule
      assert_equal @catalog_item, new_rule&.target
    end

    test "creates a new blocking rule for specified model when org doesn't already have a rule for that model and there is an allow rule for its publisher" do
      publisher_rule = create(:github_models_organization_access_rule, :allow, :publisher_specific,
        organization: @org)
      @catalog_item.update!(github_models_publisher_id: publisher_rule.models_publisher_id)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.block_model(@catalog_item, actor: @org_admin)
      end

      if GitHub.models_enabled?
        refute policy.model_allowed?(@catalog_item)
      end
      new_rule = GitHubModels::OrganizationAccessRule.for_org(@org).blocked.last
      refute_nil new_rule
      assert_equal @catalog_item, new_rule&.target
    end

    test "no-op when org already has a blocking rule targeting that specific model" do
      rule = create(:github_models_organization_access_rule, :block, organization: @org, catalog_item: @catalog_item)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.block_model(@catalog_item, actor: @org_admin)
      end

      refute policy.model_allowed?(@catalog_item)
      refute_predicate rule.reload, :allow?
      assert_equal @catalog_item, rule.catalog_item
      assert_equal @org, rule.organization
    end

    test "no-op when org already has a blocking rule for the model's publisher" do
      publisher = create(:github_models_publisher)
      publisher_rule = create(:github_models_organization_access_rule, :block, organization: @org,
        publisher: publisher)
      @catalog_item.update!(github_models_publisher_id: publisher.id)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.block_model(@catalog_item, actor: @org_admin)
      end

      refute policy.model_allowed?(@catalog_item)
      refute_predicate publisher_rule.reload, :allow?
      assert_equal publisher, publisher_rule.target
      assert_equal @org, publisher_rule.organization
    end

    test "no-op when org already has a global block rule and no allow rule for that specific model" do
      create(:github_models_organization_access_rule, :block, organization: @org)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.block_model(@catalog_item, actor: @org_admin)
      end

      refute policy.model_allowed?(@catalog_item)
    end
  end

  context "#block_publishers" do
    if GitHub.models_enabled?
      test "blocks many publishers at a time" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        publisher1, publisher2 = create_pair(:github_models_publisher)
        @catalog_item.update!(github_models_publisher_id: publisher1.id)
        @catalog_item2.update!(github_models_publisher_id: publisher2.id)

        assert_difference("GitHubModels::OrganizationAccessRule.count", 2) do
          # 1 SELECT to load all the org's rules initially
          #   + 2 SELECTs to validate each rule's uniqueness on save
          #   + 2 INSERTs
          assert_query_count_per_table({ "models_organization_access_rules" => 5 }) do
            assert_equal 2, policy.block_publishers([publisher1, publisher2], actor: @org_admin)
          end
        end

        assert_query_count_per_table({
          "azure_models_catalog_items" => 0,
          "business_organization_memberships" => 1,
          "configuration_entries" => 1,
          "models_organization_access_rules" => 0,
          "models_publishers" => 0,
        }) do
          refute policy.model_allowed?(@catalog_item)
          refute policy.model_allowed?(@catalog_item2)
        end
      end

      test "handles when some publishers are already blocked" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        publisher1, publisher2 = create_pair(:github_models_publisher)
        @catalog_item.update!(github_models_publisher_id: publisher1.id)
        @catalog_item2.update!(github_models_publisher_id: publisher2.id)
        create(:github_models_organization_access_rule, :block, organization: @org, publisher: publisher1)

        assert_difference("GitHubModels::OrganizationAccessRule.count") do
          # 1 SELECT to load all the org's rules initially
          #   + 1 SELECT to validate the new rule's uniqueness on save
          #   + 1 INSERT
          assert_query_count_per_table({ "models_organization_access_rules" => 3 }) do
            assert_equal 2, policy.block_publishers([publisher1, publisher2], actor: @org_admin)
          end
        end

        assert_query_count_per_table({
          "azure_models_catalog_items" => 0,
          "business_organization_memberships" => 1,
          "configuration_entries" => 1,
          "models_organization_access_rules" => 0,
          "models_publishers" => 0,
        }) do
          refute policy.model_allowed?(@catalog_item)
          refute policy.model_allowed?(@catalog_item2)
        end
      end
    end
  end

  context "#block_publisher" do
    test "updates existing allow rule for that publisher if the org has one and there's no global block rule" do
      publisher = create(:github_models_publisher)
      rule = create(:github_models_organization_access_rule, :allow, organization: @org, publisher: publisher)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.block_publisher(publisher, actor: @org_admin)
      end

      refute_predicate rule.reload, :allow?
    end

    test "deletes existing allow rule for that publisher if the org has one and there's a global block rule" do
      create(:github_models_organization_access_rule, :block, organization: @org)
      publisher = create(:github_models_publisher)
      allow_rule = create(:github_models_organization_access_rule, :allow, organization: @org, publisher: publisher)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_difference("GitHubModels::OrganizationAccessRule.count", -1) do
        assert policy.block_publisher(publisher, actor: @org_admin)
      end

      refute GitHubModels::OrganizationAccessRule.exists?(allow_rule.id)
    end

    test "creates a new blocking rule for specified publisher when org doesn't already have a rule for that publisher" do
      publisher = create(:github_models_publisher)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.block_publisher(publisher, actor: @org_admin)
      end

      new_rule = GitHubModels::OrganizationAccessRule.for_org(@org).blocked.last
      refute_nil new_rule
      assert_equal publisher, new_rule&.target
    end

    test "no-op when org already has a blocking rule targeting that specific publisher" do
      publisher = create(:github_models_publisher)
      rule = create(:github_models_organization_access_rule, :block, organization: @org, publisher: publisher)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.block_publisher(publisher, actor: @org_admin)
      end

      refute_predicate rule.reload, :allow?
      assert_equal publisher, rule.publisher
      assert_equal @org, rule.organization
    end

    test "no-op when org already has a global block rule and no allow rule for that specific publisher" do
      create(:github_models_organization_access_rule, :block, organization: @org)
      publisher = create(:github_models_publisher)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.block_publisher(publisher, actor: @org_admin)
      end
    end
  end

  context "#allow_models" do
    if GitHub.models_enabled?
      test "allows many models at a time" do
        create(:github_models_organization_access_rule, :block, organization: @org)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        catalog_item3 = create(:github_models_catalog_item)

        assert_difference("GitHubModels::OrganizationAccessRule.count", 3) do
          # 1 SELECT to load all the org's rules initially
          #   + 3 SELECTs to validate each rule's uniqueness on save
          #   + 3 INSERTs
          assert_query_count_per_table({ "models_organization_access_rules" => 7 }) do
            assert_equal 3, policy.allow_models([@catalog_item, @catalog_item2, catalog_item3], actor: @org_admin)
          end
        end

        assert_query_count_per_table({
          "azure_models_catalog_items" => 0,
          "business_organization_memberships" => 1,
          "configuration_entries" => 1,
          "models_organization_access_rules" => 0,
          "models_publishers" => 0,
        }) do
          assert policy.model_allowed?(@catalog_item)
          assert policy.model_allowed?(@catalog_item2)
          assert policy.model_allowed?(catalog_item3)
        end
      end

      test "handles when some models are already allowed" do
        create(:github_models_organization_access_rule, :block, organization: @org)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        create(:github_models_organization_access_rule, :allow, organization: @org, catalog_item: @catalog_item)

        assert_difference("GitHubModels::OrganizationAccessRule.count") do
          # 1 SELECT to load all the org's rules initially
          #   + 1 SELECT to validate the new rule's uniqueness on save
          #   + 1 INSERT
          assert_query_count_per_table({ "models_organization_access_rules" => 3 }) do
            assert_equal 2, policy.allow_models([@catalog_item, @catalog_item2], actor: @org_admin)
          end
        end

        assert_query_count_per_table({
          "azure_models_catalog_items" => 0,
          "business_organization_memberships" => 1,
          "configuration_entries" => 1,
          "models_organization_access_rules" => 0,
          "models_publishers" => 0,
        }) do
          assert policy.model_allowed?(@catalog_item)
          assert policy.model_allowed?(@catalog_item2)
        end
      end
    end
  end

  context "#allow_model" do
    test "updates existing block rule for that model if the org has one and there is a global block rule" do
      create(:github_models_organization_access_rule, :block, organization: @org)
      rule = create(:github_models_organization_access_rule, :block, organization: @org, catalog_item: @catalog_item)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.allow_model(@catalog_item, actor: @org_admin)
      end

      if GitHub.models_enabled?
        assert policy.model_allowed?(@catalog_item)
      end
      assert_predicate rule.reload, :allow?
    end

    test "still creates a rule even if Models config setting is disabled for the org" do
      create(:github_models_organization_access_rule, :block, organization: @org)
      assert @org.disable_models_access(@org_admin, instrument: false)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.allow_model(@catalog_item, actor: @org_admin)
      end

      refute policy.model_allowed?(@catalog_item)
    end

    test "deletes existing block rule for that model if the org has one and there is no global block rule" do
      rule = create(:github_models_organization_access_rule, :block, organization: @org, catalog_item: @catalog_item)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_difference("GitHubModels::OrganizationAccessRule.count", -1) do
        assert policy.allow_model(@catalog_item, actor: @org_admin)
      end

      if GitHub.models_enabled?
        assert policy.model_allowed?(@catalog_item)
      end
      refute GitHubModels::OrganizationAccessRule.exists?(rule.id)
    end

    test "creates a new allowing rule for specified model when org doesn't already have a rule for that model and there is a global block rule" do
      create(:github_models_organization_access_rule, :block, organization: @org)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.allow_model(@catalog_item, actor: @org_admin)
      end

      if GitHub.models_enabled?
        assert policy.model_allowed?(@catalog_item)
      end
      new_rule = GitHubModels::OrganizationAccessRule.for_org(@org).allowed.last
      refute_nil new_rule
      assert_equal @catalog_item, new_rule&.target
    end

    test "creates a new allowing rule for specified model when org doesn't already have a rule for that model and there is a block rule for its publisher" do
      publisher_rule = create(:github_models_organization_access_rule, :block, :publisher_specific,
        organization: @org)
      @catalog_item.update!(github_models_publisher_id: publisher_rule.models_publisher_id)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.allow_model(@catalog_item, actor: @org_admin)
      end

      if GitHub.models_enabled?
        assert policy.model_allowed?(@catalog_item)
      end
      new_rule = GitHubModels::OrganizationAccessRule.for_org(@org).allowed.last
      refute_nil new_rule
      assert_equal @catalog_item, new_rule&.target
    end

    test "no-op when org doesn't already have a rule for that model and there is no global block rule" do
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.allow_model(@catalog_item, actor: @org_admin)
      end
    end

    test "no-op when org already has an allowing rule targeting that model's publisher and no model-specific rule" do
      publisher = create(:github_models_publisher)
      @catalog_item.update!(github_models_publisher_id: publisher.id)
      create(:github_models_organization_access_rule, :block, organization: @org)
      publisher_rule = create(:github_models_organization_access_rule, :allow, organization: @org,
        publisher: publisher)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.allow_model(@catalog_item, actor: @org_admin)
      end

      if GitHub.models_enabled?
        assert policy.model_allowed?(@catalog_item)
      end
      assert_predicate publisher_rule.reload, :allow?
      assert_equal publisher, publisher_rule.target
      assert_equal @org, publisher_rule.organization
    end

    test "no-op when org already has an allowing rule targeting that specific model" do
      rule = create(:github_models_organization_access_rule, :allow, organization: @org, catalog_item: @catalog_item)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.allow_model(@catalog_item, actor: @org_admin)
      end

      if GitHub.models_enabled?
        assert policy.model_allowed?(@catalog_item)
      end
      assert_predicate rule.reload, :allow?
      assert_equal @catalog_item, rule.catalog_item
      assert_equal @org, rule.organization
    end
  end

  context "#allow_publishers" do
    if GitHub.models_enabled?
      test "allows many publishers at a time" do
        create(:github_models_organization_access_rule, :block, organization: @org)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        publisher1, publisher2 = create_pair(:github_models_publisher)
        @catalog_item.update!(github_models_publisher_id: publisher1.id)
        @catalog_item2.update!(github_models_publisher_id: publisher2.id)

        assert_difference("GitHubModels::OrganizationAccessRule.count", 2) do
          # 1 SELECT to load all the org's rules initially
          #   + 2 SELECTs to validate each rule's uniqueness on save
          #   + 2 INSERTs
          assert_query_count_per_table({ "models_organization_access_rules" => 5 }) do
            assert_equal 2, policy.allow_publishers([publisher1, publisher2], actor: @org_admin)
          end
        end

        assert_query_count_per_table({
          "azure_models_catalog_items" => 0,
          "business_organization_memberships" => 1,
          "configuration_entries" => 1,
          "models_organization_access_rules" => 0,
          "models_publishers" => 0,
        }) do
          assert policy.model_allowed?(@catalog_item)
          assert policy.model_allowed?(@catalog_item2)
        end
      end

      test "handles when some publishers are already allowed" do
        create(:github_models_organization_access_rule, :block, organization: @org)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        publisher1, publisher2 = create_pair(:github_models_publisher)
        @catalog_item.update!(github_models_publisher_id: publisher1.id)
        @catalog_item2.update!(github_models_publisher_id: publisher2.id)
        create(:github_models_organization_access_rule, :allow, organization: @org, publisher: publisher1)

        assert_difference("GitHubModels::OrganizationAccessRule.count") do
          # 1 SELECT to load all the org's rules initially
          #   + 1 SELECT to validate the new rule's uniqueness on save
          #   + 1 INSERT
          assert_query_count_per_table({ "models_organization_access_rules" => 3 }) do
            assert_equal 2, policy.allow_publishers([publisher1, publisher2], actor: @org_admin)
          end
        end

        assert_query_count_per_table({
          "azure_models_catalog_items" => 0,
          "business_organization_memberships" => 1,
          "configuration_entries" => 1,
          "models_organization_access_rules" => 0,
          "models_publishers" => 0,
        }) do
          assert policy.model_allowed?(@catalog_item)
          assert policy.model_allowed?(@catalog_item2)
        end
      end
    end
  end

  context "#allow_publisher" do
    test "updates existing block rule for that publisher if the org has one and there is a global block rule" do
      create(:github_models_organization_access_rule, :block, organization: @org)
      publisher = create(:github_models_publisher)
      rule = create(:github_models_organization_access_rule, :block, organization: @org, publisher: publisher)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.allow_publisher(publisher, actor: @org_admin)
      end

      assert_predicate rule.reload, :allow?
    end

    test "still creates a rule even if Models config setting is disabled for the org" do
      create(:github_models_organization_access_rule, :block, organization: @org)
      publisher = create(:github_models_publisher)
      assert @org.disable_models_access(@org_admin, instrument: false)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.allow_publisher(publisher, actor: @org_admin)
      end
    end

    test "deletes existing block rule for that publisher if the org has one and there is no global block rule" do
      publisher = create(:github_models_publisher)
      rule = create(:github_models_organization_access_rule, :block, organization: @org, publisher: publisher)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_difference("GitHubModels::OrganizationAccessRule.count", -1) do
        assert policy.allow_publisher(publisher, actor: @org_admin)
      end

      refute GitHubModels::OrganizationAccessRule.exists?(rule.id)
    end

    test "creates a new allowing rule for specified publisher when org doesn't already have a rule for that publisher and there is a global block rule" do
      create(:github_models_organization_access_rule, :block, organization: @org)
      publisher = create(:github_models_publisher)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.allow_publisher(publisher, actor: @org_admin)
      end

      new_rule = GitHubModels::OrganizationAccessRule.for_org(@org).allowed.last
      refute_nil new_rule
      assert_equal publisher, new_rule&.target
    end

    test "no-op when org already has an allowing rule targeting that specific publisher" do
      publisher = create(:github_models_publisher)
      rule = create(:github_models_organization_access_rule, :allow, organization: @org, publisher: publisher)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.allow_publisher(publisher, actor: @org_admin)
      end

      assert_predicate rule.reload, :allow?
      assert_equal publisher, rule.publisher
      assert_equal @org, rule.organization
    end

    test "no-op when org doesn't already have a rule for that publisher and there is no global block rule" do
      publisher = create(:github_models_publisher)
      policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

      assert_no_difference("GitHubModels::OrganizationAccessRule.count") do
        assert policy.allow_publisher(publisher, actor: @org_admin)
      end
    end
  end

  context "#to_h" do
    if GitHub.models_enabled?
      test "handles when org has no rules" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        assert_equal({
          isAllowlist: false,
          isModelsEnabled: true,
          allowedModelKeys: [@catalog_item.key, @catalog_item2.key].sort,
        }, policy.to_h)
      end

      test "handles when org has allowed a particular model while blocking others" do
        create(:github_models_organization_access_rule, :block, organization: @org)
        create(:github_models_organization_access_rule, :allow, organization: @org, catalog_item: @catalog_item)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        assert_equal({
          isAllowlist: true,
          isModelsEnabled: true,
          allowedModelKeys: [@catalog_item.key],
        }, policy.to_h)
      end

      test "handles when org has a publisher-specific rule" do
        create(:github_models_organization_access_rule, :block, organization: @org)
        publisher_rule = create(:github_models_organization_access_rule, :allow, :publisher_specific,
          organization: @org)
        @catalog_item.update!(github_models_publisher_id: publisher_rule.models_publisher_id)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        assert_equal({
          isAllowlist: true,
          isModelsEnabled: true,
          allowedModelKeys: [@catalog_item.key],
        }, policy.to_h)
      end

      test "handles when org has a global block rule" do
        create(:github_models_organization_access_rule, :block, organization: @org)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        assert_equal({
          isAllowlist: true,
          isModelsEnabled: true,
          allowedModelKeys: [],
        }, policy.to_h)
      end

      test "handles when org has disabled the Models config setting" do
        assert @org.disable_models_access(@org_admin, instrument: false)
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        assert_equal({
          isAllowlist: false,
          isModelsEnabled: false,
          allowedModelKeys: [],
        }, policy.to_h)
      end

      test "handles when org has both publisher- and model-specific rules" do
        create(:github_models_organization_access_rule, :block, organization: @org)

        allowing_publisher_rule = create(:github_models_organization_access_rule, :allow, :publisher_specific,
          organization: @org)
        blocking_publisher_rule = create(:github_models_organization_access_rule, :block, :publisher_specific,
          organization: @org)

        create(:github_models_organization_access_rule, :allow, organization: @org, catalog_item: @catalog_item)
        create(:github_models_organization_access_rule, :block, organization: @org, catalog_item: @catalog_item2)

        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_equal({
          isAllowlist: true,
          isModelsEnabled: true,
          allowedModelKeys: [@catalog_item.key],
        }, policy.to_h)
      end

      test "handles when all publishers are blocked and no model-specific allow rules exist" do
        publisher1, publisher2 = create_pair(:github_models_publisher)
        @catalog_item.update!(github_models_publisher_id: publisher1.id)
        @catalog_item2.update!(github_models_publisher_id: publisher2.id)
        create(:github_models_organization_access_rule, :block, publisher: publisher1, organization: @org)
        create(:github_models_organization_access_rule, :block, publisher: publisher2, organization: @org)

        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)

        assert_equal({
          isAllowlist: false,
          isModelsEnabled: true,
          allowedModelKeys: [],
        }, policy.to_h)
      end
    end

    unless GitHub.models_enabled?
      test "handles when Models is disabled as a feature" do
        policy = GitHubModels::OrganizationAccessPolicy.new(org: @org)
        assert_equal({
          isAllowlist: false,
          isModelsEnabled: false,
          allowedModelKeys: [],
        }, policy.to_h)
      end
    end
  end
end
