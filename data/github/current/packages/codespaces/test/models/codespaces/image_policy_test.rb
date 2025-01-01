# typed: true
# frozen_string_literal: true

require "test_helper"

class ImagePolicyTest < GitHub::TestCase
  include CodespacesPlanFixtures
  fixtures do
    @user = create(:user)

    @org = create(:codespaces_organization, admin: @user)
    @org.add_member(@user)
    @org_repo = create(:private_repository, owner: @org)
    @org_repo.add_member(@user)
    Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

    @policy_group_org = create(:policy_group, :all_targets, owner: @org, name: "all repos")
    @policy_group_repo = create(:policy_group, owner: @org, name: "specific repo")
    create(:policy_group_membership, policy_group: @policy_group_repo, target: @org_repo)
  end

  context ".image_allowed?" do
    context "org policy exists" do
      test "returns true if part of allow list (exact match)" do
        create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

        assert Codespaces::ImagePolicy.image_allowed?(
          image_name: "ghcr.io/test",
          repository: @org_repo,
          billable_owner: @org,
        )
      end
      test "returns true if part of allow list (exact match - 2)" do
        create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test/image:ubuntu"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

        assert Codespaces::ImagePolicy.image_allowed?(
          image_name: "ghcr.io/test/image:ubuntu",
          repository: @org_repo,
          billable_owner: @org,
        )
      end
      test "returns false if not in allow list" do
        create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

        refute Codespaces::ImagePolicy.image_allowed?(
          image_name: "foobar",
          repository: @org_repo,
          billable_owner: @org,
        )
      end
      context "codespaces_image_policy_supports_wildcard" do
        test "returns true if part of allow list (exact match)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          assert Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns true if part of allow list (exact match - 2)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test/image:ubuntu"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          assert Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:ubuntu",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns false if not in allow list" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          refute Codespaces::ImagePolicy.image_allowed?(
            image_name: "foobar",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns false if not an exact match with the allow list" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          refute Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns false if not an exact match with the allow list (registryName/subDomain)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          refute Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:1",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns false if not an exact match with the allow list (registryName/subDomain - incomplete subdomain)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/tes"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          refute Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:1",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns false if not an exact match with the allow list (registryName/subDomain/imageName)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test/image"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          refute Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:1",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns false if not an exact match with the allow list (registryName/subDomain/imageName:tag)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test/image:ubuntu"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          refute Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:ubuntu2",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns false if not an exact match with the allow list (registryName/subDomain/)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test/"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          refute Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:1",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns true if part of allow list (wildcard)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          assert Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns true if part of allow list (wildcard - 2)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test/*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          assert Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:1",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns true if part of allow list (wildcard - 3)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          assert Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:1",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns true if part of allow list (wildcard - 4)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          assert Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:1",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns true if part of allow list (wildcard - 5)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          assert Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:1",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns true if part of allow list (wildcard - 6)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test/image:ubuntu", "ghcr.io/*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          assert Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:ubuntu2",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns true if part of allow list (wildcard - 7)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          assert Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.ioo/test/image:ubuntu2",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns false if not part of allow list (wildcard - 8)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          refute Codespaces::ImagePolicy.image_allowed?(
            image_name: "test",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns true if part of the allowed list with tag containing '*' (1)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test/image:*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          assert Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:ubuntu",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns true if part of the allowed list with tag containing '*' (2)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test/image:dev*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          assert Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:dev",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns true if part of the allowed list with tag containing '*' (3)" do
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test/image:dev*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          assert Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:dev-ubuntu",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
        test "returns true if matching across both explicit & wildcard constraints" do
          group_2 = create(:policy_group, owner: @org, name: "all repos 2")
          group_3 = create(:policy_group, owner: @org, name: "all repos 3")
          create(:policy_constraint, policy_group: @policy_group_org, allowed_values: ["ghcr.io/test/image:dev*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)
          create(:policy_constraint, policy_group: group_2, allowed_values: ["ghcr.io/test/image:dev-*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)
          create(:policy_constraint, policy_group: group_3, allowed_values: ["ghcr.io/test/image:dev-mega"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

          assert Codespaces::ImagePolicy.image_allowed?(
            image_name: "ghcr.io/test/image:dev-mega",
            repository: @org_repo,
            billable_owner: @org,
          )
        end
      end
    end
    context "org policy does not exists" do
      test "returns true" do
        result = Codespaces::ImagePolicy.image_allowed?(
          image_name: "foobar",
          repository: @org_repo,
          billable_owner: @org,
        )

        assert result
      end
    end
  end

  context ".merged_allowlists" do
    test "reduces to least permissive wildcards and exact matches" do
      group_1 = @policy_group_org
      group_2 = create(:policy_group, :all_targets, owner: @org, name: "all repos 2")
      group_3 = create(:policy_group, :all_targets, owner: @org, name: "all repos 3")
      group_1.policy_constraints.create(allowed_values: ["abc", "foo.io/*", "ghcr.io/test/image:dev-*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)
      group_2.policy_constraints.create(allowed_values: ["abc", "foo.io/test/image:*", "bar.io/test/image:*", "ghcr.io/test/image:*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)
      group_3.policy_constraints.create(allowed_values: ["abc", "foo.io/test/*", "ghcr.io/test/image:*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

      assert_equal ["abc", "foo.io/test/image:*", "ghcr.io/test/image:dev-*"], Codespaces::ImagePolicy.merged_allowlists(billable_owner: @org, repository: @org_repo).sort
    end

    test "allows nothing with no overlap" do
      group_1 = @policy_group_org
      group_2 = create(:policy_group, :all_targets, owner: @org, name: "all repos 2")
      group_1.policy_constraints.create(allowed_values: ["abc"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)
      group_2.policy_constraints.create(allowed_values: ["bcd", "bar.io/test/image:*", "ghcr.io/test/image:*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

      assert_empty Codespaces::ImagePolicy.merged_allowlists(billable_owner: @org, repository: @org_repo).sort
    end

    test "allows nothing with a blank list" do
      group_1 = @policy_group_org
      group_2 = create(:policy_group, :all_targets, owner: @org, name: "all repos 2")
      group_3 = create(:policy_group, :all_targets, owner: @org, name: "all repos 3")
      group_1.policy_constraints.create(allowed_values: ["abc", "foo.io/test/image:*", "ghcr.io/test/image:dev-*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)
      group_2.policy_constraints.create(allowed_values: [], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)
      group_3.policy_constraints.create(allowed_values: ["abc", "ghcr.io/test/image:*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

      assert_empty Codespaces::ImagePolicy.merged_allowlists(billable_owner: @org, repository: @org_repo).sort
    end
  end

end unless GitHub.enterprise?
