# typed: true
# frozen_string_literal: true

require "test_helper"

class Dashboard::SavedCollectionTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:user)
    @dashboard = create(:user_dashboard, user: @owner)
  end

  context "on initialization" do
    test "has default enum values" do
      saved_collection = Dashboard::SavedCollection.new
      assert saved_collection.icon
      assert saved_collection.color
    end
  end

  test "logs hydro events on create, edit, and destroy", skip_enterprise: true do
    saved_collection = create(:saved_collection, dashboard: @dashboard)
    serialized_saved_collection = Hydro::EntitySerializer.dashboard_saved_collection(saved_collection).except(:created_at, :updated_at)
    assert_hydro_messages(count: 1, schema: "github.v1.DashboardSavedCollectionCreate")

    saved_collection.update(name: "New name")
    assert_hydro_messages(count: 1, schema: "github.v1.DashboardSavedCollectionUpdate")

    saved_collection.destroy

    assert_hydro_messages(count: 1, schema: "github.v1.DashboardSavedCollectionDestroy")
  end

  test "can only create one saved collection per protected_type per dashboard", skip_enterprise: true do
    saved_collection1 = Dashboard::SavedCollection.new(dashboard: @dashboard, name: "whatever", protected_type: "reviews")
    saved_collection1.save
    saved_collection2 = Dashboard::SavedCollection.new(dashboard: @dashboard, name: "whatever", protected_type: "reviews")
    saved_collection2.save

    error = saved_collection2.errors.first
    assert_equal "has already been taken", error.message

    @dashboard.reload
    assert_equal 1, @dashboard.saved_collections.length
  end

  context "validations" do
    test "requires fields" do
      saved_collection = Dashboard::SavedCollection.new
      refute_predicate saved_collection, :valid?

      assert_includes saved_collection.errors[:name], "can't be blank"
      assert_includes saved_collection.errors[:dashboard], "can't be blank"
    end

    test "name cannot be too long" do
      saved_collection = Dashboard::SavedCollection.new(name: "A" * (::SearchDisplayable::NAME_BYTESIZE_LIMIT + 1))
      refute_predicate saved_collection, :valid?
      assert_includes saved_collection.errors[:name], "is too long (maximum is 256 characters)"
    end

    test "description cannot be too long" do
      saved_collection = Dashboard::SavedCollection.new(description: "A" * (MYSQL_UNICODE_BLOB_LIMIT + 1))
      refute_predicate saved_collection, :valid?
      assert_includes saved_collection.errors[:description], "is too long (maximum is 65536 characters)"
    end

    test "priority must be unique" do
      create(:saved_collection, dashboard: @dashboard, priority: 1)
      saved_collection = build(:saved_collection, dashboard: @dashboard, priority: 1)
      refute_predicate saved_collection, :valid?
      assert_includes saved_collection.errors[:priority], "has already been taken"
    end

    test "priority must be a valid unsigned bigint" do
      saved_collection = build(:saved_collection, dashboard: @dashboard, priority: -1)
      refute_predicate saved_collection, :valid?
      assert_includes saved_collection.errors[:priority], "must be greater than or equal to 0"

      saved_collection.priority = GitHub::Prioritizable::MAX_PRIORITY_VALUE + 1
      refute_predicate saved_collection, :valid?
      assert_includes saved_collection.errors[:priority], "must be less than or equal to 18446744073709551615"
    end
  end

  context "associations" do
    test "has many saved views" do
      saved_collection = create(:saved_collection, dashboard: @dashboard)
      create(:saved_view, saved_collection: saved_collection)
      assert_equal 1, saved_collection.saved_views.count
    end
  end
end
