# typed: true
# frozen_string_literal: true

require "test_helper"

class ExploreCollectionTest < GitHub::TestCase
  include StringFromBinaryTestHelper

  context "validations" do
    test "validates presence of display_name" do
      collection = create :explore_collection
      collection.display_name = ""

      refute_valid collection
      assert_includes collection.errors[:display_name], "can't be blank"
    end

    test "validates length of display_name" do
      collection = create :explore_collection
      collection.display_name = "x" * (ExploreCollection::MAX_DISPLAY_NAME_LENGTH + 1)

      refute_valid collection
      assert_includes collection.errors[:display_name], "is too long (maximum is " \
                      "#{ExploreCollection::MAX_DISPLAY_NAME_LENGTH} characters)"
    end

    test "validates presence of slug" do
      collection = create :explore_collection
      collection.slug = ""

      refute_valid collection
      assert_includes collection.errors[:slug], "can't be blank"
    end

    test "validates length of slug" do
      collection = create :explore_collection
      collection.slug = "x" * (ExploreCollection::MAX_SLUG_LENGTH + 1)

      refute_valid collection
      assert_includes collection.errors[:slug], "is too long (maximum is " \
                      "#{ExploreCollection::MAX_SLUG_LENGTH} characters)"
    end

    test "validates uniqueness of slug" do
      existing_collection = create :explore_collection
      assert_valid(existing_collection)

      new_collection = create :explore_collection
      new_collection.slug = existing_collection.slug

      refute_valid new_collection
      assert_includes new_collection.errors[:slug], "has already been taken"
    end

    test "validates that slug contains only alphanumerics and hyphens" do
      collection = create :explore_collection

      valid_slugs = %w(ruby ruby-tuesdays rails-5)
      valid_slugs.each do |valid_slug|
        collection.slug = valid_slug
        assert_valid collection
      end

      invalid_slugs = %w(java! java&@!#$script)
      invalid_slugs.each do |invalid_slug|
        collection.slug = invalid_slug

        refute_valid collection
        assert_includes collection.errors[:slug],
          "can only include letters, numbers, and hyphens, e.g., front-end-javascript-frameworks"
      end

      slug_with_emoji = "🐹"
      collection.slug = slug_with_emoji
      refute_valid collection
      assert_includes collection.errors[:slug],
        "can only include letters, numbers, and hyphens, e.g., front-end-javascript-frameworks"
    end

    test "validates that attribution url is a valid url" do
      collection = create :explore_collection

      collection.attribution_url = nil
      assert_valid collection

      collection.attribution_url = "http://example.com"
      assert_valid collection

      collection.attribution_url = "ftp://!!!examplez!!!"
      refute_valid collection
      assert_includes collection.errors[:attribution_url], "must be a valid URL"
    end

    test "validates that image url is a valid url" do
      collection = create :explore_collection

      collection.image_url = nil
      assert_valid collection

      collection.image_url = "http://example.com/pic.jpg"
      assert_valid collection

      collection.image_url = "ftp://!!!examplez!!!"
      refute_valid collection
      assert_includes collection.errors[:image_url], "must be a valid URL"
    end

    test "validates that image url contains a supported image extension" do
      collection = create :explore_collection

      supported_extensions = %w(jpg jpeg gif png)
      supported_extensions.each do |extension|
        collection.image_url = "http://example.com/image.#{extension}"
        assert_valid collection
      end

      unsupported_extensions = %w(tiff bmp)
      unsupported_extensions.each do |extension|
        collection.image_url = "http://example.com/image.#{extension}"
        refute_valid collection
        assert_includes collection.errors[:image_url], "must contain a supported image extension"
      end
    end

    context "#normalize_slug" do
      test "lowercases the slug name" do
        collection = create(:explore_collection, slug: "I-LOVE-YELLING")
        assert_equal collection.slug, "i-love-yelling"
      end

      test "converts underscores to dashes" do
        collection = create(:explore_collection, slug: "snakes_are_cool")
        assert_equal collection.slug, "snakes-are-cool"
      end
    end
  end

  test "#short_description_html and #async_short_description_html" do
    collection = build(:explore_collection, description:
      "https://github.com and :tada: and a bunch of other text " \
      "because someone was very longwinded")

    short_html = collection.short_description_html(limit: 40)
    assert_equal short_html, collection.async_short_description_html(limit: 40).sync

    assert_match /…/, short_html
    assert_includes short_html, "and a"
    refute_includes short_html, "very longwinded"
    assert_includes short_html, "🎉"

    result = Nokogiri::HTML.parse(short_html)
    assert_nil result.at_css("a")
  end

  context ".featured_and_shuffled" do
    test "returns a limited, randomly ordered set of featured collections" do
      featured_collections = create_list(:featured_explore_collection, 3)
      unfeatured_collection = create(:explore_collection)

      collections = ExploreCollection.featured_and_shuffled(limit: 2)

      refute_includes collections, unfeatured_collection
      assert_equal 2, collections.count
      assert_includes featured_collections, collections.first
      assert_includes featured_collections, collections.second
    end
  end

  [:display_name, :description, :created_by].each do |field|
    test "supports emoji for #{field}" do
      collection = create(:explore_collection, field => "we ❤️ emojis")

      assert_multibyte_tracked_changes(collection, field)
    end
  end

  test "supports UTF-8 for slug using StringFromBinary" do
    encoded_value = "we-love-emojis"
    collection = create(:explore_collection, slug: encoded_value)
    collection.reload

    assert_equal StringFromBinary.new, collection.type_for_attribute(:slug)
    assert_equal Encoding::UTF_8, collection.slug.encoding
  end
end
