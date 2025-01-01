# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessFooterLinkTest < GitHub::TestCase
  fixtures do
    @business = create :business
  end

  context "validations" do
    test "require that title is present" do
      link = build :business_footer_link, business: @business, title: ""
      refute_predicate link, :valid?
      assert_includes link.errors[:title], "can't be blank"
    end

    test "require that title be no longer than 80 characters" do
      link = build :business_footer_link, business: @business, title: "e" * 81
      refute_predicate link, :valid?
      assert_includes link.errors[:title], "is too long (maximum is 80 characters)"
    end

    test "require that url is present" do
      link = build :business_footer_link, business: @business, url: ""
      refute_predicate link, :valid?
      assert_includes link.errors[:url], "can't be blank"
    end

    test "require that url be no longer than 255 characters" do
      link = build :business_footer_link, business: @business, url: "https://#{"e" * 256}.com"
      refute_predicate link, :valid?
      assert_includes link.errors[:url], "is too long (maximum is 255 characters)"
    end

    test "require that url begin with https://" do
      link = build :business_footer_link, business: @business, url: "eeeeee.com"
      refute_predicate link, :valid?
      assert_includes link.errors[:url], "is not a valid https URL (only https is allowed)"
    end
  end
end
