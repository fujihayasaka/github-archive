# typed: true
# frozen_string_literal: true

require "test_helper"
class  Businesses::PeopleSidebarComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include GitHub::Memoizer
  include FineGrainedPermissionsTestHelper

  fixtures do
    @user = create :user
    @member = create :user
    @org = create :organization, admins: [@member]
    @business = create :business, owners: [@user], organizations: [@org]
    if TestEnv.test_with_all_emus?
      @user_external_identity = @user.external_identities.first
    end
  end

  test "renders a people sidebar" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :people,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("people-sidebar")
  end

  context "Members link" do
    test "Renders when owner" do
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 1,
      )
      assert_test_selector("people-sidebar")
      assert_selector("a", text: "Members") do |link|
        assert_equal urls.people_enterprise_path(@business), link[:href]
      end
    end

    test "Renders when user with read_enterprise_admins_and_members" do
      enable_feature_flag(:custom_enterprise_role_feature, @business)
      enable_feature_flag(:support_enterprise_admins_and_members, @business)
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_admins_and_members])

      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @member,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 4,
      )
      assert_test_selector("people-sidebar")
      assert_selector("a", text: "Members") do |link|
        assert_equal urls.people_enterprise_path(@business), link[:href]
      end
    end

    test "Does not render for user with read_enterprise_admins_and_members with support_enterprise_admins_and_members ff disabled" do
      enable_feature_flag(:custom_enterprise_role_feature, @business)
      disable_feature_flag(:support_enterprise_admins_and_members, @business)
      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_admins_and_members])

      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @member,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 4,
      )
      assert_test_selector("people-sidebar")
      refute_selector("a", text: "Members")
    end
  end

  test "Administrators link" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :people,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("people-sidebar")
    assert_selector("a", text: "Administrators") do |link|
      assert_equal urls.enterprise_admins_path(@business.slug), link[:href]
    end
  end

  context "Outside collaborators link" do
    test "Renders when owner" do
      enable_feature_flag(:repository_collaborators_for_emu, @business)
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 1,
      )
      assert_test_selector("people-sidebar")
      if TestEnv.test_with_all_emus?
        assert_selector("a", text: "Repository collaborators") do |link|
          assert_equal urls.enterprise_outside_collaborators_path(@business), link[:href]
        end
      else
        assert_selector("a", text: "Outside collaborators") do |link|
          assert_equal urls.enterprise_outside_collaborators_path(@business), link[:href]
        end
      end
    end

    test "renders for member with read enterprise members permission" do
      Business.any_instance.stubs(:actor_can_read_members?).returns(true)
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @member,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 4,
      )
      assert_test_selector("people-sidebar")
      if TestEnv.test_with_all_emus?
        assert_selector("a", text: "Repository collaborators") do |link|
          assert_equal urls.enterprise_outside_collaborators_path(@business), link[:href]
        end
      else
        assert_selector("a", text: "Outside collaborators") do |link|
          assert_equal urls.enterprise_outside_collaborators_path(@business), link[:href]
        end
      end
    end

    test "does not appear when member does not have permissions" do
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @member,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 4,
      )
      assert_test_selector("people-sidebar")
      if TestEnv.test_with_all_emus?
        refute_selector("a", text: "Repository collaborators")
      else
        refute_selector("a", text: "Outside collaborators")
      end
    end
  end

  context "Suspended members link" do
    test "Render when owner" do
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 1,
      )
      assert_test_selector("people-sidebar")
      assert_selector("a", text: "Suspended") do |link|
        assert_equal urls.enterprise_suspended_members_path(@business), link[:href]
      end
    end

    test "Renders with member with read_enterprise_admins_and_members" do
      enable_feature_flag(:custom_enterprise_role_feature, @business)
      enable_feature_flag(:support_enterprise_admins_and_members, @business)

      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_admins_and_members])

      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @member,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 4,
      )
      assert_test_selector("people-sidebar")
      assert_selector("a", text: "Suspended") do |link|
        assert_equal urls.enterprise_suspended_members_path(@business), link[:href]
      end
    end

    test "Does not appear when member does not have read_enterprise_admins_and_members" do
      enable_feature_flag(:custom_enterprise_role_feature, @business)
      enable_feature_flag(:support_enterprise_admins_and_members, @business)

      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @member,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 4,
      )
      assert_test_selector("people-sidebar")
      refute_selector("a", text: "Suspended") do |link|
        assert_equal urls.enterprise_suspended_members_path(@business), link[:href]
      end
    end

    test "Does not appear when member has read_enterprise_admins_and_members but read_enterprise_admins_and_members ff is disabled" do
      enable_feature_flag(:custom_enterprise_role_feature, @business)
      disable_feature_flag(:support_enterprise_admins_and_members, @business)

      grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_admins_and_members])

      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @member,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 4,
      )
      assert_test_selector("people-sidebar")
      refute_selector("a", text: "Suspended") do |link|
        assert_equal urls.enterprise_suspended_members_path(@business), link[:href]
      end
    end
  end if TestEnv.test_with_all_emus?

  test "Organization roles link" do
    enable_feature_flag(:enterprise_custom_organization_roles, @business)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :people,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("people-sidebar")
    assert_selector("a", text: "Organization roles") do |link|
      assert_equal urls.enterprise_organization_roles_path(@business), link[:href]
    end
  end

  test "Enterprise roles link" do
    enable_feature_flag(:custom_enterprise_role_feature, @business)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :people,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("people-sidebar")
    assert_selector("a", text: "Role management") do |link|
      assert_equal urls.enterprise_roles_path(@business), link[:href]
    end
    assert_selector("a", text: "Role assignments") do |link|
      assert_equal urls.enterprise_role_assignments_path(@business), link[:href]
    end
  end

  if !GitHub.single_business_environment? && !GitHub.multi_tenant_enterprise?
    test "Invitations link", skip_with_all_emus: true do
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 1,
      )
      assert_test_selector("people-sidebar")
      assert_selector("a", text: "Invitations") do |link|
        assert_equal urls. enterprise_pending_members_path(@business), link[:href]
      end
    end

    test "Failed invitations link", skip_with_all_emus: true do
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 1,
      )
      assert_test_selector("people-sidebar")
      assert_selector("a", text: "Failed invitations") do |link|
        assert_equal urls.enterprise_failed_invitations_path(@business.slug), link[:href]
      end
    end

    test "Enterprise teams link", skip_with_all_emus: true do
      business = create :business, seats_plan_type: :basic
      user = business.owners.first
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: user,
          business: business,
          sidebar_section: :people,
        ),
        allowed_queries: 1,
      )
      assert_test_selector("people-sidebar")
      assert_selector("a", text: "Enterprise teams") do |link|
        assert_equal urls.enterprise_teams_path(business.slug), link[:href]
      end
    end
  end

  if GitHub.multi_tenant_enterprise?
    test "Security managers link" do
      enable_feature_flag(:enterprise_teams_security_manager_sync, @business)
      enable_feature_flag(:enterprise_teams_enabled_for_organizations, @business)
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 1,
      )
      assert_test_selector("people-sidebar")
      assert_selector("a", text: "Security managers") do |link|
        assert_equal urls.enterprise_security_managers_path(@business), link[:href]
      end
    end
  end

  sig { returns(UrlHelpers) }
  memoize def urls
    T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
  end
end
