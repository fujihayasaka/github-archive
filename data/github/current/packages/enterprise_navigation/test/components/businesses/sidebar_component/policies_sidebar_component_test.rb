
# typed: true
# frozen_string_literal: true

require "test_helper"
class  Businesses::PoliciesSidebarComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include GitHub::Memoizer

  fixtures do
    @user = create(:user)
    @member = create(:user)
    @business = create(:business, owners: [@user])
    @organization = create(:organization)
  end

  setup do
    @organization.add_member(@member)

    @business.add_organization(@organization)
  end

  if !GitHub.single_or_multi_tenant_enterprise?
    test "does not render when enterprise is downgraded to free plan" do
      @business.update! trial_expires_at: GitHub::Billing.now, downgraded_at: GitHub::Billing.now
      @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
      @business.reload
      assert_predicate @business, :trial?
      assert_predicate @business, :downgraded_to_free_plan?

      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :policies,
        ),
        allowed_queries: 4,
      )
      refute_test_selector("policies-sidebar")
    end
  end

  test "non-enterprise admins see limited links" do
    # the checks are more involved to setup tests, so just stub for consistency
    Businesses::GlobalSidebarComponent.any_instance.stubs(:show_code_security_policies_menu_item?).returns(true)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @member,
        business: @business,
        sidebar_section: :policies,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("policies-sidebar")
    assert_selector("a", count: 1)
    assert_selector("a", text: "Advanced Security") do |link|
      assert_equal urls.settings_security_analysis_policies_enterprise_path(@business), link[:href]
    end
  end

  test "renders a policies sidebar" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :policies,
      ),
      allowed_queries: 3,
    )
    assert_test_selector("policies-sidebar")
  end

  test "Repository" do
    enable_feature_flag(:enterprise_rulesets, @business)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :policies,
      ),
      allowed_queries: 3,
    )
    assert_test_selector("policies-sidebar")
    assert_selector("a", text: "Repository") do |link|
      assert_equal urls.settings_repository_policies_enterprise_path(@business), link[:href]
    end
  end

  test "Code" do
    enable_feature_flag(:enterprise_rulesets, @business)
    enable_feature_flag(:enterprise_code_rulesets, @business)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :policies,
      ),
      allowed_queries: 3,
    )
    assert_test_selector("policies-sidebar")
    assert_selector("a", text: "Code") do |link|
      assert_equal urls.settings_code_rules_enterprise_path(@business), link[:href]
    end
  end

  test "Code insights" do
    enable_feature_flag(:enterprise_rulesets, @business)
    enable_feature_flag(:enterprise_code_rulesets, @business)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :policies,
      ),
      allowed_queries: 3,
    )
    assert_test_selector("policies-sidebar")
    assert_selector("a", text: "Code insights") do |link|
      assert_equal urls.settings_code_rule_insights_enterprise_path(@business), link[:href]
    end
  end

  test "Code ruleset bypasses" do
    enable_feature_flag(:enterprise_rulesets, @business)
    enable_feature_flag(:enterprise_code_rulesets, @business)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :policies,
      ),
      allowed_queries: 3,
    )
    assert_test_selector("policies-sidebar")
    assert_selector("a", text: "Code ruleset bypasses") do |link|
      assert_equal urls.settings_code_rules_bypass_requests_enterprise_path(@business), link[:href]
    end
  end

  test "Custom properties" do
    enable_feature_flag(:enterprise_custom_properties, @business)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :policies,
      ),
      allowed_queries: 3,
    )
    assert_test_selector("policies-sidebar")
    assert_selector("a", text: "Custom properties") do |link|
      assert_equal urls.settings_custom_properties_enterprise_path(@business), link[:href]
    end
  end

  test "Member privileges" do
    enable_feature_flag(:enterprise_custom_properties, @business)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :policies,
      ),
      allowed_queries: 3,
    )
    assert_test_selector("policies-sidebar")
    assert_selector("a", text: "Member privileges") do |link|
      assert_equal urls.settings_member_privileges_enterprise_path(@business), link[:href]
    end
  end

  if !GitHub.single_or_multi_tenant_enterprise?
    test "Codespaces" do
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :policies,
        ),
        allowed_queries: 3,
      )
      assert_test_selector("policies-sidebar")
      assert_selector("a", text: "Codespaces") do |link|
        assert_equal urls.settings_codespaces_enterprise_path(@business), link[:href]
      end
    end
  end

  if GitHub.copilot_enabled?
    context "Copilot" do
      test "Copilot settings link in active trial" do
        @business.update! trial_expires_at: ::Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
        @business.reload
        trial = ::Copilot::BusinessTrial.create_trial!(@organization,
          @organization.admins.first,
          trial_length: 10,
          )
        trial.start_trial!
        assert @business.trial?
        assert @business.has_ongoing_copilot_business_trial?
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @user,
            business: @business,
            sidebar_section: :policies,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("policies-sidebar")
        assert_selector("a", text: "Copilot") do |link|
          assert_equal urls.settings_copilot_enterprise_path(@business), link[:href]
        end
      end

      test "does not render copilot when GHEC trial and copilot trial is not active" do
        @business.update! trial_expires_at: ::Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
        @business.reload
        assert @business.trial?
        refute @business.has_ongoing_copilot_business_trial?
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @user,
            business: @business,
            sidebar_section: :policies,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("policies-sidebar")
        refute_test_selector("a", text: "Copilot")
      end

      test "Copilot link appears for basic enterprise", skip_with_all_emus: true, skip_enterprise: true, skip_in_multitenant_mode: true do
        business = create :business, seats_plan_type: :basic
        Copilot::Business.new(business).enable_copilot!
        user = business.owners.first
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: user,
            business: business,
            sidebar_section: :policies,
          ),
          allowed_queries: 2,
        )
        assert_test_selector("policies-sidebar")
        assert_selector("a", text: "Copilot") do |link|
          assert_equal urls.settings_copilot_enterprise_path(business), link[:href]
        end
      end
    end
  end

  if GitHub.actions_enabled?
    test "Actions" do
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :policies,
        ),
        allowed_queries: 3,
      )
      assert_test_selector("policies-sidebar")
      assert_selector("a", text: "Actions") do |link|
        assert_equal urls.settings_actions_enterprise_path(@business), link[:href]
      end
    end
  end

  test "Hosted compute networking", skip_enterprise: true do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :policies,
      ),
      allowed_queries: 3,
    )
    assert_test_selector("policies-sidebar")
    assert_selector("a", text: "Hosted compute networking") do |link|
      assert_equal urls.enterprise_hosted_compute_networking_path(@business), link[:href]
    end
  end

  test "Projects" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :policies,
      ),
      allowed_queries: 3,
    )
    assert_test_selector("policies-sidebar")
    assert_selector("a", text: "Projects") do |link|
      assert_equal urls.settings_projects_enterprise_path(@business), link[:href]
    end
  end

  test "GHES options", enterprise_only: true do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :policies,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("policies-sidebar")
    assert_selector("a", text: "Options") do |link|
      assert_equal urls.enterprise_admin_center_options_path(@business), link[:href]
    end
  end

  test "Code security" do
    # the checks are more involved to setup tests, so just stub for consistency
    Businesses::GlobalSidebarComponent.any_instance.stubs(:show_code_security_policies_menu_item?).returns(true)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :policies,
      ),
      allowed_queries: 2,
    )
    assert_test_selector("policies-sidebar")
    assert_selector("a", text: "Advanced Security") do |link|
      assert_equal urls.settings_security_analysis_policies_enterprise_path(@business), link[:href]
    end
  end

  if GitHub.patsv2_enabled?
    test "Personal access tokens" do
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :policies,
        ),
        allowed_queries: 3,
      )
      assert_test_selector("policies-sidebar")
      assert_selector("a", text: "Personal access tokens") do |link|
        assert_equal urls.settings_personal_access_tokens_enterprise_path(@business), link[:href]
      end
    end
  end

  if GitHub.sponsors_enabled?
    test "Sponsors" do
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :policies,
        ),
        allowed_queries: 3,
      )
      assert_test_selector("policies-sidebar")
      assert_selector("a", text: "Sponsors") do |link|
        assert_equal urls.settings_sponsors_enterprise_path(@business), link[:href]
      end
    end
  end

  if TestEnv.test_with_all_emus?
    test "Models" do
      refute @business.copilot_licensing_enabled?
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :policies,
        ),
        allowed_queries: 1,
      )
      assert_test_selector("policies-sidebar")
      assert_selector("a", text: "Models") do |link|
        assert_equal urls.settings_models_enterprise_path(@business), link[:href]
      end
    end
  end

  sig { returns(UrlHelpers) }
  memoize def urls
    T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
  end
end
