# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::Payloads::IndexTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @staff_user = create(:staff_admin_user)
    @static_gpt4 = GitHubModels::Types::Static::GPT4
    @static_gpt4o = GitHubModels::Types::Static::GPT4o
    @gpt4_catalog_item = AzureModels::CatalogItem.create!(key: "#{@static_gpt4[:registry]}/#{@static_gpt4[:name]}", value: {})
    @gpt4o_catalog_item = AzureModels::CatalogItem.create!(key: "#{@static_gpt4o[:registry]}/#{@static_gpt4o[:name]}", value: {})
  end

  setup do
    Marketplace::Payloads::Categories.any_instance.stubs(:call).returns({
      apps: [{ name: "Mock Category", slug: "mock-category", description_html: "<p>Mock Description</p>" }],
      actions: [],
    })
  end

  def payload(user: @user)
    GitHubModels::Payloads::Index.new(
      current_user: user,
      models: [@static_gpt4, @static_gpt4o]
    ).call
  end

  context "#call" do
    test "returns the models that are passed in" do
      data = payload

      assert_equal 2, data[:models].count
      assert_equal @static_gpt4[:name], data[:models].first[:name]
      assert_equal @static_gpt4o[:name], data[:models].second[:name]
    end

    test "returns categories" do
      assert_equal "Mock Category", payload.dig(:categories, :apps).first[:name]
    end

    context "model visibility" do
      test "returns all models when all catalog items are visible" do
        data = payload

        assert_equal 2, data[:models].count
        assert_equal @static_gpt4[:name], data[:models].first[:name]
        assert_equal @static_gpt4o[:name], data[:models].second[:name]
      end

      test "returns staffshipped models for staff users" do
        @gpt4_catalog_item.staffshipped!
        data = payload(user: @staff_user)

        assert_equal 2, data[:models].count
        assert_equal @static_gpt4[:name], data[:models].first[:name]
        assert_equal @static_gpt4o[:name], data[:models].second[:name]
      end

      test "hides staffshipped models for normal users" do
        @gpt4_catalog_item.staffshipped!
        data = payload

        assert_equal 1, data[:models].count
        assert_equal @static_gpt4o[:name], data[:models].first[:name]
      end

      test "hides staffshipped models for nil users" do
        @gpt4_catalog_item.staffshipped!
        data = payload(user: nil)

        assert_equal 1, data[:models].count
        assert_equal @static_gpt4o[:name], data[:models].first[:name]
      end

      test "hides hidden models for staff users" do
        @gpt4_catalog_item.hidden!
        data = payload(user: @staff_user)

        assert_equal 1, data[:models].count
        assert_equal @static_gpt4o[:name], data[:models].first[:name]
      end

      test "hides hidden models for normal users" do
        @gpt4_catalog_item.hidden!
        data = payload

        assert_equal 1, data[:models].count
        assert_equal @static_gpt4o[:name], data[:models].first[:name]
      end

      test "hides hidden models for nil users" do
        @gpt4_catalog_item.hidden!
        data = payload(user: nil)

        assert_equal 1, data[:models].count
        assert_equal @static_gpt4o[:name], data[:models].first[:name]
      end
    end
  end
end unless GitHub.enterprise?
