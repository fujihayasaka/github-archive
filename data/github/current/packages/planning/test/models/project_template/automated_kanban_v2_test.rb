# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectTemplateAutomatedKanbanV2Test < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    GitHub.context.push(actor_id: @user.id)

    @template = ProjectTemplate::AutomatedKanbanV2.new
  end

  test "creates a project successfully" do
    project = create(:project)
    project.apply_template(@template)

    assert_equal 3, project.cards.length
    assert_equal 3, project.columns.length
    assert_equal 7, project.project_workflows.length
  end

  test "is a child of ProjectTemplate" do
    assert @template.is_a?(ProjectTemplate)
  end

  test "has the required attributes for rendering the UI" do
    assert ProjectTemplate::AutomatedKanbanV2.title
    assert ProjectTemplate::AutomatedKanbanV2.template_key
    assert ProjectTemplate::AutomatedKanbanV2.description
  end

  test "has the required attributes for historical project data" do
    assert_equal 4, ProjectTemplate::SOURCE_MAPPINGS[@template.class.to_s]
  end

  context "template columns" do
    test "exist when created" do
      assert_equal 3, @template.columns.length
    end

    test "have the necessary attributes for ProjectColumn creation with automation" do
      assert_kind_of Array, @template.columns

      @template.columns.each do |column|
        assert column.is_a?(ProjectColumnTemplate)
        assert column.name
        assert column.purpose
        assert column.workflows.any?
      end
    end

    test "creates valid ProjectColumn data" do
      template_column = @template.columns.first
      project_column = create(:project_column, template_column.data)

      project = create(:project)
      project.apply_template(@template)
      column = project.columns.first

      assert_equal project_column.name, column.name
      assert_equal project_column.purpose, column.purpose
    end
  end

  context "workflows" do
    test "exist when created" do
      workflows = @template.columns.map(&:workflows)
      assert_equal 7, workflows.flatten.length
    end

    test "are attached to the correct columns" do
      project = create(:project)
      project.apply_template(@template)
      todo, in_progress, done = project.columns.map(&:project_workflows)

      assert_equal 1, todo.length
      assert_equal 3, in_progress.length
      assert_equal 3, done.length

      assert_same_elements [ProjectWorkflow::ISSUE_PENDING_CARD_ADDED_TRIGGER], todo.map(&:trigger_type)
      assert_same_elements [ProjectWorkflow::PR_PENDING_CARD_ADDED_TRIGGER, ProjectWorkflow::ISSUE_REOPENED_TRIGGER, ProjectWorkflow::PR_REOPENED_TRIGGER], in_progress.map(&:trigger_type)
      assert_same_elements [ProjectWorkflow::ISSUE_CLOSED_TRIGGER, ProjectWorkflow::PR_MERGED_TRIGGER, ProjectWorkflow::PR_CLOSED_NOT_MERGED_TRIGGER], done.map(&:trigger_type)
    end
  end
end
