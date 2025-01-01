# typed: true
# frozen_string_literal: true

require "test_helper"

class HostSetupPolicyTest < GitHub::TestCase
  include CodespacesPlanFixtures
  fixtures do
    @user = create(:user)
    @org = create(:codespaces_organization, admin: @user)
    @enterprise = create(:business)
    @enterprise.add_organization(@org)
    GitHub.flipper[:codespaces_host_setup_policy].enable(@org)
    GitHub.flipper[:codespaces_salus_beta_customers].enable(@enterprise)

    @org.add_member(@user)
    @org_repo = create(:private_repository, owner: @org)
    @org_repo.add_member(@user)

    Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

    @policy_group_org = create(:policy_group, owner: @org, name: "all repos")
    create(:policy_group_membership, policy_group: @policy_group_org, target: @org)

    @policy_group_org_2 = create(:policy_group, owner: @org, name: "all repos: 2")
    create(:policy_group_membership, policy_group: @policy_group_org_2, target: @org)

    @policy_group_repo = create(:policy_group, owner: @org, name: "specific repo")
    create(:policy_group_membership, policy_group: @policy_group_repo, target: @org_repo)

    @params = {
          repo: "#{@org.login}/#{@org_repo.name}",
          branch: "main",
          path: "host-setup.sh"
    }
  end

  context "#get_host_setup_config" do
    context "org policy exists" do
      test "returns {} if FF is disabled" do
        GitHub.flipper[:codespaces_host_setup_policy].disable(@org)
        GitHub.flipper[:codespaces_salus_beta_customers].disable
        create(:policy_constraint, policy_group: @policy_group_org, params: @params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

        result = Codespaces::HostSetupPolicy.get_host_setup_config(
          repository: @org_repo,
          billable_owner: @org,
        )

        assert_equal Hash.new, result
      end

      test "returns host setup when org level" do
        create(:policy_constraint, policy_group: @policy_group_org, params: @params , allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

        result = Codespaces::HostSetupPolicy.get_host_setup_config(
          repository: @org_repo,
          billable_owner: @org,
        )

        assert_equal "#{@org.login}/#{@org_repo.name}", result["repo"]
        assert_equal "main", result["branch"]
        assert_equal "host-setup.sh", result["path"]
      end

      test "returns host setup when repo level" do
        create(:policy_constraint, policy_group: @policy_group_repo, params: @params , allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

        result = Codespaces::HostSetupPolicy.get_host_setup_config(
          repository: @org_repo,
          billable_owner: @org,
        )

        assert_equal "#{@org.login}/#{@org_repo.name}", result["repo"]
        assert_equal "main", result["branch"]
        assert_equal "host-setup.sh", result["path"]
      end

      test "returns empty [] if params doesn't exist" do
        create(:policy_constraint, policy_group: @policy_group_repo, allowed_values: [:premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

        result = Codespaces::HostSetupPolicy.get_host_setup_config(
          repository: @org_repo,
          billable_owner: @org,
        )

        assert result
        assert_nil result.first
      end
    end

    context "org policy does not exist" do
      test "returns {}" do
        result = Codespaces::HostSetupPolicy.get_host_setup_config(
          repository: @org_repo,
          billable_owner: @org,
        )

        assert_equal Hash.new, result
      end

      test "returns {} if FF is disabled" do
        GitHub.flipper[:codespaces_host_setup_policy].disable(@org)
        GitHub.flipper[:codespaces_salus_beta_customers].disable
        result = Codespaces::HostSetupPolicy.get_host_setup_config(
          repository: @org_repo,
          billable_owner: @org,
        )

        assert_equal Hash.new, result
      end
    end

    context "personal user repo" do
      test "returns {}" do
        result = Codespaces::HostSetupPolicy.get_host_setup_config(
          repository: @org_repo,
          billable_owner: @user,
        )

        assert_equal Hash.new, result
      end
    end

    context "multiple org policies" do
      test "returns correct policy for required repo" do
        create(:policy_constraint, policy_group: @policy_group_repo, params: @params , allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

        org_repo_2 = create(:private_repository, owner: @org)
        policy_group_repo_2 = create(:policy_group, owner: @org, name: "specific repo - 2")
        create(:policy_group_membership, policy_group: policy_group_repo_2, target: org_repo_2)

        params_2 = {
            repo: "#{@org.login}/#{org_repo_2.name}",
            branch: "master",
            path: "host-setup-2.sh"
        }

        create(:policy_constraint, policy_group: policy_group_repo_2, params: params_2 , allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

        result = Codespaces::HostSetupPolicy.get_host_setup_config(
          repository: org_repo_2,
          billable_owner: @org,
        )

        assert_equal "#{@org.login}/#{org_repo_2.name}", result["repo"]
        assert_equal "master", result["branch"]
        assert_equal "host-setup-2.sh", result["path"]
      end

      test "returns specific repo over org one" do
        org_repo_2 = create(:private_repository, owner: @org)
        create(:policy_constraint, policy_group: @policy_group_org, params: @params , allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)
        params_2 = {
            repo: "#{@org.login}/#{org_repo_2.name}",
            branch: "master",
            path: "host-setup-2.sh"
        }

        create(:policy_constraint, policy_group: @policy_group_repo, params: params_2 , allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

        result = Codespaces::HostSetupPolicy.get_host_setup_config(
          repository: @org_repo,
          billable_owner: @org,
        )

        assert_equal "#{@org.login}/#{org_repo_2.name}", result["repo"]
        assert_equal "master", result["branch"]
        assert_equal "host-setup-2.sh", result["path"]
      end
    end
  end

end unless GitHub.enterprise?
