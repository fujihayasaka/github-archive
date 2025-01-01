# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::Permissions::RepoAuthzTest < GitHub::TestCase
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
      (@org = create(:business_plus_organization, name: "test-org").tap do |o|
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

    unless GitHub.enterprise?
      @emu_biz = create(:business, :enterprise_managed)
      @emu_admin = @emu_biz.find_first_emu_owner

      @emu_users = [
        (@emu_biz_owner = create(:emu, :owner, business: @emu_biz, name: "emu-biz-owner").tap { |u| @emu_biz.add_owner(u, actor: nil) }),
        (@emu_biz_member = create(:emu, business: @emu_biz, name: "emu-biz-member").tap do |u|
          @emu_repo = create(:private_repository, force_user_owned: true, owner: u, name: "#{u}-repo")
        end),
      ]
    end
  end

  context "#async_can_manage_security_products?" do
    test "returns expected value for different users" do
      [@biz_org_repo, @org_repo].each do |r|
        each_user(
          @biz_owner                  => false,
          @owner                      => true,
          @owner_repo_admin           => true,
          @security_manager           => true,
          @inherited_security_manager => true,
          @member_repo_admin          => true,
          @member                     => false,
          @collaborator               => false,
          @pending_collaborator       => false,
          @rando                      => false,
          nil                         => false,
        ) do |u, expected|
          authz = SecurityProduct::Permissions::RepoAuthz.new(r, actor: u)
          assert_equal expected, authz.async_can_manage_security_products?.sync, "User: #{u&.name || "anon"}, Repo: #{r.name}"
        end
      end
    end
  end

  context "#can_manage_security_products?" do
    test "returns the result of its async counterpart" do
      [@biz_org_repo, @org_repo].each do |r|
        authorizer = SecurityProduct::Permissions::RepoAuthz.new(r, actor: nil)

        authorizer.expects(:async_can_manage_security_products?).once.returns(Promise.resolve(true))
        assert authorizer.can_manage_security_products?

        authorizer.expects(:async_can_manage_security_products?).once.returns(Promise.resolve(false))
        refute authorizer.can_manage_security_products?
      end
    end
  end

  context "#manage_repo_advanced_security_enablement_blocked_by_policy?" do
    context "when the subject is not part of a business", skip_enterprise: true, skip_with_all_emus: true do
      test "returns false" do
        Business.any_instance.expects(:repo_admins_can_modify_advanced_security_enablement?).never

        [@org_repo, @user_repo].each do |r|
          each_user(
            @biz_owner                  => false,
            @owner                      => false,
            @owner_repo_admin           => false,
            @security_manager           => false,
            @inherited_security_manager => false,
            @member_repo_admin          => false,
            @member                     => false,
            @collaborator               => false,
            @pending_collaborator       => false,
            @rando                      => false,
            nil                         => false,
          ) do |u, expected|
            authz = SecurityProduct::Permissions::RepoAuthz.new(r.reload, actor: u)
            assert_equal expected, authz.manage_repo_advanced_security_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}, Repo: #{r.name}"
          end
        end
      end
    end

    context "when the subject is part of a business" do
      context "in dotcom", skip_enterprise: true do
        context "when the business policy allows repo admins to modify GHAS enablement" do
          test "returns false for org-owned repos" do
            @biz.allow_repo_admins_to_modify_advanced_security_enablement(actor: @biz_owner)

            each_user(
              @biz_owner                  => false,
              @owner                      => false,
              @owner_repo_admin           => false,
              @security_manager           => false,
              @inherited_security_manager => false,
              @member_repo_admin          => false,
              @member                     => false,
              @collaborator               => false,
              @pending_collaborator       => false,
              @rando                      => false,
              nil                         => false,
            ) do |u, expected|
              authz = SecurityProduct::Permissions::RepoAuthz.new(@biz_org_repo.reload, actor: u)
              assert_equal expected, authz.manage_repo_advanced_security_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}"
            end
          end

          test "returns false for emu-owned repos" do
            @emu_biz.allow_repo_admins_to_modify_advanced_security_enablement(actor: @emu_biz_owner)

            @emu_biz.mark_advanced_security_as_purchased_for_entity(actor: @emu_admin)
            @emu_biz.set_advanced_security_seats_for_entity(actor: @emu_admin, seats: 10)

            each_emu(
              @emu_admin      => false,
              @emu_biz_owner  => false,
              @emu_biz_member => false,
              nil             => false,
            ) do |u, expected|
              authz = SecurityProduct::Permissions::RepoAuthz.new(@emu_repo.reload, actor: u)
              assert_equal expected, authz.manage_repo_advanced_security_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}"
            end
          end
        end

        context "when the business policy disallows repo admins to modify GHAS enablement" do
          test "returns true for repo admins of org-owned repos" do
            @biz.disallow_repo_admins_to_modify_advanced_security_enablement(actor: @biz_owner)

            each_user(
              @biz_owner                  => false,
              @owner                      => false,
              @owner_repo_admin           => false,
              @security_manager           => false,
              @inherited_security_manager => false,
              @member_repo_admin          => true,
              @member                     => false,
              @collaborator               => false,
              @pending_collaborator       => false,
              @rando                      => false,
              nil                         => false,
            ) do |u, expected|
              authz = SecurityProduct::Permissions::RepoAuthz.new(@biz_org_repo.reload, actor: u)
              assert_equal expected, authz.manage_repo_advanced_security_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}"
            end
          end

          test "returns true for repo admins of emu-owned repos" do
            @emu_biz.disallow_repo_admins_to_modify_advanced_security_enablement(actor: @emu_biz_owner)

            @emu_biz.mark_advanced_security_as_purchased_for_entity(actor: @emu_admin)
            @emu_biz.set_advanced_security_seats_for_entity(actor: @emu_admin, seats: 10)

            each_emu(
              @emu_admin      => false,
              @emu_biz_owner  => false,
              @emu_biz_member => true,
              nil             => false,
            ) do |u, expected|
              authz = SecurityProduct::Permissions::RepoAuthz.new(@emu_repo.reload, actor: u)
              assert_equal expected, authz.manage_repo_advanced_security_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}"
            end
          end
        end
      end

      context "in GHES", enterprise_only: true do
        context "when the business policy allows repo admins to modify GHAS enablement" do
          test "returns false" do
            @biz.allow_repo_admins_to_modify_advanced_security_enablement(actor: @biz_owner)

            GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
            GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
            GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)

            [@biz_org_repo, @user_repo].each do |r|
              each_user(
                @biz_owner                  => false,
                @owner                      => false,
                @owner_repo_admin           => false,
                @security_manager           => false,
                @inherited_security_manager => false,
                @member_repo_admin          => false,
                @member                     => false,
                @collaborator               => false,
                @pending_collaborator       => false,
                @rando                      => false,
                nil                         => false,
              ) do |u, expected|
                authz = SecurityProduct::Permissions::RepoAuthz.new(r.reload, actor: u)
                assert_equal expected, authz.manage_repo_advanced_security_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}, Repo: #{r.name}"
              end
            end
          end
        end

        context "when the business policy disallows repo admins to modify GHAS enablement" do
          test "returns expected values for different users when the subject is a user-owned repo" do
            @biz.disallow_repo_admins_to_modify_advanced_security_enablement(actor: @biz_owner)

            GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
            GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
            GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)

            {
              @biz_org_repo => {
                @biz_owner                  => false,
                @owner                      => false,
                @owner_repo_admin           => false,
                @security_manager           => false,
                @inherited_security_manager => false,
                @member_repo_admin          => true,
                @member                     => false,
                @collaborator               => false,
                @pending_collaborator       => false,
                @rando                      => false,
                nil                         => false,
              },
              @user_repo => {
                @biz_owner                  => false,
                @owner                      => false,
                @owner_repo_admin           => false,
                @security_manager           => false,
                @inherited_security_manager => false,
                @member_repo_admin          => false,
                @member                     => true,
                @collaborator               => false,
                @pending_collaborator       => false,
                @rando                      => false,
                nil                         => false,
              },
            }.each do |r, expectations|
              each_user(**expectations) do |u, expected|
                authz = SecurityProduct::Permissions::RepoAuthz.new(r.reload, actor: u)
                assert_equal expected, authz.manage_repo_advanced_security_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}, Repo: #{r.name}"
              end
            end
          end
        end
      end
    end
  end

  context "#manage_repo_dependabot_alerts_enablement_blocked_by_policy?" do
    context "when the subject is not part of a business", skip_enterprise: true, skip_with_all_emus: true do
      test "returns false" do
        Business.any_instance.expects(:repo_admins_can_modify_dependabot_alerts_enablement?).never

        [@org_repo, @user_repo].each do |r|
          each_user(
            @biz_owner                  => false,
            @owner                      => false,
            @owner_repo_admin           => false,
            @security_manager           => false,
            @inherited_security_manager => false,
            @member_repo_admin          => false,
            @member                     => false,
            @collaborator               => false,
            @pending_collaborator       => false,
            @rando                      => false,
            nil                         => false,
          ) do |u, expected|
            authz = SecurityProduct::Permissions::RepoAuthz.new(r.reload, actor: u)
            assert_equal expected, authz.manage_repo_dependabot_alerts_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}, Repo: #{r.name}"
          end
        end
      end
    end

    context "when the subject is part of a business" do
      context "in dotcom", skip_enterprise: true do
        context "when the business policy allows repo admins to modify GHAS enablement" do
          test "returns false for org-owned repos" do
            @biz.allow_repo_admins_to_modify_dependabot_alerts_enablement(actor: @biz_owner)

            each_user(
              @biz_owner                  => false,
              @owner                      => false,
              @owner_repo_admin           => false,
              @security_manager           => false,
              @inherited_security_manager => false,
              @member_repo_admin          => false,
              @member                     => false,
              @collaborator               => false,
              @pending_collaborator       => false,
              @rando                      => false,
              nil                         => false,
            ) do |u, expected|
              authz = SecurityProduct::Permissions::RepoAuthz.new(@biz_org_repo.reload, actor: u)
              assert_equal expected, authz.manage_repo_dependabot_alerts_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}"
            end
          end

          test "returns false for emu-owned repos" do
            @emu_biz.allow_repo_admins_to_modify_dependabot_alerts_enablement(actor: @emu_biz_owner)

            @emu_biz.mark_advanced_security_as_purchased_for_entity(actor: @emu_admin)
            @emu_biz.set_advanced_security_seats_for_entity(actor: @emu_admin, seats: 10)

            each_emu(
              @emu_admin      => false,
              @emu_biz_owner  => false,
              @emu_biz_member => false,
              nil             => false,
            ) do |u, expected|
              authz = SecurityProduct::Permissions::RepoAuthz.new(@emu_repo.reload, actor: u)
              assert_equal expected, authz.manage_repo_dependabot_alerts_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}"
            end
          end
        end

        context "when the business policy disallows repo admins to modify GHAS enablement" do
          test "returns true for repo admins of org-owned repos" do
            @biz.disallow_repo_admins_to_modify_dependabot_alerts_enablement(actor: @biz_owner)

            each_user(
              @biz_owner                  => false,
              @owner                      => false,
              @owner_repo_admin           => false,
              @security_manager           => false,
              @inherited_security_manager => false,
              @member_repo_admin          => true,
              @member                     => false,
              @collaborator               => false,
              @pending_collaborator       => false,
              @rando                      => false,
              nil                         => false,
            ) do |u, expected|
              authz = SecurityProduct::Permissions::RepoAuthz.new(@biz_org_repo.reload, actor: u)
              assert_equal expected, authz.manage_repo_dependabot_alerts_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}"
            end
          end

          test "returns true for repo admins of emu-owned repos" do
            @emu_biz.disallow_repo_admins_to_modify_dependabot_alerts_enablement(actor: @emu_biz_owner)

            @emu_biz.mark_advanced_security_as_purchased_for_entity(actor: @emu_admin)
            @emu_biz.set_advanced_security_seats_for_entity(actor: @emu_admin, seats: 10)

            each_emu(
              @emu_admin      => false,
              @emu_biz_owner  => false,
              @emu_biz_member => true,
              nil             => false,
            ) do |u, expected|
              authz = SecurityProduct::Permissions::RepoAuthz.new(@emu_repo.reload, actor: u)
              assert_equal expected, authz.manage_repo_dependabot_alerts_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}"
            end
          end
        end
      end

      context "in GHES", enterprise_only: true do
        context "when the business policy allows repo admins to modify GHAS enablement" do
          test "returns false" do
            @biz.allow_repo_admins_to_modify_dependabot_alerts_enablement(actor: @biz_owner)

            GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
            GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
            GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)

            [@biz_org_repo, @user_repo].each do |r|
              each_user(
                @biz_owner                  => false,
                @owner                      => false,
                @owner_repo_admin           => false,
                @security_manager           => false,
                @inherited_security_manager => false,
                @member_repo_admin          => false,
                @member                     => false,
                @collaborator               => false,
                @pending_collaborator       => false,
                @rando                      => false,
                nil                         => false,
              ) do |u, expected|
                authz = SecurityProduct::Permissions::RepoAuthz.new(r.reload, actor: u)
                assert_equal expected, authz.manage_repo_dependabot_alerts_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}, Repo: #{r.name}"
              end
            end
          end
        end

        context "when the business policy disallows repo admins to modify GHAS enablement" do
          test "returns expected values for different users when the subject is a user-owned repo" do
            @biz.disallow_repo_admins_to_modify_dependabot_alerts_enablement(actor: @biz_owner)

            GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
            GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
            GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)

            {
              @biz_org_repo => {
                @biz_owner                  => false,
                @owner                      => false,
                @owner_repo_admin           => false,
                @security_manager           => false,
                @inherited_security_manager => false,
                @member_repo_admin          => true,
                @member                     => false,
                @collaborator               => false,
                @pending_collaborator       => false,
                @rando                      => false,
                nil                         => false,
              },
              @user_repo => {
                @biz_owner                  => false,
                @owner                      => false,
                @owner_repo_admin           => false,
                @security_manager           => false,
                @inherited_security_manager => false,
                @member_repo_admin          => false,
                @member                     => true,
                @collaborator               => false,
                @pending_collaborator       => false,
                @rando                      => false,
                nil                         => false,
              },
            }.each do |r, expectations|
              each_user(**expectations) do |u, expected|
                authz = SecurityProduct::Permissions::RepoAuthz.new(r.reload, actor: u)
                assert_equal expected, authz.manage_repo_dependabot_alerts_enablement_blocked_by_policy?, "User: #{u&.name || "anon"}, Repo: #{r.name}"
              end
            end
          end
        end
      end
    end
  end

  context "#manage_repo_secret_scanning_settings_blocked_by_policy?" do
    context "when the subject is not part of a business", skip_enterprise: true, skip_with_all_emus: true do
      test "returns false" do
        Business.any_instance.expects(:repo_admins_can_modify_secret_scanning_settings?).never

        [@org_repo, @user_repo].each do |r|
          each_user(
            @biz_owner                  => false,
            @owner                      => false,
            @owner_repo_admin           => false,
            @security_manager           => false,
            @inherited_security_manager => false,
            @member_repo_admin          => false,
            @member                     => false,
            @collaborator               => false,
            @pending_collaborator       => false,
            @rando                      => false,
            nil                         => false,
          ) do |u, expected|
            authz = SecurityProduct::Permissions::RepoAuthz.new(r.reload, actor: u)
            assert_equal expected, authz.manage_repo_secret_scanning_settings_blocked_by_policy?, "User: #{u&.name || "anon"}, Repo: #{r.name}"
          end
        end
      end
    end

    context "when the subject is part of a business" do
      context "in dotcom", skip_enterprise: true do
        context "when the business policy allows repo admins to modify GHAS enablement" do
          test "returns false for org-owned repos" do
            @biz.allow_repo_admins_to_modify_secret_scanning_settings(actor: @biz_owner)

            each_user(
              @biz_owner                  => false,
              @owner                      => false,
              @owner_repo_admin           => false,
              @security_manager           => false,
              @inherited_security_manager => false,
              @member_repo_admin          => false,
              @member                     => false,
              @collaborator               => false,
              @pending_collaborator       => false,
              @rando                      => false,
              nil                         => false,
            ) do |u, expected|
              authz = SecurityProduct::Permissions::RepoAuthz.new(@biz_org_repo.reload, actor: u)
              assert_equal expected, authz.manage_repo_secret_scanning_settings_blocked_by_policy?, "User: #{u&.name || "anon"}"
            end
          end

          test "returns false for emu-owned repos" do
            @emu_biz.allow_repo_admins_to_modify_secret_scanning_settings(actor: @emu_biz_owner)

            @emu_biz.mark_advanced_security_as_purchased_for_entity(actor: @emu_admin)
            @emu_biz.set_advanced_security_seats_for_entity(actor: @emu_admin, seats: 10)

            each_emu(
              @emu_admin      => false,
              @emu_biz_owner  => false,
              @emu_biz_member => false,
              nil             => false,
            ) do |u, expected|
              authz = SecurityProduct::Permissions::RepoAuthz.new(@emu_repo.reload, actor: u)
              assert_equal expected, authz.manage_repo_secret_scanning_settings_blocked_by_policy?, "User: #{u&.name || "anon"}"
            end
          end
        end

        context "when the business policy disallows repo admins to modify GHAS enablement" do
          test "returns true for repo admins of org-owned repos" do
            @biz.disallow_repo_admins_to_modify_secret_scanning_settings(actor: @biz_owner)

            each_user(
              @biz_owner                  => false,
              @owner                      => false,
              @owner_repo_admin           => false,
              @security_manager           => false,
              @inherited_security_manager => false,
              @member_repo_admin          => true,
              @member                     => false,
              @collaborator               => false,
              @pending_collaborator       => false,
              @rando                      => false,
              nil                         => false,
            ) do |u, expected|
              authz = SecurityProduct::Permissions::RepoAuthz.new(@biz_org_repo.reload, actor: u)
              assert_equal expected, authz.manage_repo_secret_scanning_settings_blocked_by_policy?, "User: #{u&.name || "anon"}"
            end
          end

          test "returns true for repo admins of emu-owned repos" do
            @emu_biz.disallow_repo_admins_to_modify_secret_scanning_settings(actor: @emu_biz_owner)

            @emu_biz.mark_advanced_security_as_purchased_for_entity(actor: @emu_admin)
            @emu_biz.set_advanced_security_seats_for_entity(actor: @emu_admin, seats: 10)

            each_emu(
              @emu_admin      => false,
              @emu_biz_owner  => false,
              @emu_biz_member => true,
              nil             => false,
            ) do |u, expected|
              authz = SecurityProduct::Permissions::RepoAuthz.new(@emu_repo.reload, actor: u)
              assert_equal expected, authz.manage_repo_secret_scanning_settings_blocked_by_policy?, "User: #{u&.name || "anon"}"
            end
          end
        end
      end

      context "in GHES", enterprise_only: true do
        context "when the business policy allows repo admins to modify GHAS enablement" do
          test "returns false" do
            @biz.allow_repo_admins_to_modify_secret_scanning_settings(actor: @biz_owner)

            GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
            GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
            GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)

            [@biz_org_repo, @user_repo].each do |r|
              each_user(
                @biz_owner                  => false,
                @owner                      => false,
                @owner_repo_admin           => false,
                @security_manager           => false,
                @inherited_security_manager => false,
                @member_repo_admin          => false,
                @member                     => false,
                @collaborator               => false,
                @pending_collaborator       => false,
                @rando                      => false,
                nil                         => false,
              ) do |u, expected|
                authz = SecurityProduct::Permissions::RepoAuthz.new(r.reload, actor: u)
                assert_equal expected, authz.manage_repo_secret_scanning_settings_blocked_by_policy?, "User: #{u&.name || "anon"}, Repo: #{r.name}"
              end
            end
          end
        end

        context "when the business policy disallows repo admins to modify GHAS enablement" do
          test "returns expected values for different users when the subject is a user-owned repo" do
            @biz.disallow_repo_admins_to_modify_secret_scanning_settings(actor: @biz_owner)

            GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
            GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
            GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)

            {
              @biz_org_repo => {
                @biz_owner                  => false,
                @owner                      => false,
                @owner_repo_admin           => false,
                @security_manager           => false,
                @inherited_security_manager => false,
                @member_repo_admin          => true,
                @member                     => false,
                @collaborator               => false,
                @pending_collaborator       => false,
                @rando                      => false,
                nil                         => false,
              },
              @user_repo => {
                @biz_owner                  => false,
                @owner                      => false,
                @owner_repo_admin           => false,
                @security_manager           => false,
                @inherited_security_manager => false,
                @member_repo_admin          => false,
                @member                     => true,
                @collaborator               => false,
                @pending_collaborator       => false,
                @rando                      => false,
                nil                         => false,
              },
            }.each do |r, expectations|
              each_user(**expectations) do |u, expected|
                authz = SecurityProduct::Permissions::RepoAuthz.new(r.reload, actor: u)
                assert_equal expected, authz.manage_repo_secret_scanning_settings_blocked_by_policy?, "User: #{u&.name || "anon"}, Repo: #{r.name}"
              end
            end
          end
        end
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

  def each_emu(**expectations)
    [*@emu_users, nil].each do |user|
      raise ArgumentError.new "expected result for #{user&.name || "anon"}" unless expectations.key?(user)
      yield user, expectations[user]
    end
  end
end
