# typed: true
# frozen_string_literal: true

require "test_helper"

class RecommenderTest < GitHub::TestCase
  include StarterWorkflowTemplateTestHelpers
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @owner = create(:user)
    @user = @owner
    @repo = create(:private_repository, owner: @owner)
    @templates = Actions::WorkflowTemplates.new(@repo, @user)
    @owner_templates_data = GitHub::JSON.parse(File.read(Rails.root.join("test", "fixtures", "actions_workflow_owner_templates.json")))
    @shared_templates_data = GitHub::JSON.parse(File.read(Rails.root.join("test", "fixtures", "actions_workflow_templates.json")))
  end

  setup do
    Actions::WorkflowTemplates.any_instance.stubs(:shared_templates).returns(@shared_templates_data)
    Actions::WorkflowTemplates.any_instance.stubs(:owner_templates).returns(@owner_templates_data)
    TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[]])
  end

  context "#template_by_id" do
    test "return template by given id if it exist" do
      assert_equal "ci/django", create_template_recommender.template_by_id("ci/django").id
      assert_nil create_template_recommender.template_by_id("non-existent-template")
    end
  end

  context "#get_repo_based_templates" do
    test "return empty template if no tech stacks is present" do
      assert_templates [], create_template_recommender.get_repo_based_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Continuous integration"])
    end

    test "Single matching tech stack(language) with category" do
      stack_percentages = {
        RepositoryTechProjectStackContract.new("Ruby", 100, nil) => 1
      }
      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])

      assert_templates ["myruby", "ci/ruby", "ci/gem-push"], create_template_recommender.get_repo_based_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Continuous integration"])
      assert_templates ["ci/ruby", "ci/gem-push"], create_template_recommender.get_repo_based_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Continuous integration"])
      assert_templates ["myruby"], create_template_recommender.get_repo_based_templates(template_source: Actions::WorkflowTemplate::Source::OWNER, filter_categories: ["Continuous integration"])
    end

    test "Multiple matching tech stack with category" do
      ci_templates = filter_templates_data_by_id(@shared_templates_data, ["ci/blank", "ci/grunt-with-typescript", "ci/grunt", "ci/nodejs"])
      owner_templates = filter_templates_data_by_id(@owner_templates_data, %w[mynodejs myruby])
      Actions::WorkflowTemplates.any_instance.stubs(:shared_templates).returns(ci_templates)
      Actions::WorkflowTemplates.any_instance.stubs(:owner_templates).returns(owner_templates)

      stack_percentages = {
        RepositoryTechProjectStackContract.new("JavaScript", 100, nil) => 0.7,
        RepositoryTechProjectStackContract.new("TypeScript", 100, nil) => 0.3,
        RepositoryTechProjectStackContract.new("npm", 0, nil) => 0,
        RepositoryTechProjectStackContract.new("Grunt", 0, nil) => 0
      }
      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])

      assert_templates ["ci/grunt-with-typescript", "ci/grunt", "mynodejs", "ci/nodejs"], create_template_recommender.get_repo_based_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Continuous integration"])
      assert_templates ["ci/grunt-with-typescript", "ci/grunt", "ci/nodejs"], create_template_recommender.get_repo_based_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Continuous integration"])
      assert_templates ["mynodejs"], create_template_recommender.get_repo_based_templates(template_source: Actions::WorkflowTemplate::Source::OWNER, filter_categories: ["Continuous integration"])
    end

    test "Templates with tech stack matching without category filter" do
      stack_percentages = {
        RepositoryTechProjectStackContract.new("Erlang", 100, nil) => 0.5,
        RepositoryTechProjectStackContract.new("Mix", 0, nil) => 0,
      }
      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])

      assert_templates ["ci/erlang", "ci/elixir"], create_template_recommender.get_repo_based_templates(template_source: Actions::WorkflowTemplate::Source::ALL)
      assert_templates ["ci/erlang", "ci/elixir"], create_template_recommender.get_repo_based_templates(template_source: Actions::WorkflowTemplate::Source::SHARED)
      assert_templates [], create_template_recommender.get_repo_based_templates(template_source: Actions::WorkflowTemplate::Source::OWNER)
    end
  end

  context "#get_templates" do
    test "Templates of a particular category with and without repo tech stacks" do
      ci_templates = filter_templates_data_by_id(@shared_templates_data, ["ci/blank", "ci/nodejs", "ci/ruby", "ci/gem-push", "ci/python-app"])
      deployment_templates = filter_templates_data_by_id(@shared_templates_data, ["deployments/alibabacloud", "deployments/azure"])
      owner_templates = filter_templates_data_by_id(@owner_templates_data, %w[mynodejs myruby])
      Actions::WorkflowTemplates.any_instance.stubs(:shared_templates).returns(ci_templates + deployment_templates)
      Actions::WorkflowTemplates.any_instance.stubs(:owner_templates).returns(owner_templates)

      assert_templates_unordered ["mynodejs", "myruby", "ci/nodejs", "ci/ruby", "ci/gem-push", "ci/python-app"], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Continuous integration"])
      assert_templates_unordered ["ci/nodejs", "ci/ruby", "ci/gem-push", "ci/python-app"], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Continuous integration"])
      assert_templates_unordered %w[mynodejs myruby], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::OWNER, filter_categories: ["Continuous integration"])
      assert_templates_including_unordered [], ["deployments/azure", "deployments/alibabacloud", "mynodejs", "myruby"], create_template_recommender(@owner, @repo).get_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Deployment"]), true
      assert Set["deployments/azure", "deployments/alibabacloud"] == create_template_recommender(@owner, @repo).get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Deployment"]).collect(&:id).to_set

      stack_percentages = {
        RepositoryTechProjectStackContract.new("JavaScript", 50, nil) => 0.5,
        RepositoryTechProjectStackContract.new("npm", 0, nil) => 0
      }

      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])
      assert_templates_including_unordered ["mynodejs", "ci/nodejs"], ["ci/python-app", "ci/ruby", "ci/gem-push", "myruby"], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Continuous integration"])
      assert_templates_including_unordered ["ci/nodejs"], ["ci/ruby", "ci/gem-push", "ci/python-app"], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Continuous integration"])
      assert_templates_including_unordered ["mynodejs"], ["myruby"], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::OWNER, filter_categories: ["Continuous integration"])
      assert_templates_including_unordered ["mynodejs"], ["deployments/azure", "deployments/alibabacloud", "myruby"], create_template_recommender(@owner, @repo).get_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Deployment"]), true
      assert Set["deployments/azure", "deployments/alibabacloud"] == create_template_recommender(@owner, @repo).get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Deployment"]).collect(&:id).to_set
    end

    test "Templates of multiple category with and without tech stacks" do
      ci_templates = filter_templates_data_by_id(@shared_templates_data, ["ci/blank", "ci/nodejs", "ci/ruby", "ci/gem-push", "ci/docker-image", "ci/python-app"])
      deployment_templates = filter_templates_data_by_id(@shared_templates_data, ["deployments/alibabacloud", "deployments/azure", "deployments/aws"])
      automation_templates = filter_templates_data_by_id(@shared_templates_data, ["automation/greetings"])
      owner_templates = filter_templates_data_by_id(@owner_templates_data, %w[mynodejs myruby])
      Actions::WorkflowTemplates.any_instance.stubs(:shared_templates).returns(ci_templates + automation_templates + deployment_templates)
      Actions::WorkflowTemplates.any_instance.stubs(:owner_templates).returns(owner_templates)

      assert_templates_unordered ["mynodejs", "myruby", "ci/nodejs", "ci/ruby", "ci/docker-image", "ci/python-app", "ci/gem-push", "automation/greetings"], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Continuous integration", "Automation"])
      assert_templates_unordered ["ci/nodejs", "ci/ruby", "ci/docker-image", "ci/python-app", "ci/gem-push", "automation/greetings"], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Continuous integration", "Automation"])
      assert_templates_unordered %w[mynodejs myruby], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::OWNER, filter_categories: ["Continuous integration", "Automation"])
      assert_templates_including_unordered [], ["deployments/azure", "deployments/alibabacloud", "deployments/aws", "mynodejs", "myruby", "ci/nodejs", "ci/ruby", "ci/docker-image", "ci/python-app", "ci/gem-push", "automation/greetings"], create_template_recommender(@owner, @repo).get_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Continuous integration", "Automation", "Deployment"]), true
      assert_templates_including_unordered [], ["deployments/azure", "deployments/alibabacloud", "deployments/aws", "ci/nodejs", "ci/ruby", "ci/docker-image", "ci/python-app", "ci/gem-push", "automation/greetings"], create_template_recommender(@owner, @repo).get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Continuous integration", "Automation", "Deployment"]), true

      stack_percentages = {
        RepositoryTechProjectStackContract.new("JavaScript", 60, nil) => 0.6,
        RepositoryTechProjectStackContract.new("Ruby", 40, nil) => 0.4,
        RepositoryTechProjectStackContract.new("npm", 0, nil) => 0
      }

      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])

      assert_templates_including_unordered ["mynodejs", "ci/nodejs", "myruby", "ci/ruby", "ci/gem-push"], ["ci/docker-image", "ci/python-app", "automation/greetings"], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Continuous integration", "Automation"])
      assert_templates_including_unordered ["ci/nodejs", "ci/ruby", "ci/gem-push"], ["ci/docker-image", "ci/python-app", "automation/greetings"], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Continuous integration", "Automation"])
      assert_templates %w[mynodejs myruby], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::OWNER, filter_categories: ["Continuous integration", "Automation"])
      assert_templates_including_unordered ["mynodejs", "ci/nodejs", "myruby", "ci/ruby", "ci/gem-push"], ["deployments/alibabacloud", "deployments/aws", "deployments/azure", "ci/docker-image", "ci/python-app", "automation/greetings"], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Continuous integration", "Automation", "Deployment"]), true
      assert_templates_including_unordered ["ci/nodejs", "ci/ruby", "ci/gem-push"], ["deployments/azure", "deployments/aws", "deployments/alibabacloud", "ci/docker-image", "ci/python-app", "automation/greetings"], create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Continuous integration", "Automation", "Deployment"]), true

    end

    test "security templates recommendation for Security Category" do
      stack_percentages = {
        RepositoryTechProjectStackContract.new("Ruby", 60, nil) => 0.5,
        RepositoryTechProjectStackContract.new("C", 40, nil) => 0.5
      }
      Repository.any_instance.stubs(:show_code_scanning_workflows_in_actions?).returns(true)
      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])
      templates_result = create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Code Scanning"])
      assert_templates_including_unordered ["code-scanning/codeql", "code-scanning/devskim"], ["code-scanning/prisma", "code-scanning/detekt", "code-scanning/anchore"], templates_result, false

    end

    test "security template recommendation when codeql weight is less" do
      # Even if codeql weight is lesser then it should be the first template in the list.
      Repository.any_instance.stubs(:show_code_scanning_workflows_in_actions?).returns(true)
      stack_percentages = {
        RepositoryTechProjectStackContract.new("JavaScript", 60, nil) => 0.3,
        RepositoryTechProjectStackContract.new("Ruby", 40, nil) => 0.1,
        RepositoryTechProjectStackContract.new("PHP", 100, nil) => 0.5
      }
      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])
      templates_result = create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Code Scanning"])
      assert_templates_including_unordered ["code-scanning/codeql", "code-scanning/devskim"], ["code-scanning/prisma", "code-scanning/detekt", "code-scanning/anchore"], templates_result, false
      assert templates_result[0].weight < templates_result[1].weight
    end

    test "security template recommendation when codeql weight is zero" do
      # If codeql weight weight is zero then it should not be the first template but will be the first template among all zero weight templates.
      Repository.any_instance.stubs(:show_code_scanning_workflows_in_actions?).returns(true)

      stack_percentages = {
        RepositoryTechProjectStackContract.new("PHP", 100, nil) => 0.8,
        RepositoryTechProjectStackContract.new("Dockerfile", 20, nil) => 0.2
      }
      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])

      templates_result = create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Code Scanning"])
      assert_templates_including_unordered ["code-scanning/devskim", "code-scanning/anchore"], ["code-scanning/codeql", "code-scanning/prisma", "code-scanning/detekt",], templates_result, false
      assert templates_result[2].id == "code-scanning/codeql"
      assert templates_result[2].weight == 0
    end

    test "security templates on view all page" do
      ci_templates = filter_templates_data_by_id(@shared_templates_data, ["ci/blank", "ci/nodejs", "ci/ruby", "ci/gem-push", "ci/docker-image", "ci/python-app"])
      deployment_templates = filter_templates_data_by_id(@shared_templates_data, ["deployments/alibabacloud", "deployments/azure", "deployments/aws"])
      automation_templates = filter_templates_data_by_id(@shared_templates_data, ["automation/greetings"])
      security_templates = filter_templates_data_by_id(@shared_templates_data, ["code-scanning/codeql", "code-scanning/devskim", "code-scanning/prisma", "code-scanning/detekt", "code-scanning/anchore"])
      Actions::WorkflowTemplates.any_instance.stubs(:shared_templates).returns(ci_templates + automation_templates + deployment_templates + security_templates)

      stack_percentages = {
        RepositoryTechProjectStackContract.new("JavaScript", 50, nil) => 0.5,
        RepositoryTechProjectStackContract.new("Ruby", 50, nil) => 0.4,
        RepositoryTechProjectStackContract.new("Dockerfile", 20, nil) => 0.1
      }

      Repository.any_instance.stubs(:show_code_scanning_workflows_in_actions?).returns(true)
      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])
      # First the templates should be ordered based on weight and if weight is same then CI/CD templates should take precedence.
      templates_result = create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Continuous integration", "Automation", "Deployment", "Code Scanning"])
      assert_templates_including_unordered ["ci/nodejs", "ci/ruby", "ci/gem-push", "code-scanning/codeql", "code-scanning/devskim", "ci/docker-image", "deployments/alibabacloud", "code-scanning/anchore"], ["deployments/azure", "deployments/aws", "code-scanning/detekt", "code-scanning/prisma", "ci/python-app", "automation/greetings"], templates_result, true
    end

    test "owner templates recommendation without tech stacks" do
      owner_templates = filter_templates_data_by_id(@owner_templates_data, %w[mynodejs-private mynodejs-internal mynodejs myruby])
      Actions::WorkflowTemplates.any_instance.stubs(:owner_templates).returns(owner_templates)

      templates_result = create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::OWNER)
      assert_templates %w[mynodejs-private mynodejs-internal mynodejs myruby], templates_result
    end

    test "owner templates recommendation with tech stack" do
      owner_templates = filter_templates_data_by_id(@owner_templates_data, %w[mynodejs-private mynodejs-internal mynodejs myruby])
      Actions::WorkflowTemplates.any_instance.stubs(:owner_templates).returns(owner_templates)

      stack_percentages = {
        RepositoryTechProjectStackContract.new("JavaScript", 50, nil) => 0.8,
        RepositoryTechProjectStackContract.new("Dockerfile", 20, nil) => 0.2
      }

      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])

      templates_result = create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::OWNER)
      assert_templates %w[mynodejs-private mynodejs-internal mynodejs myruby], templates_result
    end

    test "owner templates recommendation with internal template has higher weight" do
      owner_templates = filter_templates_data_by_id(@owner_templates_data, %w[mynodejs-private mynodejs-internal mynodejs myruby])
      Actions::WorkflowTemplates.any_instance.stubs(:owner_templates).returns(owner_templates)


      internal_template = RepositoryActions::Onboarding::Template.new(owner_templates[1])
      internal_template.add_weight(100)

      Actions::WorkflowTemplate::Recommender.any_instance.stubs(:filter_templates).returns(owner_templates.map do |template|
        if template == owner_templates[1]
          internal_template
        else
          RepositoryActions::Onboarding::Template.new(template)
        end
      end)

      templates_result = create_template_recommender.get_templates(template_source: Actions::WorkflowTemplate::Source::OWNER)
      assert_templates %w[mynodejs-internal mynodejs-private mynodejs myruby], templates_result
    end

    test "preview templates recommendation" do
      ci_templates = filter_templates_data_by_id(@shared_templates_data, ["ci/blank", "ci/nodejs", "ci/nodejs-preview", "ci/ruby", "ci/gem-push", "ci/python-app"])
      owner_templates = filter_templates_data_by_id(@owner_templates_data, %w[mynodejs myruby])
      Actions::WorkflowTemplates.any_instance.stubs(:shared_templates).returns(ci_templates)
      Actions::WorkflowTemplates.any_instance.stubs(:owner_templates).returns(owner_templates)

      assert_templates_unordered ["ci/nodejs", "ci/ruby", "ci/gem-push", "ci/python-app", "ci/nodejs-preview"], create_template_recommender_preview.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Continuous integration"])

      stack_percentages = {
        RepositoryTechProjectStackContract.new("JavaScript", 50, nil) => 0.5,
        RepositoryTechProjectStackContract.new("npm", 0, nil) => 0
      }

      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])
      assert_templates_including_unordered ["mynodejs", "ci/nodejs", "ci/nodejs-preview"], ["ci/python-app", "ci/ruby", "ci/gem-push", "myruby"], create_template_recommender_preview.get_templates(template_source: Actions::WorkflowTemplate::Source::ALL, filter_categories: ["Continuous integration"])
      assert_templates_including_unordered ["ci/nodejs", "ci/nodejs-preview"], ["ci/ruby", "ci/gem-push", "ci/python-app"], create_template_recommender_preview.get_templates(template_source: Actions::WorkflowTemplate::Source::SHARED, filter_categories: ["Continuous integration"])
    end
  end

  def create_template_recommender(user = nil, repo = nil)
    Actions::WorkflowTemplate::Recommender.new((repo || @repo), (user || @user))
  end

  def create_template_recommender_preview(user = nil, repo = nil)
    Actions::WorkflowTemplate::Recommender.new((repo || @repo), (user || @user), true)
  end
end
