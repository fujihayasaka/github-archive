# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesPolicyGroupTest < GitHub::TestCase
  fixtures do
    @organization = create(:organization)
    @org_policy_group = Codespaces::PolicyGroup.create!(
      name: "My Test Policies",
      owner_id: @organization.id,
      owner_type: Codespaces::PolicyGroup::OWNER_TYPE_USER,
    )
  end

  context "Organization" do
    context ".parent_business_policies" do
      test "returns parent business policies targeting the organization" do
        business = create(:business)
        org = create(:organization, business:)

        create(:policy_group, :all_targets, owner: business, name: "Policy 1")
        create(:policy_group, :selected_targets, owner: business, targets: [org], name: "Policy 2")
        create(:policy_group, :selected_targets, owner: business, targets: [], name: "Policy 3")
        create(:policy_group, :all_targets, owner: org, name: "Policy 4")

        policy_names = Codespaces::PolicyGroup.parent_business_policies(org).map(&:name).sort
        assert_equal ["Policy 1", "Policy 2"], policy_names
      end

      test "excludes hidden business policies" do
        business = create(:business)
        org = create(:organization, business:)

        create(:org_access_policy_group, :all_targets, :all_orgs, owner: business)

        assert_empty Codespaces::PolicyGroup.parent_business_policies(org)
      end
    end

    context "validation" do
      test "disallows an undeclared owner_type" do
        refute_includes Codespaces::PolicyGroup::OWNER_TYPES, "Organization"

        org_policy_group = Codespaces::PolicyGroup.new(
          name: "My Test Policies",
          owner_id: @organization.id,
          owner_type: "Organization",
        )

        refute org_policy_group.valid?
        assert org_policy_group.errors["owner_type"].any?, "expected 'Organization' to be an invalid owner_type"
      end

      test "allows a User owner_type" do
        @organization = create(:organization)
        org_policy_group = Codespaces::PolicyGroup.new(
          name: "My Test Policies",
          owner_id: @organization.id,
          owner_type: Codespaces::PolicyGroup::OWNER_TYPE_USER,
        )

        assert org_policy_group.valid?
        refute org_policy_group.errors["owner_type"].any?, "expected 'User' to be a valid owner_type"
      end

      test "disallows an individual User owner" do
        user = create(:user)
        user_policy_group = Codespaces::PolicyGroup.new(
          name: "My Test Policies",
          owner_id: user.id,
          owner_type: Codespaces::PolicyGroup::OWNER_TYPE_USER,
        )

        refute user_policy_group.valid?
        assert user_policy_group.errors["owner"].any?, "expected individual User to be an invalid owner"
      end

      test "requires a name" do
        policy_group = Codespaces::PolicyGroup.new(
          name: "",
          owner_id: create(:organization).id,
          owner_type: Codespaces::PolicyGroup::OWNER_TYPE_USER,
        )

        refute policy_group.valid?
        assert policy_group.errors["name"], ["can't be blank", "is too short (minimum is 1 character)"]
      end

      test "name must be less than 64 characters in length" do
        str_length = 65
        policy_group = Codespaces::PolicyGroup.new(
          name: SecureRandom.alphanumeric(str_length),
          owner_id: create(:organization).id,
          owner_type: Codespaces::PolicyGroup::OWNER_TYPE_USER,
        )

        refute policy_group.valid?
        assert policy_group.errors["name"], ["is too long (maximum is 64 characters)"]
      end
    end

    context "#apply_universal_membership!" do
      test "does nothing if already universal" do
        @org_policy_group.policy_group_memberships.create!(target: @organization, target_filter: nil)

        @org_policy_group.apply_universal_membership!

        assert_equal 1, @org_policy_group.policy_group_memberships.count
        assert_equal @organization, @org_policy_group.policy_group_memberships.first.target
      end

      test "sets a membership record on the record's owner" do
        @org_policy_group.apply_universal_membership!

        assert_equal 1, @org_policy_group.policy_group_memberships.count
        assert_equal @organization, @org_policy_group.policy_group_memberships.first.target
      end

      test "wipes existing repo membership, then sets a membership record on the record's owner" do
        repo = create(:repository, owner: @organization)
        @org_policy_group.policy_group_memberships.create!(target: repo, target_filter: nil)

        @org_policy_group.apply_universal_membership!

        assert_equal 0, Codespaces::PolicyGroupMembership.where(target: repo).count
        assert_equal 1, @org_policy_group.policy_group_memberships.count
        assert_equal @organization, @org_policy_group.policy_group_memberships.first.target
      end
    end

    context "#apply_entity_allowlist_membership!" do
      test "adds a repo" do
        repo = create(:repository, owner: @organization)
        assert_equal 0, Codespaces::PolicyGroupMembership.where(target: repo).count

        @org_policy_group.apply_entity_allowlist_membership!([repo.id], :repositories)

        assert_equal 1, Codespaces::PolicyGroupMembership.where(target: repo).count
      end

      test "wipes previously included, but now-excluded repos from the list" do
        repo1 = create(:repository, owner: @organization)
        @org_policy_group.policy_group_memberships.create!(target: repo1, target_filter: nil)
        repo2 = create(:repository, owner: @organization)
        @org_policy_group.policy_group_memberships.create!(target: repo2, target_filter: nil)
        repo3 = create(:repository, owner: @organization)

        @org_policy_group.apply_entity_allowlist_membership!([repo2.id, repo3.id], :repositories)

        assert_equal 0, Codespaces::PolicyGroupMembership.where(target: repo1).count
        assert_equal 1, Codespaces::PolicyGroupMembership.where(target: repo2).count
        assert_equal 1, Codespaces::PolicyGroupMembership.where(target: repo3).count
      end

      test "does not create new ones if already exists" do
        repo1 = create(:repository, owner: @organization)
        @org_policy_group.policy_group_memberships.create!(target: repo1, target_filter: nil)
        repo2 = create(:repository, owner: @organization)
        @org_policy_group.policy_group_memberships.create!(target: repo2, target_filter: nil)
        repo3 = create(:repository, owner: @organization)

        @org_policy_group.apply_entity_allowlist_membership!([repo2.id, repo3.id], :repositories)
        @org_policy_group.apply_entity_allowlist_membership!([repo2.id, repo3.id], :repositories)
        assert_equal 0, Codespaces::PolicyGroupMembership.where(target: repo1).count
        assert_equal 1, Codespaces::PolicyGroupMembership.where(target: repo2).count
        assert_equal 1, Codespaces::PolicyGroupMembership.where(target: repo3).count
      end

      test "can still update the repolist to be subset of original" do
        repo1 = create(:repository, owner: @organization)
        @org_policy_group.policy_group_memberships.create!(target: repo1, target_filter: nil)
        repo2 = create(:repository, owner: @organization)
        @org_policy_group.policy_group_memberships.create!(target: repo2, target_filter: nil)
        repo3 = create(:repository, owner: @organization)

        @org_policy_group.apply_entity_allowlist_membership!([repo2.id, repo3.id], :repositories)
        @org_policy_group.apply_entity_allowlist_membership!([repo2.id], :repositories)
        assert_equal 0, Codespaces::PolicyGroupMembership.where(target: repo1).count
        assert_equal 1, Codespaces::PolicyGroupMembership.where(target: repo2).count
        assert_equal 0, Codespaces::PolicyGroupMembership.where(target: repo3).count
      end
    end

    context "#apply_constraints!" do
      test "adds a constraint" do
        @org_policy_group.apply_constraints!([{ name: "codespaces.allowed_machine_types", value: ["standardLinux32gb"] }])

        assert_equal 1, @org_policy_group.policy_constraints.count
        assert_equal "codespaces.allowed_machine_types", @org_policy_group.policy_constraints.first.name
        assert_equal ["standardLinux32gb"], @org_policy_group.policy_constraints.first.allowed_values
      end

      test "updates a constraint" do
        @org_policy_group.policy_constraints.create!(name: "codespaces.allowed_machine_types", allowed_values: ["standardLinux32gb"])
        @org_policy_group.apply_constraints!([{ name: "codespaces.allowed_machine_types", value: %w[basicLinux32gb largePremiumLinux] }])

        assert_equal 1, @org_policy_group.policy_constraints.count
        assert_equal "codespaces.allowed_machine_types", @org_policy_group.policy_constraints.first.name
        assert_equal %w[basicLinux32gb largePremiumLinux], @org_policy_group.policy_constraints.first.allowed_values
      end

      test "fails if a constraint is invalid" do
        policy_group = Codespaces::PolicyGroup.create(
          name: "My Test Policies",
          owner_id: create(:organization).id,
          owner_type: Codespaces::PolicyGroup::OWNER_TYPE_USER,
        )
        exception = assert_raises ActiveRecord::RecordInvalid do
          policy_group.apply_constraints!([{ name: "codespaces.allowed_machine_types", value: ["foobar"] }])
        end

        assert_equal exception.message, "Validation failed: Allowed values Invalid values were included: foobar"
        assert_equal 0, policy_group.policy_constraints.count
      end

      # Until we have another constraint that can be added this won't pass
      # test "deletes a previously-included constraint" do
      #   @org_policy_group.policy_constraints.create!(name: "codespaces.allowed_machine_types", allowed_values: ["standardLinux32gb"])

      #   @org_policy_group.apply_constraints!([])
      #   assert_equal 0, @org_policy_group.policy_constraints.count
      # end

      test "cannot delete a constraint if last one" do
        @org_policy_group.policy_constraints.create!(name: "codespaces.allowed_machine_types", allowed_values: ["standardLinux32gb"])

        assert_raises(ActiveRecord::RecordInvalid) do
          @org_policy_group.apply_constraints!([])
        end
        assert_equal 1, @org_policy_group.reload.policy_constraints.count
      end

    end
  end
