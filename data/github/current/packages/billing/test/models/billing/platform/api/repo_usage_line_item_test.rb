# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Platform::Api::RepoUsageLineItemTest < GitHub::TestCase
  fixtures do
    @org = create(:organization, name: "github")
    @repository = create(:repository, owner: @org, name: "server")
  end

  def build_raw_line_item(time)
    {
      billedAmount: 100,
      quantity: 1,
      usageAt: time,
      product: "actions"
    }
  end

  context "#to_json" do
    test "returns expected json" do
      Timecop.freeze("2025-08-24 00:01:00Z") do
        now = Time.now.utc.to_i
        raw_repo_usage_line_item_data = build_raw_line_item(now)

        repo_usage_line_item = Billing::Platform::Api::RepoUsageLineItem.new(raw_repo_usage_line_item_data, @org, @repository)

        expected_json = {
          billedAmount: 100,
          quantity: 1,
          product: "actions",
          repo: {
            name: "server"
          },
          org: {
            name: "github",
            avatarSrc: "http://alambic.github.test/avatars/u/#{@org.id}?b=1&s=16&v=2",
          },
          usageAt: Time.at(0, now, :millisecond).utc
        }

        assert_equal repo_usage_line_item.to_json, expected_json
      end
    end

    test "returns placeholder repo info if repo does not exist" do
      now = Time.now.utc.to_i
      raw_repo_usage_line_item_data = build_raw_line_item(now)

      repo_usage_line_item = Billing::Platform::Api::RepoUsageLineItem.new(raw_repo_usage_line_item_data, @org, nil)

      assert_equal repo_usage_line_item.to_json[:repo][:name], "Deleted Repository"
    end

    test "returns placeholder org info if org does not exist" do
      now = Time.now.utc.to_i
      raw_repo_usage_line_item_data = build_raw_line_item(now)

      repo_usage_line_item = Billing::Platform::Api::RepoUsageLineItem.new(raw_repo_usage_line_item_data, nil, @repo)

      assert_equal repo_usage_line_item.to_json[:org][:name], "Deleted Organization"
      assert_equal repo_usage_line_item.to_json[:org][:avatarSrc], ""
    end

    test "uses gross amount if billed amount is nil" do
      raw_repo_usage_line_item_data = {
        grossAmount: 100,
        quantity: 1,
        usageAt: Time.now.utc.to_i,
        product: "actions"
      }

      repo_usage_line_item = Billing::Platform::Api::RepoUsageLineItem.new(raw_repo_usage_line_item_data, nil, nil)

      assert_equal repo_usage_line_item.to_json[:billedAmount], raw_repo_usage_line_item_data[:grossAmount]
    end
  end
end
