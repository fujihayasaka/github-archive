# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaigns::SecurityCampaignTest < GitHub::TestCase
  fixtures do
    @owner = create(:paid_user)
    @org = create(:organization, admin: @owner)
  end

  context "number" do
    test "number starts at 1 for a new org" do
      campaign = create(:security_campaign, organization: @org)
      assert_equal 1, campaign.number
    end

    test "number increments when multiple campaigns are created" do
      campaign1 = create(:security_campaign, organization: @org)
      campaign2 = create(:security_campaign, organization: @org)
      campaign3 = create(:security_campaign, organization: @org)
      assert_equal 1, campaign1.number
      assert_equal 2, campaign2.number
      assert_equal 3, campaign3.number
    end

    test "number sequences are scoped to the organization" do
      org2 = create(:organization, admin: @owner)

      campaign1 = create(:security_campaign, organization: @org)
      campaign2 = create(:security_campaign, organization: @org)

      campaign3 = create(:security_campaign, organization: org2)
      campaign4 = create(:security_campaign, organization: org2)

      assert_equal 1, campaign3.number
      assert_equal 2, campaign4.number
    end
  end

  test "open scope only returns open campaigns" do
    open_campaigns = create_list(:security_campaign, 2, organization: @org)
    create(:security_campaign, organization: @org, published_at: Time.now, closed_at: Time.now)

    assert_equal open_campaigns.map(&:id).sort, SecurityCampaigns::SecurityCampaign.open.map(&:id).sort
  end

  test "closed scope only returns closed campaigns" do
    create_list(:security_campaign, 2, organization: @org)
    closed_campaigns = create_list(:security_campaign, 2, organization: @org, published_at: Time.now, closed_at: Time.now)

    assert_equal closed_campaigns.map(&:id).sort, SecurityCampaigns::SecurityCampaign.closed.map(&:id).sort
  end

  test "description must be set if published_at is not null" do
    campaign = build(:security_campaign, organization: @org, published_at: Time.now, description: nil)
    refute campaign.valid?
    assert_includes campaign.errors[:description], "can't be blank"
  end

  test "ends_at must be set if published_at is not null" do
    campaign = build(:security_campaign, organization: @org, published_at: Time.now, ends_at: nil)
    refute campaign.valid?
    assert_includes campaign.errors[:ends_at], "can't be blank"
  end

  test "closed_at must not be set if published_at is null" do
    campaign = build(:security_campaign, organization: @org, published_at: nil, closed_at: Time.now)
    refute campaign.valid?
    assert_includes campaign.errors[:closed_at], "must be blank"
  end

  test "creation_query must be set if published_at is null" do
    campaign = build(:security_campaign, :draft, organization: @org, creation_query: nil)
    refute campaign.valid?
    assert_includes campaign.errors[:creation_query], "can't be blank"
  end

  test "state is closed if closed_at is set" do
    campaign = create(:security_campaign, organization: @org, closed_at: Time.now)
    assert_equal :closed, campaign.state
  end

  test "state is draft if published_at is not set" do
    campaign = create(:security_campaign, organization: @org, published_at: nil)
    assert_equal :draft, campaign.state
  end

  test "state is open if published_at is set and closed_at is not set" do
    campaign = create(:security_campaign, organization: @org, published_at: Time.now, closed_at: nil)
    assert_equal :open, campaign.state
  end
end
