# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersNotificationListFilterTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @repo = create(:repository)
    @repo2 = create(:repository)
    @team = create(:team, organization: @org)
    @team2 = create(:team, organization: @org)

    @org.add_member(@user)
    @team.add_member(@user)
    @team2.add_member(@user)
  end

  setup do
    @qualifiers = Search::ParsedQuery.qualifiers
  end

  def filter
    Search::Filters::NotificationListFilter.new(current_user: @user, qualifiers: @qualifiers)
  end

  context "must" do
    test "filters a repository" do
      @qualifiers[:repo].must @repo.name_with_owner

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Repository" } },
                { term: { list_id: @repo.id } },
              ],
            },
          }],
        },
      }, filter.must)
      assert_nil filter.must_not
      assert_predicate filter, :valid?
    end

    test "filters multiple repositories" do
      @qualifiers[:repo].must [@repo.name_with_owner, @repo2.name_with_owner]

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Repository" } },
                { terms: { list_id: [@repo.id, @repo2.id] } },
              ],
            },
          }],
        },
      }, filter.must)
      assert_nil filter.must_not
      assert_predicate filter, :valid?
    end

    test "filters a team" do
      @qualifiers[:team].must [@team.ability_description]

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Team" } },
                { term: { list_id: @team.id } },
              ],
            },
          }],
        },
      }, filter.must)
      assert_nil filter.must_not
      assert_predicate filter, :valid?
    end

    test "filters multiple teams" do
      @qualifiers[:team].must [@team.ability_description, @team2.ability_description]

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Team" } },
                { terms: { list_id: [@team.id, @team2.id] } },
              ],
            },
          }],
        },
      }, filter.must)
      assert_nil filter.must_not
      assert_predicate filter, :valid?
    end

    test "filters by repositories and teams" do
      @qualifiers[:repo].must [@repo.name_with_owner, @repo2.name_with_owner]
      @qualifiers[:team].must [@team.ability_description, @team2.ability_description]

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Repository" } },
                { terms: { list_id: [@repo.id, @repo2.id] } },
              ],
            },
          }, {
            bool: {
              must: [
                { term: { list_type: "Team" } },
                { terms: { list_id: [@team.id, @team2.id] } },
              ],
            },
          }],
        },
      }, filter.must)
      assert_nil filter.must_not
      assert_predicate filter, :valid?
    end

    test "ignores inaccessible private repositories" do
      private_repo = create(:private_repository)

      @qualifiers[:repo].must [@repo.name_with_owner, private_repo.name_with_owner]

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Repository" } },
                { term: { list_id: @repo.id } },
              ],
            },
          }],
        },
      }, filter.must)
    end

    test "ignores inaccessible teams" do
      other_org = create(:organization)
      other_team = create(:team, organization: other_org)

      @qualifiers[:team].must [@team.ability_description, other_team.ability_description]

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Team" } },
                { term: { list_id: @team.id } },
              ],
            },
          }],
        },
      }, filter.must)
    end
  end

  context "must_not" do
    test "filters out a repository" do
      @qualifiers[:repo].must_not @repo.name_with_owner

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Repository" } },
                { term: { list_id: @repo.id } },
              ],
            },
          }],
        },
      }, filter.must_not)
      assert_nil filter.must
      assert_predicate filter, :valid?
    end

    test "filters out multiple repositories" do
      @qualifiers[:repo].must_not [@repo.name_with_owner, @repo2.name_with_owner]

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Repository" } },
                { terms: { list_id: [@repo.id, @repo2.id] } },
              ],
            },
          }],
        },
      }, filter.must_not)
      assert_nil filter.must
      assert_predicate filter, :valid?
    end

    test "filters out a team" do
      @qualifiers[:team].must_not [@team.ability_description]

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Team" } },
                { term: { list_id: @team.id } },
              ],
            },
          }],
        },
      }, filter.must_not)
      assert_nil filter.must
      assert_predicate filter, :valid?
    end

    test "filters out multiple teams" do
      @qualifiers[:team].must_not [@team.ability_description, @team2.ability_description]

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Team" } },
                { terms: { list_id: [@team.id, @team2.id] } },
              ],
            },
          }],
        },
      }, filter.must_not)
      assert_nil filter.must
      assert_predicate filter, :valid?
    end

    test "filters out by repositories and teams" do
      @qualifiers[:repo].must_not [@repo.name_with_owner, @repo2.name_with_owner]
      @qualifiers[:team].must_not [@team.ability_description, @team2.ability_description]

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Repository" } },
                { terms: { list_id: [@repo.id, @repo2.id] } },
              ],
            },
          }, {
            bool: {
              must: [
                { term: { list_type: "Team" } },
                { terms: { list_id: [@team.id, @team2.id] } },
              ],
            },
          }],
        },
      }, filter.must_not)
      assert_nil filter.must
      assert_predicate filter, :valid?
    end

    test "ignores inaccessible private repositories" do
      private_repo = create(:private_repository)

      @qualifiers[:repo].must_not [@repo.name_with_owner, private_repo.name_with_owner]

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Repository" } },
                { term: { list_id: @repo.id } },
              ],
            },
          }],
        },
      }, filter.must_not)
    end

    test "ignores inaccessible teams" do
      other_org = create(:organization)
      other_team = create(:team, organization: other_org)

      @qualifiers[:team].must_not [@team.ability_description, other_team.ability_description]

      assert_equal({
        bool: {
          should: [{
            bool: {
              must: [
                { term: { list_type: "Team" } },
                { term: { list_id: @team.id } },
              ],
            },
          }],
        },
      }, filter.must_not)
    end
  end
end
