# typed: true
# frozen_string_literal: true

require "test_helper"
require "zstd-ruby"

class Dashboard::SavedViewTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:user)
    @dashboard = create(:user_dashboard, user: @owner)
    @saved_collection = create(:saved_collection, dashboard: @dashboard)
  end

  context "on initialization" do
    test "has default enum values" do
      saved_view = Dashboard::SavedView.new
      assert saved_view.icon
      assert saved_view.color
    end
  end

  test "logs hydro events on create, edit, and destroy", skip_enterprise: true do
    saved_view = create(:saved_view, saved_collection: @saved_collection)
    assert_hydro_messages(count: 1, schema: "github.v1.DashboardSavedViewCreate")

    saved_view.update(name: "New name")
    assert_hydro_messages(count: 1, schema: "github.v1.DashboardSavedViewUpdate")

    saved_view.destroy

    assert_hydro_messages(count: 1, schema: "github.v1.DashboardSavedViewDestroy")
  end

  context "validations" do
    test "requires fields" do
      saved_view = Dashboard::SavedView.new
      refute_predicate saved_view, :valid?

      assert_includes saved_view.errors[:name], "can't be blank"
      assert_includes saved_view.errors[:saved_collection_id], "can't be blank"
    end

    test "name cannot be too long" do
      saved_view = Dashboard::SavedView.new(name: "A" * (::SearchDisplayable::NAME_BYTESIZE_LIMIT + 1))
      refute_predicate saved_view, :valid?
      assert_includes saved_view.errors[:name], "is too long (maximum is 256 characters)"
    end

    test "description cannot be too long" do
      saved_view = Dashboard::SavedView.new(description: "A" * (MYSQL_UNICODE_BLOB_LIMIT + 1))
      refute_predicate saved_view, :valid?
      assert_includes saved_view.errors[:description], "is too long (maximum is 65536 characters)"
    end

    test "query cannot be too long" do
      saved_view = Dashboard::SavedView.new(query: "A" * (MYSQL_UNICODE_BLOB_LIMIT + 1))
      refute_predicate saved_view, :valid?
      assert_includes saved_view.errors[:query], "is too long (maximum is 65536 characters)"
    end

    test "priority must be unique" do
      create(:saved_view, saved_collection: @saved_collection, priority: 1)
      saved_view = build(:saved_view, saved_collection: @saved_collection, priority: 1)
      refute_predicate saved_view, :valid?
      assert_includes saved_view.errors[:priority], "has already been taken"
    end

    test "priority must be a valid unsigned bigint" do
      saved_view = build(:saved_view, saved_collection: @saved_collection, priority: -1)
      refute_predicate saved_view, :valid?
      assert_includes saved_view.errors[:priority], "must be greater than or equal to 0"

      saved_view.priority = GitHub::Prioritizable::MAX_PRIORITY_VALUE + 1
      refute_predicate saved_view, :valid?
      assert_includes saved_view.errors[:priority], "must be less than or equal to 18446744073709551615"
    end
  end

  context "query" do
    test "is stored as a compressed binary" do
      saved_view = create(:saved_view, query: "author:a author:b")

      raw_db_binary = saved_view.read_attribute_before_type_cast("compressed_query")

      refute_equal saved_view.query, raw_db_binary.to_s
      refute_equal saved_view.compressed_query, raw_db_binary.to_s

      assert_kind_of ActiveModel::Type::Binary::Data, raw_db_binary
      assert_equal Zstd.compress(saved_view.query, 3).to_s, raw_db_binary.to_s
    end

    test "can handle unicode" do
      saved_view = create(:saved_view, query: "🏂")
      assert_equal "🏂", saved_view.query
      assert_equal "🏂", saved_view.compressed_query
    end
  end

  context "associations" do
    test "belongs to a saved collection" do
      saved_view = create(:saved_view, query: "author:a author:b")
      assert saved_view.saved_collection
    end
  end
end
