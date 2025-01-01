# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersMemexProjectExclusionFilterTest < GitHub::TestCase
  fixtures do
    @repos = create_list(:repository, 2)
    @memex = create(:memex_project)

    @issues = @repos.map { |repo| create(:issue, repository: repo) }
    @pulls = @repos.map { |repo| create(:pull_request, :disable_disk_access, repository: repo) }

    @items = (@issues + @pulls).map do |content|
      create(:memex_project_item, memex_project: @memex, content: content)
    end
  end

  test "excludes both issues and pulls from a given  repo" do
    filter = Search::Filters::MemexProjectExclusionFilter.new(
      memex_project_id: @memex,
      repository_id: @repos[0].id
    )

    assert_predicate filter, :valid?
    assert_nil filter.must
    assert_equal(
      {
        terms: {
          issue_id: [
            @issues[0].id,
            @pulls[0].issue.id
          ]
        }
      },
      filter.must_not
    )
  end
end
