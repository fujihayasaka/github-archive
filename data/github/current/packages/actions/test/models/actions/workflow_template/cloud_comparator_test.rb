# typed: true
# frozen_string_literal: true

require "test_helper"

class CloudComparatorTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @templates = Actions::WorkflowTemplates.new(@repo, @user)
    @owner_templates_data = GitHub::JSON.parse(File.read(Rails.root.join("test", "fixtures", "actions_workflow_owner_templates.json")))
    @non_owner_templates_data = GitHub::JSON.parse(File.read(Rails.root.join("test", "fixtures", "actions_workflow_templates.json")))
  end

  setup do
    Actions::WorkflowTemplates.any_instance.stubs(:all).returns(@owner_templates_data + @non_owner_templates_data)
  end

  context "#applicable" do
    test "category which is appliable" do
      assert_equal true, Actions::WorkflowTemplate::CloudComparator.applicable?(["deployment"])
    end

    test "category which is not appliable" do
      assert_equal false, Actions::WorkflowTemplate::CloudComparator.applicable?(["automation"])
    end
  end

  # 1 returned value means second template will go first
  # -1 returned value means first template will go first
  # 0 returned value means no change
  context "#compare" do
    test "One or more of the templates are not cloud templates" do
      my_nodejs = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("mynodejs"))
      nodejs = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("ci/nodejs"))
      assert_equal 0, Actions::WorkflowTemplate::CloudComparator.new.compare(my_nodejs, nodejs), "Since one or more of the templates are not cloud templates, it should return 0"
    end

    test "One of the templates is azure" do
      azure = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("deployments/azure"))
      aws = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("deployments/aws"))

      assert_equal -1, Actions::WorkflowTemplate::CloudComparator.new.compare(azure, aws), "Azure should be returned first, ie., -1"
      assert_equal 1, Actions::WorkflowTemplate::CloudComparator.new.compare(aws, azure), "Azure should be returned first, ie., 1"
    end

    test "Both the templates are azure" do
      azure1 = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("deployments/azure"))
      azure2 = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("deployments/azure"))

      assert_equal 0, Actions::WorkflowTemplate::CloudComparator.new.compare(azure1, azure2), "Since both templates are azure, no change in order, ie., 0"
      assert_equal 0, Actions::WorkflowTemplate::CloudComparator.new.compare(azure2, azure1), "Since both templates are azure, no change in order, ie., 0"
    end

    test "None of the templates are azure" do
      aws = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("deployments/aws"))
      alibaba = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("deployments/alibabacloud"))

      assert_equal -1, Actions::WorkflowTemplate::CloudComparator.new.compare(aws, alibaba), "aws should come first, ie., -1"
      assert_equal 1, Actions::WorkflowTemplate::CloudComparator.new.compare(alibaba, aws), "aws should come first, ie., 1"
    end

    test "Popular Templates precede normal templates" do
      aaa = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("deployments/aaa"))
      alibaba = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("deployments/alibabacloud"))

      assert_equal 1, Actions::WorkflowTemplate::CloudComparator.new.compare(aaa, alibaba), "alibaba should come first as as it's a popular template, ie., 1"
      assert_equal -1, Actions::WorkflowTemplate::CloudComparator.new.compare(alibaba, aaa), "alibaba should come first as as it's a popular template, ie., -1"
    end
  end
end
