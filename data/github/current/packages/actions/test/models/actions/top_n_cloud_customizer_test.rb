# typed: false
# frozen_string_literal: true

require "test_helper"

class TopNCloudCustomizerTest < GitHub::TestCase
  include StarterWorkflowTemplateTestHelpers

  fixtures do
    @owner = create(:user)
    @repository = create(:private_repository, owner: @owner)
  end

  setup do
    TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[]])
  end

  context "#customize_templates" do
    test "if sorted popular templates are returned in case of no tech_stacks are present in the repo" do
      templates = get_templates_with_id(%w[Python_Google Python_HashiCorp Python_Tencent Python_IBM Java_Lambda_Functions Java_Azure_Functions])
      non_relevant_template_ids = ["deployments/azure", "deployments/aws", "deployments/google", "deployments/terraform", "deployments/alibabacloud", "deployments/ibm", "deployments/tencent", "deployments/openshift"]
      non_relevant_templates = get_templates_with_id(non_relevant_template_ids)

      stack_percentages = nil
      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])

      assert_templates non_relevant_template_ids, Actions::TopNCloudCustomizer.customize_templates(templates, non_relevant_templates, **{ repository: @repository, max_num_of_templates: 8 })
    end

    test "if sorted popular templates are returned in case of no languages present in the repo" do
      templates = get_templates_with_id(%w[Java_Azure_Functions Java_Lambda_Functions Python_Google Python_HashiCorp Python_IBM Python_Tencent])

      non_relevant_template_ids = ["deployments/azure", "deployments/aws", "deployments/google", "deployments/terraform", "deployments/alibabacloud", "deployments/ibm", "deployments/tencent", "deployments/openshift"]
      non_relevant_templates = get_templates_with_id(non_relevant_template_ids)

      stack_percentages = {
        RepositoryTechProjectStackContract.new("Azure Functions", 0, nil) => 0
      }
      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])

      assert_templates non_relevant_template_ids, Actions::TopNCloudCustomizer.customize_templates(templates, non_relevant_templates, **{ repository: @repository, max_num_of_templates: 8 })
    end

    test "if a single repo-based cloud template is getting rendered" do
      templates = get_templates_with_id(["C#_Azure_Functions"])
      i = 100
      templates.each { |template| template.weight = i += 1 }

      stack_percentages = {
        RepositoryTechProjectStackContract.new("C#", 505, nil) => 0.81,
        RepositoryTechProjectStackContract.new("Java", 118, nil) => 0.19,
        RepositoryTechProjectStackContract.new("Azure Functions", 0, nil) => 0
      }
      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])

      non_relevant_template_ids = ["deployments/azure", "deployments/alibabacloud", "deployments/aws", "deployments/google", "deployments/terraform", "deployments/ibm", "deployments/openshift", "deployments/tencent"]
      non_relevant_templates = get_templates_with_id(non_relevant_template_ids)

      assert_templates_including_non_relevant_subset templates.collect(&:id), non_relevant_template_ids, Actions::TopNCloudCustomizer.customize_templates(templates, non_relevant_templates, **{ repository: @repository, max_num_of_templates: 8 })
    end

    test "if 2nd ranked repo-based language templates for a cloud are picked up provided max_num_of_templates count is not hit" do
      templates = get_templates_with_id(%w[Python_Google Python_HashiCorp Python_IBM Python_Tencent Java_Azure_Functions Java_Lambda_Functions Java_Lambda_Functions2])
      aws_templates = []
      i = 100
      templates.each do |template|
        template.weight = i += 1
        aws_templates.append(template) if template.creator == "Amazon Web Services"
      end

      stack_percentages = {
      RepositoryTechProjectStackContract.new("Java", 100, nil) => 0.60,
      RepositoryTechProjectStackContract.new("Python", 100, nil) => 0.40
      }

      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])

      aws_templates.sort { |a, b| b.weight <=> a.weight }
      repo_based_template_ids = ["Java_Azure_Functions"].append(aws_templates[0].id).concat(%w[Python_Google Python_HashiCorp Python_IBM Python_Tencent]).append(aws_templates[1].id)
      non_relevant_template_ids = ["deployments/azure", "deployments/alibabacloud", "deployments/aws", "deployments/google", "deployments/terraform", "deployments/ibm", "deployments/openshift", "deployments/tencent"]
      non_relevant_templates = get_templates_with_id(non_relevant_template_ids)

      assert_templates_including_non_relevant_subset repo_based_template_ids, non_relevant_template_ids, Actions::TopNCloudCustomizer.customize_templates(templates, non_relevant_templates, **{ repository: @repository, max_num_of_templates: 8 })
    end

    test "if Docker gets rendered first" do
      templates = get_templates_with_id(%w[Python_Google Python_HashiCorp Python_IBM Python_Tencent Java_Azure_Functions Java_Lambda_Functions Java_Lambda_Functions2 Docker_cloud])
      aws_templates = []
      i = 100
      templates.each do |template|
        template.weight = i += 1
        aws_templates.append(template) if template.creator == "Amazon Web Services"
      end

      stack_percentages = {
      RepositoryTechProjectStackContract.new("Java", 60, nil) => 0.60,
      RepositoryTechProjectStackContract.new("Python", 39, nil) => 0.39,
      RepositoryTechProjectStackContract.new("Dockerfile", 1, nil) => 0.01
      }

      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])

      aws_templates.sort { |a, b| b.weight <=> a.weight }
      non_relevant_template_ids = ["deployments/azure", "deployments/alibabacloud", "deployments/aws", "deployments/google", "deployments/terraform", "deployments/ibm", "deployments/openshift", "deployments/tencent"]
      non_relevant_templates = get_templates_with_id(non_relevant_template_ids)

      assert_templates_including_non_relevant_subset %w[Docker_cloud Java_Azure_Functions].append(aws_templates[0].id).concat(%w[Python_Google Python_HashiCorp Python_IBM Python_Tencent]).append(aws_templates[1].id), non_relevant_template_ids, Actions::TopNCloudCustomizer.customize_templates(templates, non_relevant_templates, **{ repository: @repository, max_num_of_templates: 8 })
    end

    test "if only a maximum of 8 templates are picked up for ordering" do
      templates = get_templates_with_id(%w[Python_Google Python_HashiCorp Python_IBM Python_Tencent Java_Azure_Functions Java_Lambda_Functions Java_Lambda_Functions2 Python_Google2 Python_Google3])

      aws_templates = []
      gcp_templates = []
      i = 100
      templates.each do |template|
        template.weight = i += 1
        if template.creator == "Amazon Web Services"
          aws_templates.append(template)
        elsif template.creator == "Google Cloud"
          gcp_templates.append(template)
        end
      end

      stack_percentages = {
      RepositoryTechProjectStackContract.new("Java", 100, nil) => 0.60,
      RepositoryTechProjectStackContract.new("Python", 100, nil) => 0.40
      }

      TechProjectStackAnalysis.stubs(:tech_projects_with_stack_percentages).returns([[".", stack_percentages]])
      aws_templates.sort { |a, b| b.weight <=> a.weight }
      gcp_templates.sort { |a, b| b.weight <=> a.weight }
      repo_based_template_ids = ["Java_Azure_Functions"].append(aws_templates[0].id).concat(%w[Python_Google Python_HashiCorp Python_IBM Python_Tencent]).append(aws_templates[1].id).append(gcp_templates[0].id)

      non_relevant_template_ids = ["deployments/azure", "deployments/alibabacloud", "deployments/aws", "deployments/google", "deployments/terraform", "deployments/ibm", "deployments/openshift", "deployments/tencent"]
      non_relevant_templates = get_templates_with_id(non_relevant_template_ids)

      assert_templates_including_non_relevant_subset %w[Java_Azure_Functions Java_Lambda_Functions Python_Google Python_HashiCorp Python_IBM Python_Tencent Java_Lambda_Functions2 Python_Google2], non_relevant_template_ids, Actions::TopNCloudCustomizer.customize_templates(templates, non_relevant_templates, **{ repository: @repository, max_num_of_templates: 8 })
    end

  end
end
