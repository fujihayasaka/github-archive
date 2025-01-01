# typed: true
# frozen_string_literal: true

require "test_helper"
require "zstd-ruby"

class TeamSearchShortcutTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)
    @team = create(:team, name: "myTeam", organization: @org)
    @dashboard = create(:team_dashboard, team: @team)
  end

  context "on initialization" do
    test "has default enum values" do
      shortcut = TeamSearchShortcut.new
      assert shortcut.search_type
      assert shortcut.icon
      assert shortcut.color
    end
  end

  context "validations" do
    test "requires fields" do
      shortcut = TeamSearchShortcut.new
      refute_predicate shortcut, :valid?

      assert_includes shortcut.errors[:name], "can't be blank"
      assert_includes shortcut.errors[:dashboard], "can't be blank"
    end

    test "name cannot be too long" do
      shortcut = TeamSearchShortcut.new(name: "A" * (::SearchDisplayable::NAME_BYTESIZE_LIMIT + 1))
      refute_predicate shortcut, :valid?
      assert_includes shortcut.errors[:name], "is too long (maximum is 256 characters)"
    end

    test "description cannot be too long" do
      shortcut = TeamSearchShortcut.new(description: "A" * (MYSQL_UNICODE_BLOB_LIMIT + 1))
      refute_predicate shortcut, :valid?
      assert_includes shortcut.errors[:description], "is too long (maximum is 65536 characters)"
    end

    test "query cannot be too long" do
      shortcut = TeamSearchShortcut.new(query: "A" * (MYSQL_UNICODE_BLOB_LIMIT + 1))
      refute_predicate shortcut, :valid?
      assert_includes shortcut.errors[:query], "is too long (maximum is 65536 characters)"
    end

    test "priority must be unique" do
      create(:team_search_shortcut, dashboard: @dashboard, priority: 1)
      shortcut = build(:team_search_shortcut, dashboard: @dashboard, priority: 1)
      refute_predicate shortcut, :valid?
      assert_includes shortcut.errors[:priority], "has already been taken"
    end

    test "priority must be a valid unsigned bigint" do
      shortcut = build(:team_search_shortcut, dashboard: @dashboard, priority: -1)
      refute_predicate shortcut, :valid?
      assert_includes shortcut.errors[:priority], "must be greater than or equal to 0"

      shortcut.priority = GitHub::Prioritizable::MAX_PRIORITY_VALUE + 1
      refute_predicate shortcut, :valid?
      assert_includes shortcut.errors[:priority], "must be less than or equal to 18446744073709551615"
    end

    test "scoping repository must be visible to the dashboard team" do
      repository = create(:private_repository)
      shortcut = build(:team_search_shortcut, dashboard: @dashboard, scoping_repository: repository)
      refute_predicate shortcut, :valid?
      assert_includes shortcut.errors[:scoping_repository], "not found for dashboard owner"
    end

    test "cannot have more than the maximum shortcuts" do
      create_list(:team_search_shortcut, ::TeamSearchShortcut::MAX_PER_DASHBOARD, dashboard: @dashboard)
      shortcut = build(:team_search_shortcut, dashboard: @dashboard)
      refute_predicate shortcut, :valid?
      assert_includes shortcut.errors[:base], "cannot have more than #{::TeamSearchShortcut::MAX_PER_DASHBOARD} shortcuts"
    end
  end

  context "query" do
    test "is stored as a compressed binary" do
      shortcut = create(:team_search_shortcut, query: "author:a author:b")

      raw_db_binary = shortcut.read_attribute_before_type_cast("compressed_query")

      refute_equal shortcut.query, raw_db_binary.to_s
      refute_equal shortcut.compressed_query, raw_db_binary.to_s

      assert_kind_of ActiveModel::Type::Binary::Data, raw_db_binary
      assert_equal Zstd.compress(shortcut.query, 3).to_s, raw_db_binary.to_s
    end

    test "can handle unicode" do
      shortcut = create(:team_search_shortcut, query: "🏂")
      assert_equal "🏂", shortcut.query
      assert_equal "🏂", shortcut.compressed_query
    end
  end

  context "query_terms" do
    test "known terms include basic, issues, and discussions terms" do
      basic_terms = %i(assignee author user repo category label milestone project)
      issue_terms = ::Search::Queries::IssueQuery::field_list
      discussion_terms = ::Search::Queries::DiscussionQuery::field_list

      expected_terms = Set.new(basic_terms + issue_terms + discussion_terms)

      assert ::SearchQueryable::KNOWN_QUERY_TERMS.superset?(expected_terms),
        "Expected #{::SearchQueryable::KNOWN_QUERY_TERMS} to be a superset of #{expected_terms}"
    end

    test "parses known terms to hashes" do
      repo = create(:repository, owner: @owner, name: "accessible-repo")
      label = create(:label, repository: repo, name: "A B C")

      terms = create(:team_search_shortcut, {
        scoping_repository: repo,
        query: "-author:a random repo:#{repo.name_with_owner} label:\"#{label.name}\" unknown:🦉 is:open Free Form Text"
      }).query_terms

      assert_same_elements [
        {
          term: "-author:a",
          matched: true,
          name: :author,
          value: "a",
          negative: true
        },
        {
          term: "random",
          matched: false
        },
        {
          term: "repo:#{repo.name_with_owner}",
          matched: true,
          name: :repo,
          value: repo.name_with_owner,
          negative: false
        },
        {
          term: "label:\"#{label.name}\"",
          matched: true,
          name: :label,
          value: label.name,
          negative: false,
          scoping_repository_id: repo.id
        },
        {
          term: "unknown:🦉",
          matched: false
        },
        {
          term: "is:open",
          matched: true,
          name: :is,
          value: "open",
          negative: false
        }, {
          term: "Free Form Text",
          matched: false
        }
      ], terms
    end
  end
end
