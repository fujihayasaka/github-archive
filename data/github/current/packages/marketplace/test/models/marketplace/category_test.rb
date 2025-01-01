# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceCategoryTest < GitHub::TestCase
  context "slug generation" do
    test "slug is generated from name" do
      category = create(:marketplace_category, name: "Big Category")
      assert_equal "big-category", category.slug
    end

    test "slug is updated if name is changed" do
      category = create(:marketplace_category, name: "Big Category")

      category.name = "Small Category"
      category.save
      assert_equal "small-category", category.reload.slug
    end
  end

  test "name is string representation" do
    category = create(:marketplace_category, name: "This Category Has a Name")

    assert_equal category.name, category.to_s
  end

  context "validations" do
    test "disallows 'none' as a name" do
      category = build(:marketplace_category, name: "none")

      refute_predicate category, :valid?
      assert_includes category.errors[:name], "is reserved, please rename the category"
    end

    test "disallows name containing emojis" do
      category = build(:marketplace_category, name: "🐹")

      refute_predicate category, :valid?
      assert_includes category.errors[:name], "doesn't accept 4-byte Unicode"
    end

    test "requires a unique name (case insensitive)" do
      category = create(:marketplace_category)

      category2 = build(:marketplace_category, name: category.name)
      refute_predicate category2, :valid?
      assert_includes category2.errors[:name], "has already been taken"

      category3 = build(:marketplace_category, name: category.name.upcase)
      refute_predicate category3, :valid?
      assert_includes category3.errors[:name], "has already been taken"
    end

    test "requires a unique slug (case insensitive)" do
      category = create(:marketplace_category)

      # slug will be set from name:
      category2 = build(:marketplace_category, name: category.slug)
      refute_predicate category2, :valid?
      assert_includes category2.errors[:slug], "has already been taken"

      category3 = build(:marketplace_category, name: category.slug.upcase)
      refute_predicate category3, :valid?
      assert_includes category3.errors[:slug], "has already been taken"
    end

    test "requires slug does not match an existing Listing" do
      listing = create(:marketplace_listing, name: "Existing Listing")
      category = build(:marketplace_category, name: listing.name)

      refute_predicate category, :valid?
      assert_includes category.errors[:slug], "is reserved by a Listing, please rename the category"
    end

    test "validates description length" do
      text = "a" * (Marketplace::Category::DESCRIPTION_MAX_LENGTH + 1)
      category = build(:marketplace_category, description: text)

      refute_predicate category, :valid?
      assert_predicate category.errors[:description], :any?
    end

    test "does not allow using the same category as parent" do
      category = create(:marketplace_category)
      category.parent_category = category

      refute_predicate category, :valid?
      assert_predicate category.errors[:parent_category], :any?
    end

    test "does not allow using the same category as sub category" do
      category = create(:marketplace_category)
      category.sub_categories << category

      refute_predicate category, :valid?
      assert_predicate category.errors[:parent_category], :any?
    end

    test "allows only a single level of sub categories" do
      category = create(:marketplace_category)
      sub_category = create(:marketplace_category, parent_category: category)

      other_category = create(:marketplace_category)

      category.parent_category = other_category
      refute_predicate category, :valid?
      refute category.save
      assert_includes category.errors[:parent_category], "cannot be set because this category has subcategories"
      assert_equal 0, other_category.reload.sub_categories.count

      other_category.sub_categories << category
      refute_predicate category, :valid?
      refute category.save
      assert_includes category.errors[:parent_category], "cannot be set because this category has subcategories"
      assert_equal 0, other_category.reload.sub_categories.count

      category.sub_categories = []
      assert_predicate category.reload, :valid?
      assert_equal 0, category.sub_categories.count

      category.parent_category = other_category
      assert_predicate category, :valid?
      assert category.save
      assert_equal 1, other_category.reload.sub_categories.count
    end

    test "does not allow filter type category if it has primary listings" do
      category = create(:marketplace_category)
      listing = create(:marketplace_listing, categories: [category])

      refute category.acts_as_filter?
      assert_equal category.id, listing.reload.regular_categories.first.id
      assert category.valid?

      category.acts_as_filter = true

      refute category.valid?
      assert_includes category.errors[:acts_as_filter],
        "cannot be a filter because it has primary listings"
    end

    test "allows filter type category if it has secondary listings" do
      category = create(:marketplace_category)
      other_category = create(:marketplace_category)
      listing = create(:marketplace_listing, categories: [other_category, category])

      refute category.acts_as_filter?
      assert_equal category.id, listing.reload.regular_categories.second&.id
      assert category.valid?

      category.acts_as_filter = true

      assert category.save
      assert category.acts_as_filter?
      assert_nil listing.regular_categories.reload.second
    end

    test "allows filter type category if no primary or secondary listings" do
      category = create(:marketplace_category)

      refute category.acts_as_filter?
      assert category.valid?

      category.acts_as_filter = true

      assert category.save
      assert category.acts_as_filter?
    end
  end

  context "slug_for_topic" do
    test "returns the category slug when an alias exists" do
      assert_equal "code-quality", Marketplace::Category.slug_for_topic("quality")
    end

    test "returns nil when no alias exists" do
      assert_nil Marketplace::Category.slug_for_topic("unaliased")
    end
  end

  context ".subcategory_candidates" do
    test "excludes the given category" do
      cat1 = create(:marketplace_category)
      cat2 = create(:marketplace_category)

      subcategory_candidates = Marketplace::Category.subcategory_candidates(for_optional_slug: cat2.slug)

      assert_equal [cat1.id], subcategory_candidates.map(&:id)
    end

    test "returns categories that don't have subcategories" do
      cat1 = create(:marketplace_category)
      cat2 = create(:marketplace_category)
      cat3 = create(:marketplace_category, sub_categories: [cat1])

      subcategory_candidates = Marketplace::Category.subcategory_candidates

      assert_equal [cat1.id, cat2.id], subcategory_candidates.map(&:id)
    end
  end

  context ".navigation_visible" do
    test "excludes categories whose `navigation_visible` is false" do
      visible_category = create(:marketplace_category, navigation_visible: true)
      _hidden_category = create(:marketplace_category, navigation_visible: false)

      assert_equal [visible_category], Marketplace::Category.navigation_visible
    end
  end

  context ".top_level" do
    test "returns the top level categories, i.e. they may have subcategories" do
      parent_category = create(:marketplace_category)
      _subcategory = create(:marketplace_category, parent_category: parent_category)
      childless_category = create(:marketplace_category)

      assert_equal [parent_category, childless_category], Marketplace::Category.top_level
    end
  end
end
