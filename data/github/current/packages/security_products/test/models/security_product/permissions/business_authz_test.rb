# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::Permissions::BusinessAuthzTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @biz = create(:global_business)
    @biz_org = create(:business_plus_organization, business: @biz, name: "biz-owned-org")
    @biz_org_repo = create(:private_repository, owner: @biz_org, name: "biz-org-repo")
    @biz_security_manager_team = create(:enterprise_security_manager_team, business: @biz)
    @biz_org_security_manager_team = create(:security_manager_team, organization: @biz_org)

    @users = [
      @biz_owner = create(:user, name: "biz-owner").tap { |u| @biz.add_owner(u, actor: nil) },
      @biz_security_manager = create(:user, name: "biz-security-manager").tap { |u| @biz_org.add_member(u) ; @biz_security_manager_team.bulk_add_members(users: [u]) },
      @biz_member_org_owner = create(:user, name: "biz-member-org-owner").tap { |u| @biz_org.add_admin(u) },
      @biz_member_org_security_manager = create(:user, name: "biz-member-org-security-manager").tap { |u| @biz_org_security_manager_team.add_member(u) },
      @biz_member = create(:user, name: "biz-member").tap { |u| @biz_org.add_member(u) },
      @collaborator = create(:user, name: "collaborator").tap { |u| @biz_org_repo.add_member(u) },
      @pending_collaborator = create(:user, name: "pending-collaborator").tap { |u| RepositoryInvitation.invite_to_repo(u, @biz_member_org_owner, @biz_org_repo) },
      @rando = create(:user, name: "rando"),
      @biz_team_member = create(:user, name: "biz-team-member")
    ]
  end

  setup do
    enable_feature_flag(:custom_enterprise_role_feature)
  end

  [
    :can_view_code_security_policies?,
    :can_view_code_security_settings?,
    :can_modify_code_security_policies?,
    :can_modify_code_security_settings?,
    :can_view_user_owned_repository_alerts?,
    :can_unlock_user_owned_repositories?
  ].each do |method|
    context "##{method}" do
      test "returns expected value for different users" do
        _, biz_team = add_user_to_enterprise_team(business: @biz, user: @biz_team_member)
        grant_fgp_to_enterprise_team(team: biz_team, target: @biz, fgps: [:manage_enterprise_security_products])

        each_user(
          @biz_owner                       => true,
          @biz_security_manager            => true,
          @biz_member_org_owner            => false,
          @biz_member_org_security_manager => false,
          @biz_member                      => false,
          @collaborator                    => false,
          @pending_collaborator            => false,
          @rando                           => false,
          @biz_team_member                 => GitHub.flipper[:business_esm_check_permission_via_authz_domain].enabled?,
          nil                              => false,
        ) do |u, expected|
          authz = SecurityProduct::Permissions::BusinessAuthz.new(@biz, actor: u)
          assert_equal expected, authz.public_send(method), "User: #{u&.name || "anon"}"
        end
      end
    end
  end

  context "#can_view_code_security_settings?"  do
    test "returns false for enterprise security managers when ESM is enabled" do
      EnterpriseTeam.expects(:enabled_for_organization_security_manager?).at_least_once.returns(true)
      authz = SecurityProduct::Permissions::BusinessAuthz.new(@biz, actor: @biz_security_manager)
      refute authz.can_view_code_security_settings?
    end
  end

  context "#can_modify_code_security_settings?"  do
    test "returns false for enterprise security managers when ESM is enabled" do
      EnterpriseTeam.expects(:enabled_for_organization_security_manager?).at_least_once.returns(true)
      authz = SecurityProduct::Permissions::BusinessAuthz.new(@biz, actor: @biz_security_manager)
      refute authz.can_modify_code_security_settings?
    end
  end

  private

  def each_user(**expectations)
    [*@users, nil].each do |user|
      raise ArgumentError.new "expected result for #{user&.name || "anon"}" unless expectations.key?(user)
      yield user, expectations[user]
    end
  end

  context "#check authzd parameters" do
    test "check context parameter is passed upfront" do
      skip if GitHub.flipper[:business_esm_check_permission_via_authz_domain].enabled?
      Platform::Loaders::Permissions::BatchAuthorize.expects(:load).with(
        action: :manage_enterprise_security_products,
        actor: @biz_security_manager,
        subject: @biz,
        context: { "business.enterprise_teams.for_user": [@biz_security_manager_team.id] },
      ).returns(Promise.resolve(Authzd::ALLOW))

      authz = SecurityProduct::Permissions::BusinessAuthz.new(@biz, actor: @biz_security_manager)
      assert authz.can_modify_code_security_settings?
    end
  end
end
