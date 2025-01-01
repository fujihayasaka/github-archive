# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Payloads::CategoriesTest < GitHub::TestCase
  fixtures do
    @overlapping_category = create(:marketplace_category, name: "aaa", navigation_visible: true, description: "overlapping description")
    @app_category = create(:marketplace_category, name: "bbb", navigation_visible: true, description: "app description")
    @action_category = create(:marketplace_category, name: "ccc", navigation_visible: true, description: "action description")

    @category_with_unlisted_items = create(:marketplace_category, name: "ddd", navigation_visible: true)
    @category_with_no_items = create(:marketplace_category, name: "eee", navigation_visible: true)
    @category_without_visible_navigation = create(:marketplace_category, name: "fff", navigation_visible: false)

    @good_app_listing = create(:marketplace_listing,
                               categories: [@overlapping_category, @app_category, @category_without_visible_navigation],
                               state: :verified)
    @rejected_app_listing = create(:marketplace_listing, categories: [@category_with_unlisted_items], state: :rejected)

    @good_action = create(:repository_action,
                          :listed,
                          categories: [@overlapping_category, @action_category, @category_without_visible_navigation])

    @unlisted_action = create(:repository_action, categories: [@category_with_unlisted_items], state: :unlisted)
  end

  context "#call" do
    test "returns visible categories with valid apps, sorted by name, with the correct count" do
      payload = Marketplace::Payloads::Categories.new.call

      assert_equal 2, payload[:apps].count
      assert_equal({
        name: @overlapping_category.name,
        slug: @overlapping_category.slug,
        description_html: "<p>overlapping description</p>\n",
      }, payload[:apps].first)
      assert_equal({
        name: @app_category.name,
        slug: @app_category.slug,
        description_html: "<p>app description</p>\n",
      }, payload[:apps].second)
    end

    test "returns visible categories with valid actions, sorted by name, with the correct count" do
      payload = Marketplace::Payloads::Categories.new.call

      assert_equal 2, payload[:actions].count
      assert_equal({
        name: @overlapping_category.name,
        slug: @overlapping_category.slug,
        description_html: "<p>overlapping description</p>\n",
      }, payload[:actions].first)
      assert_equal({
        name: @action_category.name,
        slug: @action_category.slug,
        description_html: "<p>action description</p>\n",
      }, payload[:actions].second)
    end
  end
end unless GitHub.enterprise?
