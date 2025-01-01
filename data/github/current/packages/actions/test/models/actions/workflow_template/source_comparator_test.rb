# typed: true
# frozen_string_literal: true

require "test_helper"

class SourceComparatorTest < GitHub::TestCase
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
    test "template source which is appliable for source comparator" do
      assert_equal true, Actions::WorkflowTemplate::SourceComparator.applicable?(Actions::WorkflowTemplate::Source::ALL)
    end

    test "template source which is not appliable for source comparator" do
      assert_equal false, Actions::WorkflowTemplate::SourceComparator.applicable?(Actions::WorkflowTemplate::Source::SHARED)
    end
  end

  # 1 returned value means second template will go first
  # -1 returned value means first template will go first
  # 0 returned value means no change
  context "#compare" do
    test "One of the template is from owner and other from non-owner" do
      my_nodejs = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("mynodejs"))
      nodejs = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("ci/nodejs"))
      assert_equal -1, Actions::WorkflowTemplate::SourceComparator.new.compare(my_nodejs, nodejs), "First template from onwer and second from non-owner should return -1"
      assert_equal 1, Actions::WorkflowTemplate::SourceComparator.new.compare(nodejs, my_nodejs), "First template from non-onwer and second from owner should return 1"
    end

    test "Both templates are either from onwer or non-owner" do
      ruby = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("ci/ruby"))
      nodejs = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("ci/nodejs"))
      my_nodejs = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("mynodejs"))
      my_ruby = RepositoryActions::Onboarding::Template.new(@templates.get_by_id("myruby"))

      assert_equal 0, Actions::WorkflowTemplate::SourceComparator.new.compare(ruby, nodejs), "Both templates (non-owner) should return 0"
      assert_equal 0, Actions::WorkflowTemplate::SourceComparator.new.compare(my_nodejs, my_ruby), "Both templates (owner) should return 0"
    end
  end
end
