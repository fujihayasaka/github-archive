# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchShortcutsSetterTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @viewer = create(:user)
    @dashboard = create(:user_dashboard, user: @viewer)
    @repo = create(:repository, owner: @viewer)
  end

  test "replaces all shortcuts in order" do
    existing_shortcut = create(:search_shortcut, dashboard: @dashboard)

    input_a = {
      name: "A",
      query: "-author:monalisa hey",
      search_type: "issues",
      icon: "zap",
      color: "blue",
      scoping_repository: { owner: @repo.owner.login, name: @repo.name }
    }

    input_b = {
      name: "B",
      query: "label:awesome",
      search_type: "discussions",
      icon: "flame",
      color: "red",
    }

    result = assert_changes(
      -> { @dashboard.shortcuts.pluck(:name) },
      from: [existing_shortcut.name],
      to: %w(A B)
    ) do
      SearchShortcutsSetter.new(@viewer).set([input_a, input_b])
    end

    assert_predicate result, :success?
    assert_equal 2,  @dashboard.shortcuts.size
    shortcut_a, shortcut_b = @dashboard.shortcuts

    assert_equal input_a[:name], shortcut_a.name
    assert_equal input_a[:query], shortcut_a.query
    assert_equal input_a[:search_type], shortcut_a.search_type
    assert_equal input_a[:icon], shortcut_a.icon
    assert_equal input_a[:color], shortcut_a.color
    assert_equal @repo.id, shortcut_a.scoping_repository_id

    assert_equal input_b[:name], shortcut_b.name
    assert_equal input_b[:query], shortcut_b.query
    assert_equal input_b[:search_type], shortcut_b.search_type
    assert_equal input_b[:icon], shortcut_b.icon
    assert_equal input_b[:color], shortcut_b.color
    assert_nil shortcut_b.scoping_repository_id

    assert_hydro_published({
      search_type: input_a[:search_type].upcase.to_sym,
      scoping_repository_id: @repo.id,
      user: Hydro::EntitySerializer.user(@viewer),
      context: "MOBILE",
    }, schema: "github.v1.UserDashboardShortcutCreate")

    assert_hydro_published({
      search_type: input_b[:search_type].upcase.to_sym,
      scoping_repository_id: nil,
      user: Hydro::EntitySerializer.user(@viewer),
      context: "MOBILE",
    }, schema: "github.v1.UserDashboardShortcutCreate")

    assert_hydro_published({
      search_type: existing_shortcut.search_type.upcase.to_sym,
      scoping_repository_id: existing_shortcut.scoping_repository_id,
      user: Hydro::EntitySerializer.user(@viewer),
      context: "MOBILE",
    }, schema: "github.v1.UserDashboardShortcutDestroy")
  end

  test "inaccessible repos for scoping_repository return an error" do
    private_repo = create(:private_repository)

    shortcuts = [{
      name: "Test",
      query: "Test",
      search_type: "issues",
      icon: "zap",
      color: "blue",
      scoping_repository: { owner: private_repo.owner.login, name: private_repo.name }
    }]

    error = assert_raises Platform::Errors::NotFound do
      SearchShortcutsSetter.new(@viewer).set(shortcuts)
    end

    assert_equal error.type, "NOT_FOUND"
  end

  test "for blank name values" do
    shortcuts = [{
        name: "",
        query: "",
        searchtype: "issues",
        icon: "zap",
        color: "blue"
    }]

    result = SearchShortcutsSetter.new(@viewer).set(shortcuts)
    refute_empty result.errors
    assert_equal result.errors.first[:message], "Name can't be blank"
  end

  test "for overly long name or query values" do
    shortcuts = [{
      name: "A" * (::SearchDisplayable::NAME_BYTESIZE_LIMIT + 1),
      query: "A" * (::MYSQL_UNICODE_BLOB_LIMIT + 1),
      searchType: "ISSUES",
      icon: "ZAP",
      color: "BLUE"
    }]


    result = SearchShortcutsSetter.new(@viewer).set(shortcuts)
    refute_empty result.errors
    assert_includes result.errors.first[:message], "Name is too long"
    assert_includes result.errors.last[:message], "Query is too long"
  end

  test "when creating too many shortcuts" do
    shortcuts = (::SearchShortcut::MAX_PER_DASHBOARD + 1).times.map do |_|
      { name: "Test", query: "Test", searchType: "issues", icon: "zap", color: "blue" }
    end

    result = SearchShortcutsSetter.new(@viewer).set(shortcuts)
    refute_empty result.errors
    assert_includes result.errors.first[:message], "Cannot have more than #{::SearchShortcut::MAX_PER_DASHBOARD} shortcuts"
  end
end