end

class CodespacesPolicyGroupForBusinessTest < GitHub::TestCase
  fixtures do
    if GitHub.single_business_environment?
      create(:business) if Business.count == 0
      @business = GitHub.global_business
    else
      @business = create(:business)
    end
    @policy_group = Codespaces::PolicyGroup.create!(
      name: "My Test Policies",
      owner_id: @business.id,
      owner_type: Codespaces::PolicyGroup::OWNER_TYPE_BUSINESS,
    )
  end

  context "validation" do
    test "requires a name" do
      policy_group = Codespaces::PolicyGroup.new(
        name: "",
        owner_id: @business.id,
        owner_type: Codespaces::PolicyGroup::OWNER_TYPE_BUSINESS,
      )

      refute policy_group.valid?
      assert policy_group.errors["name"], ["can't be blank", "is too short (minimum is 1 character)"]
    end

    test "name must be less than 64 characters in length" do
      str_length = 65
      policy_group = Codespaces::PolicyGroup.new(
        name: SecureRandom.alphanumeric(str_length),
        owner_id: @business.id,
        owner_type: Codespaces::PolicyGroup::OWNER_TYPE_BUSINESS,
      )

      refute policy_group.valid?
      assert policy_group.errors["name"], ["is too long (maximum is 64 characters)"]
    end

    test "protects against reserved names" do
      policy_group = Codespaces::PolicyGroup.new(
        name: Codespaces::PolicyGroup::RESERVED_POLICY_GROUP_NAME_BUSINESS_ACCESS,
        owner_id: @business.id,
        owner_type: Codespaces::PolicyGroup::OWNER_TYPE_BUSINESS,
      )
      policy_group.policy_constraints.build(name: "codespaces.allowed_machine_types", allowed_values: ["standardLinux32gb"])

      refute policy_group.valid?
      assert policy_group.errors["name"].any? { |s|  s =~ /is a reserved policy name/ }
    end
  end

  context "#apply_universal_membership!" do
    test "does nothing if already universal" do
      @policy_group.policy_group_memberships.create!(target: @business, target_filter: nil)

      @policy_group.apply_universal_membership!

      assert_equal 1, @policy_group.policy_group_memberships.count
      assert_equal @business, @policy_group.policy_group_memberships.first.target
    end

    test "sets a membership record on the record's owner" do
      @policy_group.apply_universal_membership!

      assert_equal 1, @policy_group.policy_group_memberships.count
      assert_equal @business, @policy_group.policy_group_memberships.first.target
    end

    test "wipes existing org membership, then sets a membership record on the record's owner" do
      org = create(:organization)
      @business.add_organization(org)
      @policy_group.policy_group_memberships.create!(target: org, target_filter: nil)

      @policy_group.apply_universal_membership!

      assert_equal 0, org.policy_group_memberships.count
      assert_equal 1, @policy_group.policy_group_memberships.count
      assert_equal @business, @policy_group.policy_group_memberships.first.target
    end
  end

  context "#apply_entity_allowlist_membership!" do
    test "adds an organization" do
      org = create(:organization)
      @business.add_organization(org)
      assert_equal 0, org.policy_group_memberships.count

      @policy_group.apply_entity_allowlist_membership!([org.id], :organizations)

      assert_equal 1, org.policy_group_memberships.count
    end

    test "wipes previously included, but now-excluded orgs from the list" do
      org1 = create(:organization)
      @business.add_organization(org1)
      @policy_group.policy_group_memberships.create!(target: org1, target_filter: nil)
      org2 = create(:organization)
      @business.add_organization(org2)
      @policy_group.policy_group_memberships.create!(target: org2, target_filter: nil)
      org3 = create(:organization)
      @business.add_organization(org3)

      @policy_group.apply_entity_allowlist_membership!([org2.id, org3.id], :organizations)

      assert_equal 0, org1.policy_group_memberships.count
      assert_equal 1, org2.policy_group_memberships.count
      assert_equal 1, org3.policy_group_memberships.count
    end

    test "does not create new ones if already exists" do
      org1 = create(:organization)
      @business.add_organization(org1)
      @policy_group.policy_group_memberships.create!(target: org1, target_filter: nil)
      org2 = create(:organization)
      @business.add_organization(org2)
      @policy_group.policy_group_memberships.create!(target: org2, target_filter: nil)
      org3 = create(:organization)
      @business.add_organization(org3)

      @policy_group.apply_entity_allowlist_membership!([org2.id, org3.id], :organizations)
      @policy_group.apply_entity_allowlist_membership!([org2.id, org3.id], :organizations)
      assert_equal 0, org1.policy_group_memberships.count
      assert_equal 1, org2.policy_group_memberships.count
      assert_equal 1, org3.policy_group_memberships.count
    end

    test "can still update the repolist to be subset of original" do
      org1 = create(:organization)
      @business.add_organization(org1)
      @policy_group.policy_group_memberships.create!(target: org1, target_filter: nil)
      org2 = create(:organization)
      @business.add_organization(org2)
      @policy_group.policy_group_memberships.create!(target: org2, target_filter: nil)
      org3 = create(:organization)
      @business.add_organization(org3)

      @policy_group.apply_entity_allowlist_membership!([org2.id, org3.id], :organizations)
      @policy_group.apply_entity_allowlist_membership!([org2.id], :organizations)
      assert_equal 0, org1.policy_group_memberships.count
      assert_equal 1, org2.policy_group_memberships.count
      assert_equal 0, org3.policy_group_memberships.count
    end
  end

  context "#apply_constraints!" do
    test "adds a constraint" do
      @policy_group.apply_constraints!([{ name: "codespaces.allowed_machine_types", value: ["standardLinux32gb"] }])

      assert_equal 1, @policy_group.policy_constraints.count
      assert_equal "codespaces.allowed_machine_types", @policy_group.policy_constraints.first.name
      assert_equal ["standardLinux32gb"], @policy_group.policy_constraints.first.allowed_values
    end

    test "updates a constraint" do
      @policy_group.policy_constraints.create!(name: "codespaces.allowed_machine_types", allowed_values: ["standardLinux32gb"])
      @policy_group.apply_constraints!([{ name: "codespaces.allowed_machine_types", value: %w[basicLinux32gb largePremiumLinux] }])

      assert_equal 1, @policy_group.policy_constraints.count
      assert_equal "codespaces.allowed_machine_types", @policy_group.policy_constraints.first.name
      assert_equal %w[basicLinux32gb largePremiumLinux], @policy_group.policy_constraints.first.allowed_values
    end

    test "fails if a constraint is invalid" do
      policy_group = Codespaces::PolicyGroup.create(
        name: "My Test Policies 2",
        owner_id: @business.id,
        owner_type: Codespaces::PolicyGroup::OWNER_TYPE_BUSINESS,
      )
      exception = assert_raises ActiveRecord::RecordInvalid do
        policy_group.apply_constraints!([{ name: "codespaces.allowed_machine_types", value: ["foobar"] }])
      end

      assert_equal exception.message, "Validation failed: Allowed values Invalid values were included: foobar"
      assert_equal 0, policy_group.policy_constraints.count
    end

    test "cannot delete a constraint if last one" do
      @policy_group.policy_constraints.create!(name: "codespaces.allowed_machine_types", allowed_values: ["standardLinux32gb"])

      assert_raises(ActiveRecord::RecordInvalid) do
        @policy_group.apply_constraints!([])
      end
      assert_equal 1, @policy_group.reload.policy_constraints.count
    end

  end
end
