# typed: true
# frozen_string_literal: true

require "test_helper"

module CopilotPLG
  class SelfServeBannerTest < GitHub::TestCase
    setup do
      @valid_attributes = {
        slug: "test-banner",
        title: "Test Banner",
        body: "This is a test banner",
        cta_url: "https://github.com",
        cta_text: "Learn More",
        visibility: true
      }
    end

    test "validates presence of required fields" do
      banner = SelfServeBanner.new
      refute banner.valid?

      assert_includes banner.errors[:slug], "can't be blank"
      assert_includes banner.errors[:title], "can't be blank"
      assert_includes banner.errors[:body], "can't be blank"
      assert_includes banner.errors[:cta_url], "can't be blank"
      assert_includes banner.errors[:cta_text], "can't be blank"
    end

    test "test validates slug uniqueness" do
      existing_banner = SelfServeBanner.create!(@valid_attributes)
      duplicate_banner = SelfServeBanner.new(@valid_attributes)

      refute duplicate_banner.valid?
      assert_includes duplicate_banner.errors[:slug], "has already been taken"
    end

    test "validates cta url format" do
      banner = SelfServeBanner.new(@valid_attributes.merge(cta_url: "invalid-url"))
      refute banner.valid?
      assert_includes banner.errors[:cta_url], "is invalid"

      banner.cta_url = "https://github.com"
      assert banner.valid?
    end

    test "validates visibility inclusion" do
      banner = SelfServeBanner.new(@valid_attributes.merge(visibility: nil))
      refute banner.valid?

      banner.visibility = true
      assert banner.valid?

      banner.visibility = false
      assert banner.valid?
    end

    test "cannot modify slug after create" do
      banner = SelfServeBanner.create!(
        slug: "original-test-banner",
        title: "Test Banner",
        body: "This is a test banner",
        cta_url: "https://survey-monkey.com",
        cta_text: "Learn More",
        visibility: true)

      original_slug = banner.slug

      banner.update(slug: "new-slug")
      assert_equal original_slug, banner.reload.slug
    end
  end
end
