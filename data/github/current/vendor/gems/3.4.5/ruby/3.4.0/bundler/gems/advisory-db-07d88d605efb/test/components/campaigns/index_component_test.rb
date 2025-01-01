# frozen_string_literal: true

require "test_helper"

class CampaignsIndexComponentTest < ViewComponent::TestCase
  test "lists campaigns" do
    component = Campaigns::IndexComponent.new(sort: nil, status: nil, page: nil)
    assert_equal 0, component.campaigns.length

    # open campaigns to be rendered
    create(:campaign)

    component = Campaigns::IndexComponent.new(sort: nil, status: nil, page: nil)
    assert_equal 1, component.campaigns.length
  end

  test "paginates campaigns" do
    create_list(:campaign, 35)

    component = Campaigns::IndexComponent.new(sort: nil, status: nil, page: nil)
    assert_equal 30, component.campaigns.length

    component = Campaigns::IndexComponent.new(sort: nil, status: nil, page: 2)
    assert_equal 5, component.campaigns.length
  end

  test "sorts campaigns" do
    create(:campaign, created_at: 2.days.ago, name: "older campaign")
    create(:campaign, created_at: 1.day.ago, name: "newer campaign")

    component = Campaigns::IndexComponent.new(sort: nil, status: nil, page: nil)
    assert_equal "newer campaign", component.campaigns.first.name
    assert_equal "older campaign", component.campaigns.last.name

    component = Campaigns::IndexComponent.new(sort: "asc", status: nil, page: nil)
    assert_equal "older campaign", component.campaigns.first.name
    assert_equal "newer campaign", component.campaigns.last.name
  end

  test "filters campaigns by status" do
    active_campaign = create(:campaign)
    complete_campaign = create(:campaign, :complete)

    component = Campaigns::IndexComponent.new(sort: nil, status: nil, page: nil)
    assert_includes component.campaigns, active_campaign
    refute_includes component.campaigns, complete_campaign

    component = Campaigns::IndexComponent.new(sort: nil, status: "complete", page: nil)
    assert_includes component.campaigns, complete_campaign
    refute_includes component.campaigns, active_campaign
  end
end
