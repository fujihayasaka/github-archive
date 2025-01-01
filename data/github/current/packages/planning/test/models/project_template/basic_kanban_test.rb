# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectTemplateBasicKanbanTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    user = create(:user)
    GitHub.context.push(actor_id: user.id)

    @template = ProjectTemplate::BasicKanban.new
  end

  test "creates a project successfully" do
    project = create(:project)
    project.apply_template(@template)

    assert_equal 3, project.cards.length
    ordered_card_notes = project.columns[0].cards.order(priority: :desc).pluck(:note)
    assert_match /Welcome to GitHub projects/, ordered_card_notes.first
    assert_match /Automatically move your cards/, ordered_card_notes.last
    assert_empty project.columns[1].cards
    assert_empty project.columns[2].cards
    assert_equal 3, project.columns.length
    assert_equal 0, project.project_workflows.length
  end

  test "prioritizes column cards correctly when feature flagged" do
    project = create(:project)
    project.apply_template(ProjectTemplate::BasicKanban.new)

    assert_equal 3, project.cards.length
    ordered_card_notes = project.columns[0].cards.order(priority: :desc).pluck(:note)
    assert_match /Welcome to GitHub projects/, ordered_card_notes.first
    assert_match /Automatically move your cards/, ordered_card_notes.last
    assert_empty project.columns[1].cards
    assert_empty project.columns[2].cards
    assert_equal 3, project.columns.length
    assert_equal 0, project.project_workflows.length
  end

  test "is a child of ProjectTemplate" do
    assert @template.is_a?(ProjectTemplate)
  end

  test "has the required attributes for rendering the UI" do
    assert ProjectTemplate::BasicKanban.title
    assert ProjectTemplate::BasicKanban.template_key
    assert ProjectTemplate::BasicKanban.description
  end

  test "has the required attributes for historical project data" do
    assert_equal 1, ProjectTemplate::SOURCE_MAPPINGS[@template.class.to_s]
  end

  context "template columns" do
    test "exist when created" do
      assert_equal 3, @template.columns.length
    end

    test "have the necessary attributes for ProjectColumn creation" do
      assert_kind_of Array, @template.columns

      @template.columns.each do |column|
        assert column.is_a?(ProjectColumnTemplate)
        assert column.name
        assert column.workflows.empty?
      end
    end

    test "creates valid ProjectColumn data" do
      column = @template.columns.first
      project_column = create(:project_column, column.data)

      project = create(:project)
      project.apply_template(@template)
      assert_equal project_column.name, project.columns.first.name
    end
  end
end
