# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::OrganizationAccessRuleTest < GitHub::TestCase
  fixtures do
    @catalog_item = create(:github_models_catalog_item)
  end

  context "instrumentation" do
    test "instruments a creation event for a model-specific rule" do
      events = subscribe("github_models_organization_access_rule.create")
      actor = create(:user)
      org = create(:organization, admin: actor)
      rule = build(:github_models_organization_access_rule, :block, organization: org, actor: actor,
        catalog_item: @catalog_item)

      assert_difference("events.size") { rule.save! }

      refute_nil event = events.pop, "a new audit log event was expected"
      assert_subset_hash({
        allow: false,
        github_models_organization_access_rule: "Block model #{@catalog_item.friendly_name}",
        github_models_organization_access_rule_id: rule.id,
        actor: actor.login,
        actor_id: actor.id,
        model: @catalog_item.friendly_name,
        model_key: @catalog_item.key,
        org: org.login,
        org_id: org.id,
      }, event.payload)
    end

    test "instruments a creation event for a publisher-specific rule" do
      events = subscribe("github_models_organization_access_rule.create")
      publisher = create(:github_models_publisher)
      actor = create(:user)
      org = create(:organization, admin: actor)
      rule = build(:github_models_organization_access_rule, :block, organization: org, actor: actor,
        publisher: publisher)

      assert_difference("events.size") { rule.save! }

      refute_nil event = events.pop, "a new audit log event was expected"
      assert_subset_hash({
        allow: false,
        github_models_organization_access_rule: "Block publisher #{publisher.name}",
        github_models_organization_access_rule_id: rule.id,
        actor: actor.login,
        actor_id: actor.id,
        model_publisher: publisher.name,
        model_publisher_id: publisher.id,
        org: org.login,
        org_id: org.id,
      }, event.payload)
    end

    test "instruments a creation event for a global rule" do
      events = subscribe("github_models_organization_access_rule.create")
      actor = create(:user)
      org = create(:organization, admin: actor)
      rule = build(:github_models_organization_access_rule, :block, organization: org, actor: actor)

      assert_difference("events.size") { rule.save! }

      refute_nil event = events.pop, "a new audit log event was expected"
      assert_subset_hash({
        allow: false,
        github_models_organization_access_rule: "Block GitHub Models access",
        github_models_organization_access_rule_id: rule.id,
        actor: actor.login,
        actor_id: actor.id,
        org: org.login,
        org_id: org.id,
      }, event.payload)
    end

    test "instruments a deletion event for a model-specific rule" do
      events = subscribe("github_models_organization_access_rule.destroy")
      actor = create(:user)
      org = create(:organization, admin: actor)
      rule = create(:github_models_organization_access_rule, :block, organization: org, actor: actor,
        catalog_item: @catalog_item)

      assert_difference("events.size") { rule.destroy! }

      refute_nil event = events.pop, "a new audit log event was expected"
      assert_subset_hash({
        allow: false,
        github_models_organization_access_rule: "Block model #{@catalog_item.friendly_name}",
        github_models_organization_access_rule_id: rule.id,
        actor: actor.login,
        actor_id: actor.id,
        model: @catalog_item.friendly_name,
        model_key: @catalog_item.key,
        org: org.login,
        org_id: org.id,
      }, event.payload)
    end

    test "instruments a deletion event for a publisher-specific rule" do
      events = subscribe("github_models_organization_access_rule.destroy")
      publisher = create(:github_models_publisher)
      actor = create(:user)
      org = create(:organization, admin: actor)
      rule = create(:github_models_organization_access_rule, :block, publisher: publisher, organization: org,
        actor: actor)

      assert_difference("events.size") { rule.destroy! }

      refute_nil event = events.pop, "a new audit log event was expected"
      assert_subset_hash({
        allow: false,
        github_models_organization_access_rule: "Block publisher #{publisher.name}",
        github_models_organization_access_rule_id: rule.id,
        actor: actor.login,
        actor_id: actor.id,
        model_publisher: publisher.name,
        model_publisher_id: publisher.id,
        org: org.login,
        org_id: org.id,
      }, event.payload)
    end

    test "instruments a deletion event for a global rule" do
      events = subscribe("github_models_organization_access_rule.destroy")
      actor = create(:user)
      org = create(:organization, admin: actor)
      rule = create(:github_models_organization_access_rule, :block, organization: org, actor: actor)

      assert_difference("events.size") { rule.destroy! }

      refute_nil event = events.pop, "a new audit log event was expected"
      assert_subset_hash({
        allow: false,
        github_models_organization_access_rule: "Block GitHub Models access",
        github_models_organization_access_rule_id: rule.id,
        actor: actor.login,
        actor_id: actor.id,
        org: org.login,
        org_id: org.id,
      }, event.payload)
    end

    test "instruments an update event for a model-specific rule" do
      events = subscribe("github_models_organization_access_rule.update")
      actor = create(:user)
      org = create(:organization, admin: actor)
      create(:github_models_organization_access_rule, :block, organization: org)
      rule = create(:github_models_organization_access_rule, :block, organization: org, actor: actor,
        catalog_item: @catalog_item)

      assert_difference("events.size") { rule.update!(allow: true) }

      refute_nil event = events.pop, "a new audit log event was expected"
      assert_subset_hash({
        allow: true,
        old_allow: false,
        github_models_organization_access_rule: "Allow model #{@catalog_item.friendly_name}",
        github_models_organization_access_rule_id: rule.id,
        actor: actor.login,
        actor_id: actor.id,
        model: @catalog_item.friendly_name,
        model_key: @catalog_item.key,
        org: org.login,
        org_id: org.id,
      }, event.payload)
    end

    test "instruments an update event for a publisher-specific rule" do
      events = subscribe("github_models_organization_access_rule.update")
      publisher = create(:github_models_publisher)
      actor = create(:user)
      org = create(:organization, admin: actor)
      create(:github_models_organization_access_rule, :block, organization: org)
      rule = create(:github_models_organization_access_rule, :block, organization: org, actor: actor,
        publisher: publisher)

      assert_difference("events.size") { rule.update!(allow: true) }

      refute_nil event = events.pop, "a new audit log event was expected"
      assert_subset_hash({
        allow: true,
        old_allow: false,
        github_models_organization_access_rule: "Allow publisher #{publisher.name}",
        github_models_organization_access_rule_id: rule.id,
        actor: actor.login,
        actor_id: actor.id,
        model_publisher: publisher.name,
        model_publisher_id: publisher.id,
        org: org.login,
        org_id: org.id,
      }, event.payload)
    end
  end

  context "validations" do
    test "requires an organization" do
      rule = GitHubModels::OrganizationAccessRule.new(organization: nil)
      refute_predicate rule, :valid?
      assert_includes rule.errors[:organization], "must exist"
    end

    test "requires 'allow' to be non-nil" do
      rule = build(:github_models_organization_access_rule, allow: nil)
      assert_nothing_raised { rule.save }
      assert_includes rule.errors[:allow], "is not included in the list"
    end

    test "requires catalog item to belong to publisher if both are set" do
      publisher1, publisher2 = create_pair(:github_models_publisher)
      @catalog_item.update!(github_models_publisher_id: publisher2.id)

      rule = GitHubModels::OrganizationAccessRule.new(publisher: publisher1, catalog_item: @catalog_item)

      refute_predicate rule, :valid?
      assert_includes rule.errors[:catalog_item], "does not match publisher"
    end

    test "sets publisher based on catalog item when not specifically set" do
      publisher = create(:github_models_publisher)
      @catalog_item.update!(github_models_publisher_id: publisher.id)
      rule = GitHubModels::OrganizationAccessRule.new(catalog_item: @catalog_item, publisher: nil)

      rule.valid? # trigger before_validation callback

      assert_equal publisher, rule.publisher
    end

    test "requires unique publisher-specific rule per org" do
      publisher = create(:github_models_publisher)
      org = create(:organization)
      existing_rule = create(:github_models_organization_access_rule, publisher: publisher, organization: org)
      new_rule = GitHubModels::OrganizationAccessRule.new(organization: org, publisher: publisher)

      refute_predicate new_rule, :valid?
      assert_includes new_rule.errors[:organization], "already has a rule for this publisher"
    end

    test "allows multiple rules to specify the same publisher when they're model-specific rules" do
      publisher = create(:github_models_publisher)
      catalog_item1, catalog_item2 = create_pair(:github_models_catalog_item,
        github_models_publisher_id: publisher.id)
      org = create(:organization)
      existing_rule = create(:github_models_organization_access_rule, publisher: publisher, organization: org,
        catalog_item: catalog_item1)
      new_rule = build(:github_models_organization_access_rule, organization: org, publisher: publisher,
        catalog_item: catalog_item2)

      assert_predicate new_rule, :valid?
      assert new_rule.save
    end

    test "allows creating a global block rule when org has publisher- and model-specific rules" do
      org = create(:organization)
      create(:github_models_organization_access_rule, :publisher_specific, organization: org)
      create(:github_models_organization_access_rule, :model_specific, organization: org)
      global_rule = build(:github_models_organization_access_rule, :block, organization: org, publisher: nil,
        catalog_item: nil)

      assert_predicate global_rule, :valid?
      assert global_rule.save
    end

    test "requires unique model-specific rule per org" do
      publisher = create(:github_models_publisher)
      @catalog_item.update!(github_models_publisher_id: publisher.id)
      org = create(:organization)
      create(:github_models_organization_access_rule, catalog_item: @catalog_item, organization: org,
        publisher: publisher)
      new_rule = GitHubModels::OrganizationAccessRule.new(organization: org, catalog_item: @catalog_item,
        publisher: publisher)

      refute_predicate new_rule, :valid?
      assert_includes new_rule.errors[:organization], "already has a rule for this model"
    end

    test "requires unique global rule per org" do
      org = create(:organization)
      create(:github_models_organization_access_rule, :block, organization: org)
      new_rule = GitHubModels::OrganizationAccessRule.new(organization: org, allow: false)

      refute_predicate new_rule, :valid?
      assert_includes new_rule.errors[:organization], "already has a rule for GitHub Models access"
    end

    test "requires global rule be blocking" do
      org = create(:organization)
      rule = GitHubModels::OrganizationAccessRule.new(organization: org, allow: true)

      refute_predicate rule, :valid?
      assert_includes rule.errors[:allow],
        "must be false for a rule that does not target a specific publisher or model"
    end

    test "requires publisher ID to be valid at creation time if specified" do
      rule = build(:github_models_organization_access_rule, models_publisher_id: 0)
      refute rule.save
      assert_includes rule.errors[:models_publisher_id], "is invalid"
    end

    test "allows invalid publisher ID when updating an existing rule" do
      rule = create(:github_models_organization_access_rule, :publisher_specific)
      rule.publisher.delete
      refute_nil rule.models_publisher_id
      assert_predicate rule.reload, :valid?
    end
  end

  context "for_org scope" do
    test "filters rules by organization" do
      org1, org2 = create_pair(:organization)
      org1_rule1 = create(:github_models_organization_access_rule, :block, organization: org1)
      org1_rule2 = create(:github_models_organization_access_rule, :publisher_specific, :allow,
        organization: org1)
      org2_rule = create(:github_models_organization_access_rule, :block, organization: org2)

      assert_same_elements [org1_rule1, org1_rule2], GitHubModels::OrganizationAccessRule.for_org(org1)
      assert_equal [org2_rule], GitHubModels::OrganizationAccessRule.for_org(org2.id)
      assert_empty GitHubModels::OrganizationAccessRule.for_org(nil)
    end
  end

  context "#global?" do
    test "returns false for rule that specifies a model" do
      rule = build(:github_models_organization_access_rule, :model_specific)
      refute_predicate rule, :global?
    end

    test "returns false for rule that specifies a publisher" do
      rule = build(:github_models_organization_access_rule, :publisher_specific)
      refute_predicate rule, :global?
    end

    test "returns true for rule that does not specify a publisher or model" do
      rule = build(:github_models_organization_access_rule, publisher: nil, catalog_item: nil)
      assert_predicate rule, :global?
    end
  end

  context "targeted scope" do
    test "filters to just rules that target a model or publisher" do
      model_specific_rule = create(:github_models_organization_access_rule, :model_specific)
      publisher_specific_rule = create(:github_models_organization_access_rule, :publisher_specific)
      global_rule = create(:github_models_organization_access_rule, :block)

      result = GitHubModels::OrganizationAccessRule.targeted
        .where(id: [model_specific_rule.id, publisher_specific_rule.id, global_rule.id])

      assert_same_elements [model_specific_rule, publisher_specific_rule], result
      assert result.none?(&:global?), ".targeted scope should not return any #global? rule"
    end
  end

  context "global scope" do
    test "filters to just rules that don't target a model or publisher" do
      model_specific_rule = create(:github_models_organization_access_rule, :model_specific)
      publisher_specific_rule = create(:github_models_organization_access_rule, :publisher_specific)
      global_rule = create(:github_models_organization_access_rule, :block)

      result = GitHubModels::OrganizationAccessRule.global
        .where(id: [model_specific_rule.id, publisher_specific_rule.id, global_rule.id])

      assert_equal [global_rule], result
      assert result.all?(&:global?), "#global? method should be in sync with .global scope"
    end
  end

  context "#block?" do
    test "returns true if allow is false" do
      rule = GitHubModels::OrganizationAccessRule.new(allow: false)
      assert_predicate rule, :block?
    end

    test "returns false if allow is true" do
      rule = GitHubModels::OrganizationAccessRule.new(allow: true)
      refute_predicate rule, :block?
    end
  end

  context "#target" do
    test "returns the catalog item if set" do
      rule = GitHubModels::OrganizationAccessRule.new(catalog_item: @catalog_item)
      assert_equal @catalog_item, rule.target
    end

    test "returns the publisher if no catalog item is set" do
      publisher = build(:github_models_publisher)
      rule = GitHubModels::OrganizationAccessRule.new(publisher: publisher, catalog_item: nil)
      assert_equal publisher, rule.target
    end
  end

  context "allowed scope" do
    test "filters to allowing rules only" do
      allowed_rule = create(:github_models_organization_access_rule, :allow, :model_specific)
      blocked_rule = create(:github_models_organization_access_rule, :block)

      result = GitHubModels::OrganizationAccessRule.allowed.where(id: [allowed_rule.id, blocked_rule.id])

      assert_equal [allowed_rule], result
    end
  end

  context "blocked scope" do
    test "filters to blocking rules only" do
      allowed_rule = create(:github_models_organization_access_rule, :allow, :publisher_specific)
      blocked_rule = create(:github_models_organization_access_rule, :block)

      result = GitHubModels::OrganizationAccessRule.blocked.where(id: [allowed_rule.id, blocked_rule.id])

      assert_equal [blocked_rule], result
    end
  end

  context "#target_label" do
    test "handles a rule that specifies a catalog item" do
      rule = GitHubModels::OrganizationAccessRule.new(catalog_item: build(:github_models_catalog_item))
      assert_equal "model", rule.target_label
    end

    test "handles a rule that does not specify a catalog item but does specify a publisher" do
      rule = GitHubModels::OrganizationAccessRule.new(catalog_item: nil,
        publisher: build(:github_models_publisher))
      assert_equal "publisher", rule.target_label
    end

    test "handles a rule that specifies neither catalog item nor publisher" do
      rule = GitHubModels::OrganizationAccessRule.new(catalog_item: nil, publisher: nil)
      assert_equal "GitHub Models access", rule.target_label
    end
  end

  context "#model_specific?" do
    test "returns true when rule targets a model" do
      assert_predicate GitHubModels::OrganizationAccessRule.new(catalog_item: @catalog_item, publisher: nil),
        :model_specific?
    end

    test "returns false when a rule targets a publisher" do
      publisher = create(:github_models_publisher)
      refute_predicate GitHubModels::OrganizationAccessRule.new(publisher: publisher, catalog_item: nil),
        :model_specific?
    end

    test "returns false for a global rule" do
      refute_predicate GitHubModels::OrganizationAccessRule.new(publisher: nil, catalog_item: nil), :model_specific?
    end
  end

  context "#publisher_specific?" do
    test "returns false when rule targets a model" do
      refute_predicate GitHubModels::OrganizationAccessRule.new(catalog_item: @catalog_item, publisher: nil),
        :publisher_specific?
    end

    test "returns true when a rule targets a publisher" do
      publisher = create(:github_models_publisher)
      assert_predicate GitHubModels::OrganizationAccessRule.new(publisher: publisher, catalog_item: nil),
        :publisher_specific?
    end

    test "returns false for a global rule" do
      refute_predicate GitHubModels::OrganizationAccessRule.new(publisher: nil, catalog_item: nil),
        :publisher_specific?
    end
  end
end
