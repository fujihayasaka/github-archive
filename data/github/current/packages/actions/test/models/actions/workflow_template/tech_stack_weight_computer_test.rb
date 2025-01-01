# typed: true
# frozen_string_literal: true

require "test_helper"

class TechStackWeightComputerTest < GitHub::TestCase
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

  context "#compute" do
    test "template with matching/non-matching tech stack" do
      stack_percentages = {
        RepositoryTechProjectStackContract.new("Python", 300, nil) => 1,
        RepositoryTechProjectStackContract.new("Django", 0, nil) => 0,
        RepositoryTechProjectStackContract.new("Pip", 0, nil) => 0
      }
      nodejs = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("ci/nodejs"))
      django = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("ci/django"))

      assert_equal 0, Actions::WorkflowTemplate::TechStackWeightComputer.new(stack_percentages).compute(nodejs), "template with no matching tech stacks should have 0 weight"
      # Expected weight 600 -> (500 + 100) * 1
      assert_equal 700, Actions::WorkflowTemplate::TechStackWeightComputer.new(stack_percentages).compute(django), "template with matching tech stacks should have non-zero weight"
    end

    test "template with multiple matching language and non-language tech stack " do
      stack_percentages = {
        RepositoryTechProjectStackContract.new("Javascript", 300, nil) => 0.7,
        RepositoryTechProjectStackContract.new("Typescript", 300, nil) => 0.2,
        RepositoryTechProjectStackContract.new("npm", 0, nil) => 0,
        RepositoryTechProjectStackContract.new("Grunt", 0, nil) => 0
      }
      python_with_cpp = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("ci/grunt-with-typescript"))

      # Expected weight 630 -> (500 + 100 + 100) * 0.9
      assert_equal 630, Actions::WorkflowTemplate::TechStackWeightComputer.new(stack_percentages).compute(python_with_cpp).round
    end
  end
end
