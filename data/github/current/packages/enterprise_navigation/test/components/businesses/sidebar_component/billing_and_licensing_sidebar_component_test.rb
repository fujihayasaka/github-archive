# typed: true
# frozen_string_literal: true

require "test_helper"

class Businesses::BillingAndLicensingSidebarComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include GitHub::Memoizer

  fixtures do
    @user = create(:user)
    @business = create(:business, owners: [@user])
    Billing::Public::Budgets::Permission.stubs(:new).returns(mock("Permission"))
  end

  setup do
    @business.customer.update!(metered_plan: true, billed_via_billing_platform: true)
  end

  test "renders a billing and licensing sidebar", skip_enterprise: true do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :billing_and_licensing,
      ),
      allowed_queries: 7,
    )
    assert_test_selector("billing-and-licensing-sidebar")
  end

  test "Overview link", skip_enterprise: true do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :billing_and_licensing,
      ),
      allowed_queries: 7,
    )
    assert_test_selector("billing-and-licensing-sidebar")
    assert_selector("a", text: "Overview") do |link|
      assert_equal urls.enterprise_billing_path(@business), link[:href]
    end
  end

  test "Usage link", skip_enterprise: true do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :billing_and_licensing,
      ),
      allowed_queries: 7,
    )
    assert_test_selector("billing-and-licensing-sidebar")
    assert_selector("a", text: "Usage") do |link|
      assert_equal urls.enterprise_billing_usage_path(@business), link[:href]
    end
  end

  test "Cost centers link", skip_enterprise: true do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :billing_and_licensing,
      ),
      allowed_queries: 7,
    )
    assert_test_selector("billing-and-licensing-sidebar")
    assert_selector("a", text: "Cost centers") do |link|
      assert_equal urls.enterprise_billing_cost_centers_path(@business), link[:href]
    end
  end

  test "Budgets and alerts link", skip_enterprise: true do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :billing_and_licensing,
      ),
      allowed_queries: 7,
    )
    assert_test_selector("billing-and-licensing-sidebar")
    assert_selector("a", text: "Budgets and alerts") do |link|
      assert_equal urls.enterprise_billing_budgets_path(@business), link[:href]
    end
  end

  unless GitHub.enterprise?
    test "Licensing link" do
      @business.customer.update!(billed_via_billing_platform: true)
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :billing_and_licensing,
        ),
        allowed_queries: 7,
      )
      assert_test_selector("billing-and-licensing-sidebar")
      assert_selector("a", text: "Licensing") do |link|
        assert_equal urls.enterprise_licensing_path(@business), link[:href]
      end
    end

    test "Payment information link" do
      @business.customer.update!(billed_via_billing_platform: true)
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :billing_and_licensing,
        ),
        allowed_queries: 7,
      )
      assert_test_selector("billing-and-licensing-sidebar")
      assert_selector("a", text: "Payment information") do |link|
        assert_equal urls.enterprise_billing_payment_information_path(@business), link[:href]
      end
    end

    test "Payment history link" do
      @business.stubs(:invoiced?).returns(false)
      @business.customer.update!(billed_via_billing_platform: true)
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :billing_and_licensing,
        ),
        allowed_queries: 7,
      )
      assert_test_selector("billing-and-licensing-sidebar")
      assert_selector("a", text: "Payment history") do |link|
        assert_equal urls.enterprise_billing_payment_history_index_path(@business), link[:href]
      end
    end

    test "Past invoices link" do
      @business.customer.update!(billed_via_billing_platform: true)
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :billing_and_licensing,
        ),
        allowed_queries: 7,
      )
      assert_test_selector("billing-and-licensing-sidebar")
      assert_selector("a", text: "Past invoices") do |link|
        assert_equal urls.enterprise_billing_past_invoices_path(@business), link[:href]
      end
    end

    test "Billing contacts link" do
      @business.customer.update!(billed_via_billing_platform: true)
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :billing_and_licensing,
        ),
        allowed_queries: 7,
      )
      assert_test_selector("billing-and-licensing-sidebar")
      assert_selector("a", text: "Billing contacts") do |link|
        assert_equal urls.enterprise_billing_contacts_path(@business), link[:href]
      end
    end

    test "Marketplace apps link" do
      @business.customer.update!(billed_via_billing_platform: true)
      actual_permission = Billing::Public::Budgets::Permission.new(@business, @user)
      Billing::Public::Budgets::Permission.stubs(:new).returns(actual_permission)
      actual_permission.stubs(:show_marketplace_apps_tab?).returns(true)

      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :billing_and_licensing,
        ),
        allowed_queries: 6,
      )
      assert_test_selector("billing-and-licensing-sidebar")
      assert_selector("a", text: "Marketplace apps") do |link|
        assert_equal urls.enterprise_billing_marketplace_apps_path(@business), link[:href]
      end
    end

    test "Sponsorships link" do
      @business.customer.update!(billed_via_billing_platform: true)
      actual_permission = Billing::Public::Budgets::Permission.new(@business, @user)
      Billing::Public::Budgets::Permission.stubs(:new).returns(actual_permission)
      actual_permission.stubs(:show_sponsorships_tab?).returns(true)

      @business.customer.update!(billed_via_billing_platform: true)
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :billing_and_licensing,
        ),
        allowed_queries: 6,
      )
      assert_test_selector("billing-and-licensing-sidebar")
      assert_selector("a", text: "Sponsorships") do |link|
        assert_equal urls.enterprise_billing_sponsorships_path(@business), link[:href]
      end
    end
  end


  sig { returns(UrlHelpers) }
  memoize def urls
    T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
  end
end
