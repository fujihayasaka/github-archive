# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class ProjectCardsLoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @repository = create(:repository)
    @issue = create(:issue, repository: @repository)

    @project = create(:project, name: "project1", owner: @repository)
    @project_card1 = create(:pending_project_card, project: @project)
    @project_card2 = create(:pending_project_card, project: @project)

    @context = Issue::Adapter::Context.new(@issue, @repository, @user, cap_filter: cap_authorizing_filter)

    Issue::Loader::CurrentIssue.load_for(@context)
    Issue::Loader::CurrentRepository.load_for(@context)
  end

  test "loading project cards only executes expected queries" do
    result, queries = log_queries do
      Issue::Loader::ProjectCards.load_for(@context, project_card_ids: [@project_card1.id, @project_card2.id])
    end

    # 1 query for loading all project cards
    expected_count = 1
    assert_equal expected_count, queries.count

    assert_equal 2, result.size
    assert result.to_h.include?(@project_card1.id)
    assert result.to_h.include?(@project_card2.id)
  end
end
