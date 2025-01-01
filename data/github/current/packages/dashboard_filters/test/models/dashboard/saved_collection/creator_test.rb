# typed: true
# frozen_string_literal: true

require "test_helper"

class SavedCollectionCreatorTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @dashboard = create(:user_dashboard, user: @owner)
  end

  test "creates SavedCollection and persists it", skip_enterprise: true do
    result = Dashboard::SavedCollection::Creator.new(
      dashboard: @dashboard,
      name: "test",
      description: "test",
      saved_views: [
        {
          name: "test",
          description: "test",
          query: "test",
          icon: SearchDisplayable::ICONS[:zap],
          color: SearchDisplayable::COLORS[:gray],
        }
      ],
      icon: SearchDisplayable::ICONS[:zap],
      color: SearchDisplayable::COLORS[:gray],
    ).execute

    assert_predicate result, :success?
    assert_predicate result.collection, :valid?
    assert_equal 1, result.collection.saved_views.count

    saved_collection = Dashboard::SavedCollection.find(result.collection.id)
    assert_equal result.collection.name, saved_collection.name
  end

  test "error blocks collection from being saved", skip_enterprise: true do
    result = Dashboard::SavedCollection::Creator.new(
      dashboard: @dashboard,
      name: "test",
      description: "test",
      saved_views: [
        {
          description: "test",
        }
      ],
      icon: SearchDisplayable::ICONS[:zap],
      color: SearchDisplayable::COLORS[:gray],
    ).execute

    refute_predicate result, :success?

    saved_collection = Dashboard::SavedCollection.first
    assert_nil saved_collection
  end

  test "only one collection with protected_type per dashboard", skip_enterprise: true do
    result1 = Dashboard::SavedCollection::Creator.execute(
      dashboard: @dashboard,
      name: "test",
      description: "test",
      protected_type: Dashboard::SavedCollection::PROTECTED_TYPES[:reviews],
    )

    assert_predicate result1, :success?

    result2 = Dashboard::SavedCollection::Creator.execute(
      dashboard: @dashboard,
      name: "test",
      description: "test",
      protected_type: Dashboard::SavedCollection::PROTECTED_TYPES[:reviews],
    )

    refute_predicate result2, :success?

    assert_equal "Protected type has already been taken", result2.errors.first
    assert_equal 1, Dashboard::SavedCollection.all.count
  end
end
