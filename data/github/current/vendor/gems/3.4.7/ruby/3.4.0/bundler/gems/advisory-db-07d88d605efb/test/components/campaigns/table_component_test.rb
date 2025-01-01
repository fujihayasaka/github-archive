# frozen_string_literal: true

require "test_helper"

class CampaignsTableComponentTest < ViewComponent::TestCase
  test "renders empty" do
    render_inline(Campaigns::TableComponent.new(campaigns: []))
    assert_selector "[data-test-selector=campaign-row]", count: 0
    assert_selector "[data-test-selector=no-campaigns]", count: 1
  end

  test "renders rows" do
    campaigns = create_list(:campaign, 10)
    render_inline(Campaigns::TableComponent.new(campaigns: campaigns))
    assert_selector "[data-test-selector=campaign-row]", count: 10
    assert_selector "[data-test-selector=no-campaign]", count: 0
  end
end
