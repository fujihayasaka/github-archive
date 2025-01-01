# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::Permissions::OrgAuthzTest < GitHub::TestCase
  fixtures do
    # Business
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
    @biz = create(:global_business)

    # Orgs
    @orgs = [
      (@biz_org = create(:business_plus_organization, business: @biz, name: "biz-owned-org").tap do |o|
        # Repos
        @biz_org_repo = create(:private_repository, owner: o, name: "#{o}-repo")

        # Teams
        @biz_org_security_manager_team = create(:security_manager_team, organization: o, privacy: :closed)
        @biz_org_security_manager_team_child = create(:team, organization: o, privacy: :closed, parent_team_id: @biz_org_security_manager_team.id)
        @biz_org_security_manager_team_grandchild = create(:team, organization: o, privacy: :closed, parent_team_id: @biz_org_security_manager_team_child.id)
      end),
      (@org = create(:free_organization, name: "free-org").tap do |o|
        # Repos
        @org_repo = create(:private_repository, owner: o, name: "#{o}-repo")

        # Teams
        @org_security_manager_team = create(:security_manager_team, organization: o, privacy: :closed)
        @org_security_manager_team_child = create(:team, organization: o, privacy: :closed, parent_team_id: @org_security_manager_team.id)
        @org_security_manager_team_grandchild = create(:team, organization: o, privacy: :closed, parent_team_id: @org_security_manager_team_child.id)
      end),
    ]

    # Users
    @users = [
      (@biz_owner = create(:user, name: "biz-owner").tap { |u| @biz.add_owner(u, actor: nil) }),
      (@owner = create(:user, name: "owner").tap { |u| @orgs.each { |o| o.add_admin(u) } }),
      (@owner_repo_admin = create(:user, name: "owner-repo-admin").tap do |u|
        @orgs.each { |o| o.add_admin(u) }
        @biz_org_repo.add_member(u, action: :admin)
        @org_repo.add_member(u, action: :admin)
      end),
      (@security_manager = create(:user, name: "security-manager").tap do |u|
        @biz_org_security_manager_team.add_member(u)
        @org_security_manager_team.add_member(u)
      end),
      (@inherited_security_manager = create(:user, name: "inherited-security-manager").tap do |u|
        @biz_org_security_manager_team_grandchild.add_member(u)
        @org_security_manager_team_grandchild.add_member(u)
      end),
      (@member_repo_admin = create(:user, name: "member-repo-admin").tap do |u|
        @orgs.each { |o| o.add_member(u) }
        @biz_org_repo.add_member(u, action: :admin)
        @org_repo.add_member(u, action: :admin)
      end),
      (@member = create(:user, name: "member").tap do |u|
        @orgs.each { |o| o.add_member(u) }
        @user_repo = create(:private_repository, owner: u, name: "#{u}-repo", force_user_owned: true)
      end),
      (@collaborator = create(:user, name: "external-collaborator").tap do |u|
        @biz_org_repo.add_member(u)
        @org_repo.add_member(u)
      end),
      (@pending_collaborator = create(:user, name: "external-pending-collaborator").tap do |u|
        RepositoryInvitation.invite_to_repo(u, @owner, @biz_org_repo)
        RepositoryInvitation.invite_to_repo(u, @owner, @org_repo)
      end),
      (@rando = create(:user, name: "rando")),
    ]
  end

  context "#async_can_view_security_managers?" do
    test "returns expected value for different users" do
      @orgs.each do |o|
        each_user(
          @biz_owner                  => false,
          @owner                      => true,
          @owner_repo_admin           => true,
          @security_manager           => true,
          @inherited_security_manager => true,
          @member_repo_admin          => false,
          @member                     => false,
          @collaborator               => false,
          @pending_collaborator       => false,
          @rando                      => false,
          nil                         => false,
        ) do |u, expected|
          authz = SecurityProduct::Permissions::OrgAuthz.new(o, actor: u)
          assert_equal expected, authz.async_can_view_security_managers?.sync, "User: #{u&.name || "anon"}, Org: #{o.display_login}"
        end
      end
    end
  end

  context "#can_view_security_managers?" do
    test "returns the result of its async counterpart" do
      @orgs.each do |o|
        authz = SecurityProduct::Permissions::OrgAuthz.new(o, actor: nil)

        authz.expects(:async_can_view_security_managers?).once.returns(Promise.resolve(true))
        assert authz.can_view_security_managers?

        authz.expects(:async_can_view_security_managers?).once.returns(Promise.resolve(false))
        refute authz.can_view_security_managers?
      end
    end
  end

  context "#async_can_add_security_managers?" do
    test "returns expected value for different users" do
      @orgs.each do |o|
        each_user(
          @biz_owner                  => false,
          @owner                      => true,
          @owner_repo_admin           => true,
          @security_manager           => false,
          @inherited_security_manager => false,
          @member_repo_admin          => false,
          @member                     => false,
          @collaborator               => false,
          @pending_collaborator       => false,
          @rando                      => false,
          nil                         => false,
        ) do |u, expected|
          authz = SecurityProduct::Permissions::OrgAuthz.new(o, actor: u)
          assert_equal expected, authz.async_can_add_security_managers?.sync, "User: #{u&.name || "anon"}, Org: #{o.display_login}"
        end
      end
    end
  end

  context "#can_add_security_managers?" do
    test "returns the result of its async counterpart" do
      @orgs.each do |o|
        authz = SecurityProduct::Permissions::OrgAuthz.new(o, actor: nil)

        authz.expects(:async_can_add_security_managers?).once.returns(Promise.resolve(true))
        assert authz.can_add_security_managers?

        authz.expects(:async_can_add_security_managers?).once.returns(Promise.resolve(false))
        refute authz.can_add_security_managers?
      end
    end
  end

  context "#async_can_remove_security_managers?" do
    test "returns expected value for different users" do
      @orgs.each do |o|
        each_user(
          @biz_owner                  => false,
          @owner                      => true,
          @owner_repo_admin           => true,
          @security_manager           => false,
          @inherited_security_manager => false,
          @member_repo_admin          => false,
          @member                     => false,
          @collaborator               => false,
          @pending_collaborator       => false,
          @rando                      => false,
          nil                         => false,
        ) do |u, expected|
          authz = SecurityProduct::Permissions::OrgAuthz.new(o, actor: u)
          assert_equal expected, authz.async_can_remove_security_managers?.sync, "User: #{u&.name || "anon"}, Org: #{o.display_login}"
        end
      end
    end
  end

  context "#can_remove_security_managers?" do
    test "returns the result of its async counterpart" do
      @orgs.each do |o|
        authz = SecurityProduct::Permissions::OrgAuthz.new(o, actor: nil)

        authz.expects(:async_can_remove_security_managers?).once.returns(Promise.resolve(true))
        assert authz.can_remove_security_managers?

        authz.expects(:async_can_remove_security_managers?).once.returns(Promise.resolve(false))
        refute authz.can_remove_security_managers?
      end
    end
  end

  context "#async_can_manage_security_products?" do
    test "returns expected value for different users" do
      @orgs.each do |o|
        each_user(
          @biz_owner                  => false,
          @owner                      => true,
          @owner_repo_admin           => true,
          @security_manager           => true,
          @inherited_security_manager => true,
          @member_repo_admin          => false,
          @member                     => false,
          @collaborator               => false,
          @pending_collaborator       => false,
          @rando                      => false,
          nil                         => false,
        ) do |u, expected|
          authz = SecurityProduct::Permissions::OrgAuthz.new(o, actor: u)
          assert_equal expected, authz.async_can_manage_security_products?.sync, "User: #{u&.name || "anon"}, Org: #{o.display_login}"
        end
      end
    end
  end

  context "#can_manage_security_products?" do
    test "returns the result of its async counterpart" do
      @orgs.each do |o|
        authz = SecurityProduct::Permissions::OrgAuthz.new(o, actor: nil)

        authz.expects(:async_can_manage_security_products?).once.returns(Promise.resolve(true))
        assert authz.can_manage_security_products?

        authz.expects(:async_can_manage_security_products?).once.returns(Promise.resolve(false))
        refute authz.can_manage_security_products?
      end
    end
  end

  private

  def each_user(**expectations)
    [*@users, nil].each do |user|
      raise ArgumentError.new "expected result for #{user&.name || "anon"}" unless expectations.key?(user)
      yield user, expectations[user]
    end
  end
end
