# typed: true
# frozen_string_literal: true

require "test_helper"

class Azure::SubscriptionSelectionDialogComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @owner = create :user, login: "admin-user"
    @customer = create(:customer)
    @org = create(:organization, admin: @owner, customer: @customer)

    @subscriptions = [
      {
        subscription_id: "sub-123",
        display_name: "Basic",
        selected: true,
      },
      {
        subscription_id: "sub-856",
        display_name: "Not so basic",
        selected: false,
      },
    ]
  end

  setup do
    @dialog = Azure::SubscriptionSelectionDialogComponent.new(@org, @subscriptions, false)
  end

  test "renders the dialog with subscriptions" do
    as @owner

    render_inline(@dialog)

    assert_text "Connect Azure subscription"

    assert_selector "label", text: "Basic"
    assert_selector "label", text: "Not so basic"
  end

  test "renders the dialog with confirm checkbox hidden" do
    as @owner

    dialog = Azure::SubscriptionSelectionDialogComponent.new(@org, [], false)
    render_inline(dialog)

    assert_selector "input", id: "confirm_subscription_selection", visible: false
  end

  test "renders the dialog with confirm checkbox disabled" do
    as @owner

    unselected_subscription = {
      subscription_id: "123456",
      display_name: "Test subscription",
      selected: false
    }

    dialog = Azure::SubscriptionSelectionDialogComponent.new(@org, [unselected_subscription], false)
    render_inline(dialog)

    assert_selector "input", id: "confirm_subscription_selection", visible: true do |input|
      assert input.disabled?
    end
  end

  test "renders the dialog with confirm checkbox enabled" do
    as @owner

    render_inline(@dialog)

    assert_selector "input", id: "confirm_subscription_selection", visible: true do |input|
      refute input.disabled?
    end
    assert_selector "input[type=submit]", visible: true do |input|
      assert input.disabled?
    end
  end

  test "renders the dialog with an error message when fetch failed" do
    as @owner

    dialog = Azure::SubscriptionSelectionDialogComponent.new(@org, @subscriptions, true)
    render_inline(dialog)

    assert_text "Failed to fetch subscriptions"

    refute_text "Basic"
    refute_text "Not so basic"
  end

  test "renders the dialog with an error message when there are no subscriptions" do
    as @owner

    dialog = Azure::SubscriptionSelectionDialogComponent.new(@org, [], false)
    render_inline(dialog)

    assert_text "No subscriptions found."

    refute_text "Basic"
    refute_text "Not so basic"
  end
end if GitHub.billing_enabled?
