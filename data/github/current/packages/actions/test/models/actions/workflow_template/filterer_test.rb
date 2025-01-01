# typed: true
# frozen_string_literal: true

require "test_helper"

class FiltererTest < GitHub::TestCase
  include StarterWorkflowTemplateTestHelpers
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @templates = Actions::WorkflowTemplates.new(@repo, @user)
    @shared_templates = GitHub::JSON.parse(File.read(Rails.root.join("test", "fixtures", "actions_workflow_templates.json")))
    @owner_templates = GitHub::JSON.parse(File.read(Rails.root.join("test", "fixtures", "actions_workflow_owner_templates.json")))
  end

  setup do
    Actions::WorkflowTemplates.any_instance.stubs(:shared_templates).returns(@shared_templates)
    Actions::WorkflowTemplates.any_instance.stubs(:owner_templates).returns(@owner_templates)
  end

  context "#by_id" do
    test "Return template with given id if it exists" do
      Actions::WorkflowTemplates.any_instance.stubs(:shared_templates).returns(@shared_templates[0..3])
      Actions::WorkflowTemplates.any_instance.stubs(:owner_templates).returns(@owner_templates[0..1])
      assert_equal "ci/ruby", workflow_templates_filterer.by_id("ci/ruby").id
      assert_nil workflow_templates_filterer.by_id("invalid-template")
    end
  end

  context "#by_criteria" do
    test "Get all templates without preview" do
      Actions::WorkflowTemplates.any_instance.stubs(:shared_templates).returns(@shared_templates[0..3])
      Actions::WorkflowTemplates.any_instance.stubs(:owner_templates).returns(@owner_templates[2..3])
      assert_templates_unordered ["ci/blank", "ci/ruby", "ci/nodejs", "mynodejs", "myruby"], workflow_templates_filterer.by_criteria(Actions::WorkflowTemplate::Source::ALL, [], [])
    end

    test "Get all templates with preview" do
      Actions::WorkflowTemplates.any_instance.stubs(:shared_templates).returns(@shared_templates[0..3])
      Actions::WorkflowTemplates.any_instance.stubs(:owner_templates).returns(@owner_templates[2..3])
      assert_templates_unordered ["ci/blank", "ci/ruby", "ci/nodejs", "ci/nodejs-preview", "mynodejs", "myruby"], workflow_templates_filterer(nil, nil, true).by_criteria(Actions::WorkflowTemplate::Source::ALL, [], [])
    end

    test "Get all owner templates " do
      assert_templates %w[mynodejs-private mynodejs-internal mynodejs myruby], workflow_templates_filterer.by_criteria(Actions::WorkflowTemplate::Source::OWNER, [], [])
    end

    test "Get all templates of particular category " do
      assert_templates_unordered ["deployments/aaa", "deployments/azure", "deployments/aws", "deployments/alibabacloud"], workflow_templates_filterer.by_criteria(Actions::WorkflowTemplate::Source::SHARED, ["Deployment"], [])
    end

    test "Get category templates with tech stack match" do
      repo_stack = []
      repo_stack.push(RepositoryTechProjectStackContract.new("JavaScript", 300, nil))
      repo_stack.push(RepositoryTechProjectStackContract.new("npm", 0, nil))

      assert_templates_unordered ["ci/nodejs", "ci/grunt", "ci/grunt-with-typescript"], workflow_templates_filterer.by_criteria(Actions::WorkflowTemplate::Source::SHARED, ["Continuous integration"], repo_stack)
    end

    test "Get category templates with tech stack match and onwner's tech stack match as well" do
      Actions::WorkflowTemplates.any_instance.stubs(:owner_templates).returns(@owner_templates[2..3])
      repo_stack = []
      repo_stack.push(RepositoryTechProjectStackContract.new("JavaScript", 300, nil))
      repo_stack.push(RepositoryTechProjectStackContract.new("npm", 0, nil))

      assert_templates_unordered ["ci/nodejs", "ci/grunt", "ci/grunt-with-typescript", "mynodejs"], workflow_templates_filterer.by_criteria(Actions::WorkflowTemplate::Source::ALL, ["Continuous integration"], repo_stack)
    end

    test "Get owner templates with tech stack match " do
      repo_stack = []
      repo_stack.push(RepositoryTechProjectStackContract.new("JavaScript", 300, nil))
      repo_stack.push(RepositoryTechProjectStackContract.new("Ruby", 300, nil))
      repo_stack.push(RepositoryTechProjectStackContract.new("npm", 0, nil))

      assert_templates %w[mynodejs-private mynodejs-internal mynodejs myruby], workflow_templates_filterer.by_criteria(Actions::WorkflowTemplate::Source::OWNER, [], repo_stack)
    end
  end

  def workflow_templates_filterer(user = nil, repo = nil, include_preview_templates = false)
    Actions::WorkflowTemplate::Filterer.new((repo || @repo), (user || @user), include_preview_templates)
  end
end
