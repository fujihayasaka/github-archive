# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionCategoryPinTest < GitHub::TestCase
  include DiscussionsTestHelper

  context "validations" do
    test "requires a repository" do
      category_pin = DiscussionCategoryPin.new
      refute_predicate category_pin, :valid?
      assert_includes category_pin.errors[:repository], "must exist"
    end

    test "requires a pinned_by user" do
      category_pin = DiscussionCategoryPin.new
      refute_predicate category_pin, :valid?
      assert_includes category_pin.errors[:pinned_by], "must exist"
    end

    test "requires a category" do
      category_pin = DiscussionCategoryPin.new
      refute_predicate category_pin, :valid?
      assert_includes category_pin.errors[:category], "must exist"
    end

    test "requires a discussion" do
      category_pin = DiscussionCategoryPin.new
      refute_predicate category_pin, :valid?
      assert_includes category_pin.errors[:discussion], "must exist"
    end

    test "can only be pinned to category once" do
      existing_pin = create(:discussion_category_pin)
      new_pin = build(:discussion_category_pin, discussion: existing_pin.discussion)

      refute_predicate new_pin, :valid?
      assert_includes new_pin.errors[:discussion], "is already pinned to this category"
    end

    test "can set its repository and category from the discussion before saving" do
      discussion = create(:discussion)
      user = create(:user)
      category_pin = DiscussionCategoryPin.new(discussion: discussion, pinned_by: user)
      category_pin.save
      assert_predicate category_pin, :valid?
      assert_equal discussion.repository, category_pin.repository
      assert_equal discussion.category, category_pin.category
    end
  end
end
