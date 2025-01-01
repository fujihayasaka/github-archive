# typed: true
# frozen_string_literal: true

require "test_helper"

class Azure::TenantSelectionDialogComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @owner = create :user, login: "admin-user"
    @customer = create(:customer)
    @org = create(:organization, admin: @owner, customer: @customer)

    @tenants = [
      {
        tenant_id: "123",
        display_name: "Fake Inc",
        redirect_url: "https://example.com",
      },
      {
        tenant_id: "456",
        display_name: "ACME Inc",
        redirect_url: "https://example.com",
      },
    ]
  end

  setup do
    @component = Azure::TenantSelectionDialogComponent.new(@org, @tenants, false)
  end

  test "renders the component" do
    render_inline(@component)

    assert_text "Select Azure Tenant"
    assert_text "Fake Inc"
    assert_text "ACME Inc"
  end

  test "renders the component with an error message when fetch failed" do
    component = Azure::TenantSelectionDialogComponent.new(@org, @tenants, true)
    render_inline(component)

    assert_text "Failed to fetch tenants."
    refute_text "Fake Inc"
    refute_text "ACME Inc"

    assert_selector "button", text: "Connect", visible: true do |input|
      assert input.disabled?
    end
  end

  test "renders the component with an error message when there are not tenants" do
    component = Azure::TenantSelectionDialogComponent.new(@org, [], false)
    render_inline(component)

    assert_text "No tenants found."
    refute_text "Fake Inc"
    refute_text "ACME Inc"

    assert_selector "button", text: "Connect", visible: true do |input|
      assert input.disabled?
    end
  end
end if GitHub.billing_enabled?
