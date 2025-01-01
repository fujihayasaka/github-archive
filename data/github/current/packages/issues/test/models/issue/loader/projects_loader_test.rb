# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class ProjectsLoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @repository = create(:repository)
    @issue = create(:issue, repository: @repository)

    @project1 = create(:project, name: "project1", owner: @repository)
    @project2 = create(:project, name: "project2", owner: @repository)

    @context = Issue::Adapter::Context.new(@issue, @repository, @user, cap_filter: cap_authorizing_filter)

    Issue::Loader::CurrentIssue.load_for(@context)
    Issue::Loader::CurrentRepository.load_for(@context)
  end

  test "loading projects only executes expected queries" do
    Platform::Security::RepositoryAccess.with_viewer(@user) do
      result, queries = log_queries do
        Issue::Loader::Projects.load_for(@context, project_ids: [@project1.id, @project2.id])
      end

      # 1 query for loading all projects
      expected_count = 1
      assert_equal expected_count, queries.count

      assert_equal 2, result.size
      assert result.to_h.include?(@project1.id)
      assert result.to_h.include?(@project2.id)
    end
  end
end
