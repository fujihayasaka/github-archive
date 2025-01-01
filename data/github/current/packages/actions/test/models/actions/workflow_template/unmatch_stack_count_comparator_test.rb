# typed: true
# frozen_string_literal: true

require "test_helper"

class UnmatchStackCountComparatorTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @templates = Actions::WorkflowTemplates.new(@repo, @user)
    @all_templates = GitHub::JSON.parse(File.read(Rails.root.join("test", "fixtures", "actions_workflow_templates.json")))
  end

  setup do
    Actions::WorkflowTemplates.any_instance.stubs(:all).returns(@all_templates)
  end

  context "#applicable" do
    test "category which is appliable for unmatch stack comparator" do
      assert_equal true, Actions::WorkflowTemplate::UnmatchStackCountComparator.applicable?(["Continuous integration"])
    end

    test "category which is not appliable for unmatch stack comparator" do
      assert_equal false, Actions::WorkflowTemplate::UnmatchStackCountComparator.applicable?(["Automation"])
    end
  end

  # 1 returned value means second template will go first
  # -1 returned value means first template will go first
  # 0 returned value means no change
  context "#compare" do
    test "Two templates with different unmatch tech stack count" do
      repo_stack = []
      repo_stack.push(RepositoryTechProjectStackContract.new("JavaScript", 300, nil))
      repo_stack.push(RepositoryTechProjectStackContract.new("npm", 0, nil))
      grunt_with_typescript = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("ci/grunt-with-typescript"))
      grunt = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("ci/grunt"))
      nodejs = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("ci/nodejs"))
      assert_equal -1, Actions::WorkflowTemplate::UnmatchStackCountComparator.new(repo_stack).compare(nodejs, grunt), "First template with zero non-match tech stack and second one have non-zero should return -1"
      assert_equal 1, Actions::WorkflowTemplate::UnmatchStackCountComparator.new(repo_stack).compare(grunt, nodejs), "Second template with zero non-match tech stack and first one with zero  should return 1"
      assert_equal 0, Actions::WorkflowTemplate::UnmatchStackCountComparator.new(repo_stack).compare(grunt, grunt_with_typescript), "First template with less non-match tech stack then second one should return -1"
      assert_equal 0, Actions::WorkflowTemplate::UnmatchStackCountComparator.new(repo_stack).compare(grunt_with_typescript, grunt), "Second template with less non-match tech stack then first one should return 1"
    end

    test "Templates with same non-matching tech stacks" do
      repo_stack = []
      repo_stack.push(RepositoryTechProjectStackContract.new("Java", 300, nil))

      gradle = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("ci/gradle"))
      maven = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("ci/maven"))
      assert_equal 0, Actions::WorkflowTemplate::UnmatchStackCountComparator.new(repo_stack).compare(maven, gradle)
    end
  end
end
