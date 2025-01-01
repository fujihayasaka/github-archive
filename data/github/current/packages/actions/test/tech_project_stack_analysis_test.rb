# typed: false
# frozen_string_literal: true

require "test_helper"

class TechProjectStackAnalysisTest < GitHub::TestCase
  include PushTestHelper

  fixtures do
    @repo = create(:repository)
  end

  context "#tech_projects_with_stack_percentages" do
    test "it returns an empty project" do
      TechProjectStackAnalysis.stubs(:tech_projects_with_stacks).returns []
      tech_projects_with_stack_percentages = [].map { |project| [project.path, project.get_stack_percentages] }
      assert_equal [], TechProjectStackAnalysis.tech_projects_with_stack_percentages(@repo)
    end

    test "it checks if project size is 0 with nil stacks" do
      project = RepositoryTechProjectContract.new(".", nil)
      assert_equal project.project_size, 0
    end

    test "it returns project with descending order of stack percentages" do
      stack1 = RepositoryTechProjectStackContract.new("Java", 20, "{}")
      stack2 = RepositoryTechProjectStackContract.new("npm", 0, '{"npm.packageJsonPath": "contoso/front-end/package.json"}')
      stack3 = RepositoryTechProjectStackContract.new("Python", 30, "{}")
      stacks_array = [stack1, stack2, stack3]
      project = RepositoryTechProjectContract.new(".", stacks_array)
      project.size_of_project = project.project_size
      projects_array = [project]
      TechProjectStackAnalysis.stubs(:tech_project_stacks).returns projects_array
      tech_projects_with_stack_percentages = projects_array.map { |project| [project.path, project.get_stack_percentages] }
      assert_equal tech_projects_with_stack_percentages, TechProjectStackAnalysis.tech_projects_with_stack_percentages(@repo)
      assert_equal tech_projects_with_stack_percentages[0][0], "."
      assert_equal tech_projects_with_stack_percentages[0][1].keys[0].name, "Python"
      assert_equal tech_projects_with_stack_percentages[0][1].keys[0].settings, "{}"
      assert_equal tech_projects_with_stack_percentages[0][1].keys[1].name, "Java"
      assert_equal tech_projects_with_stack_percentages[0][1].keys[1].settings, "{}"
      assert_equal tech_projects_with_stack_percentages[0][1].keys[2].name, "npm"
      assert_equal tech_projects_with_stack_percentages[0][1].keys[2].settings, '{"npm.packageJsonPath": "contoso/front-end/package.json"}'
    end

    test "it falls back to language breakdown when tech stacks are not found" do
      languages = {}
      languages["Shell"] = 10
      languages["JavaScript"] = 25
      languages["C#"] = 20

      @repo.stubs(:language_breakdown).returns(languages)
      TechStacks.stubs(:tech_project_stacks).returns []

      projects = TechProjectStackAnalysis.tech_projects_with_stack_percentages(@repo)

      refute_equal [], projects
      assert_equal "JavaScript", projects[0][1].keys[0].name
      assert_equal 25, projects[0][1].keys[0].size
      assert_equal "C#", projects[0][1].keys[1].name
      assert_equal 20, projects[0][1].keys[1].size
      assert_equal "Shell", projects[0][1].keys[2].name
      assert_equal 10, projects[0][1].keys[2].size
    end

  end

end
