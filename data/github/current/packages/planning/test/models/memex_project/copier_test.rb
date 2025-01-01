# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectCopierTest < GitHub::TestCase
  fixtures do
    @creator = create(:verified_user)

    @base_project = create(:memex_project, title: "Base Project")

    # Modify the system status field (see https://github.com/github/memex/issues/14161)
    status_field = @base_project.status_column
    settings = MemexProjectColumn::Settings.new(status_field.data_type, status_field.settings.with_indifferent_access)

    # Remove the "Todo" option
    todo_option = settings.options.find { |o| o.name == "Todo" }
    settings.delete_option(todo_option.id)

    # Rename the "In Progress" option
    todo_option = settings.options.find { |o| o.name == "In Progress" }
    settings.update_option(todo_option.id, name: "P0", color: "GRAY", description: "",)

    # Creates a target project to test a new project made from a template
    @target_project = create(:memex_project, title: "Target Project")

    # Add some new options
    settings.add_option(name: "😂", color: "RED", description: "😂")
    settings.add_option(name: "😔", color: "BLUE", description: "")
    settings.add_option(name: "🤔", color: "GRAY", description: "")
    status_field.update(settings: settings.serialize)

    @base_project.save!

    # table layout
    create(
      :memex_project_view,
      memex_project: @base_project,
      layout: "table_layout",
      name: "Table View",
      priority: @base_project.memex_project_views.first.priority + 1
    )

    # board layout
    @board_view = create(
      :memex_project_view,
      memex_project: @base_project,
      layout: "board_layout",
      name: "Board View",
      priority: @base_project.memex_project_views.first.priority + 2,
      layout_settings: {
        board: {
          column_limits: {
            "#{status_field.id}" => {
              "#{status_field.settings["options"].first["id"]}" => 20
            }
          }
        }
      }
    )

    # add some date fields
    @start_date_field = create(:memex_project_column, data_type: :date, user_defined: true, name: "Start Date", memex_project: @base_project)
    @end_date_field = create(:memex_project_column, data_type: :date, user_defined: true, name: "End Date", memex_project: @base_project)
    @other_date_field = create(:memex_project_column, data_type: :date, user_defined: true, name: "Other Date", memex_project: @base_project)

    # roadmap layout
    @roadmap_view = create(
      :memex_project_view,
      memex_project: @base_project,
      layout: "roadmap_layout",
      name: "Roadmap View",
      priority: @base_project.memex_project_views.first.priority + 3,
      layout_settings: {
        roadmap: {
          date_fields: [@start_date_field.id, @end_date_field.id],
          marker_fields: [@start_date_field.id, @end_date_field.id, @other_date_field.id]
        }
      }
    )

    @user = create(:verified_user)
    @user_owned_project = create(:memex_project, :with_admin, title: "user's project", owner: @user)
    @org = create(:business_organization)
    @org.add_member(@user)
  end

  setup do
    @copier = MemexProject::Copier.new(
      base_project: @base_project,
      target_project: @target_project,
      actor: @user,
    )
  end

  def test_fields_are_identical
    project_copy = @copier.execute.target_project
    assert_equal @base_project.memex_project_columns.length, project_copy.memex_project_columns.length
    assert_equal @base_project.memex_project_columns.map(&:name), project_copy.memex_project_columns.map(&:name)
  end

  def test_field_values_are_identical
    project_copy = @copier.execute.target_project
    base_status_field = @base_project.status_column
    copy_status_field = project_copy.status_column

    assert_same_elements base_status_field.settings["options"].map { |o| o["name"] }, copy_status_field.settings["options"].map { |o| o["name"] }
  end

  def test_views_are_identical
    project_copy = @copier.execute.target_project
    assert_equal @base_project.memex_project_views.length, project_copy.memex_project_views.length
    assert_equal @base_project.memex_project_views.map(&:name), project_copy.memex_project_views.map(&:name)
  end

  def test_copy_board_layout_settings
    copier = MemexProject::Copier.new(
      base_project: @base_project,
      target_project: @target_project,
      actor: @user,
    )
    project = copier.execute.target_project
    board_view = project.memex_project_views.find_by(name: @board_view.name)
    status_field = project.status_column
    first_option_id = status_field.settings["options"].first["id"].to_s

    assert_equal 20, board_view[:layout_settings]["board"]["column_limits"][status_field.id.to_s][first_option_id]
  end

  def test_copy_roadmap_layout_settings
    copier = MemexProject::Copier.new(
      base_project: @base_project,
      target_project: @target_project,
      actor: @user,
    )
    project = copier.execute.target_project
    roadmap_view = project.memex_project_views.find_by(name: @roadmap_view.name)
    start_date_field = project.memex_project_columns.find_by(name: @start_date_field.name)
    end_date_field = project.memex_project_columns.find_by(name: @end_date_field.name)
    other_date_field = project.memex_project_columns.find_by(name: @other_date_field.name)
    roadmap_settings = roadmap_view[:layout_settings]["roadmap"]

    assert_equal [start_date_field.id, end_date_field.id], roadmap_settings["date_fields"]
    assert_equal [start_date_field.id, end_date_field.id, other_date_field.id], roadmap_settings["marker_fields"]
  end
end

class MemexProjectCopierTestForDraftIssues < GitHub::TestCase
  fixtures do
    @creator = create(:verified_user)

    @base_project = create(:memex_project, title: "Base Project")

    # Creates a target project to test a new project made from a template
    @target_project = create(:memex_project, title: "Target Project")

    status_column = @base_project.memex_project_columns.find(&:status?)

    text_column = create(:memex_project_column, memex_project: @base_project, user_defined: true)
    date_column = create(:date_memex_column, memex_project: @base_project)
    single_select_column = create(:single_select_memex_column, memex_project: @base_project)
    iteration_column = create(:iteration_memex_column, memex_project: @base_project)
    number_column = create(:number_memex_column, memex_project: @base_project)

    @draft_issue = @base_project.build_draft_issue(
      creator: @creator,
      title: "draft",
      body: "body"
    )
    @custom_column_values = {
      text: {
        db_value: "Some text in a custom text column 🥳",
        expected_value: "Some text in a custom text column 🥳",
      },
      date: {
        db_value: Date.new(2021, 8, 10).to_s,
        expected_value: "Aug 10, 2021",
      },
      single_select: {
        db_value: single_select_column.settings["options"][0]["id"],
        expected_value: single_select_column.settings["options"][0]["name"],
      },
      iteration: {
        db_value: iteration_column.settings["configuration"]["iterations"][0]["id"],
        expected_value: iteration_column.settings["configuration"]["iterations"][0]["title"],
      },
      number: {
        db_value: "5",
        expected_value: "5",
      }
    }

    @draft_issue.set_column_value(status_column, status_column.settings["options"][0]["id"], @creator)
    @draft_issue.set_column_value(text_column, @custom_column_values[:text][:db_value], @creator)
    @draft_issue.set_column_value(date_column, @custom_column_values[:date][:db_value], @creator)
    @draft_issue.set_column_value(single_select_column, @custom_column_values[:single_select][:db_value], @creator)
    @draft_issue.set_column_value(iteration_column, @custom_column_values[:iteration][:db_value], @creator)
    @draft_issue.set_column_value(number_column, @custom_column_values[:number][:db_value], @creator)

    @draft_archived_issue = @base_project.build_draft_issue(
      creator: @creator,
      title: "archived draft",
      body: "archived body"
    )
    @draft_archived_issue.mark_as_archived(@creator)

    @base_project.save!
  end

  setup do
    @copier = MemexProject::Copier.new(
      base_project: @base_project,
      target_project: @target_project,
      actor: @creator,
    )
  end

  def test_draft_items_are_not_copied
    project_copy = @copier.execute.target_project
    assert_equal 2, @base_project.memex_project_items.is_draft.length
    assert_equal 0, project_copy.memex_project_items.is_draft.length
  end

  def test_draft_items_are_copied_if_they_are_not_archived
    copier = MemexProject::Copier.new(
      base_project: @base_project,
      target_project: @target_project,
      actor: @creator,
      include_draft_issues: true
    )
    project_copy = copier.execute.target_project
    assert_equal 2, @base_project.memex_project_items.is_draft.length
    draft_items = project_copy.memex_project_items.is_draft

    assert_equal 1, draft_items.length
    assert_predicate draft_items[0], :draft_issue?
    refute_predicate draft_items[0], :archived?
    assert_equal "draft", draft_items[0].content.title
    assert_equal "body", draft_items[0].content.body
    assert_empty draft_items[0].content.assignees
  end

  def test_draft_issues_copied_if_below_cutoff
    3.times do |i|
      draft_issue = @base_project.build_draft_issue(
        creator: @creator,
        title: "draft #{i}",
        body: "body #{i}"
      )
      draft_issue.save!
    end

    MemexProject::Copier.stub_const(:ASYNC_DRAFTS_CUTOFF, 5) do
      copier_result = MemexProject::Copier.new(
        base_project: @base_project,
        target_project: @target_project,
        actor: @creator,
        include_draft_issues: true
      ).execute
      assert_equal 4, copier_result.target_project.memex_project_items.is_draft.length
      refute copier_result.copying_drafts_async?
    end
  end

  def test_draft_issues_enqueued_if_above_cutoff
    6.times do |i|
      draft_issue = @base_project.build_draft_issue(
        creator: @creator,
        title: "draft #{i}",
        body: "body #{i}"
      )
      draft_issue.save!
    end

    MemexProject::Copier.stub_const(:ASYNC_DRAFTS_CUTOFF, 5) do
      copier_result = MemexProject::Copier.new(
        base_project: @base_project,
        target_project: @target_project,
        actor: @creator,
        include_draft_issues: true
      ).execute

      assert_equal 0, copier_result.target_project.memex_project_items.is_draft.length
      assert copier_result.copying_drafts_async?

      assert_enqueued_with(
        job: MemexProjectCopyDraftIssuesJob,
        args: [{
          actor_id: @creator.id,
          source_memex_project_id: @base_project.id,
          target_memex_project_id: @target_project.id,
        }]
      )
    end
  end

  def test_draft_issue_status_is_copied
    copier = MemexProject::Copier.new(
      base_project: @base_project,
      target_project: @target_project,
      actor: @creator,
      include_draft_issues: true
    )
    project_copy = copier.execute.target_project
    draft_item = project_copy.memex_project_items.is_draft.first
    status_column = project_copy.memex_project_columns.find(&:status?)
    assert_equal "Todo", draft_item.column_value(status_column, require_prefilled_associations: false)
  end

  def test_draft_items_with_custom_fields_are_copied
    copier = MemexProject::Copier.new(
      base_project: @base_project,
      target_project: @target_project,
      actor: @creator,
      include_draft_issues: true
    )
    project_copy = copier.execute.target_project
    draft_item = project_copy.memex_project_items.is_draft.first

    custom_columns = project_copy.memex_project_columns.user_defined
    assert_equal 5, custom_columns.count

    custom_columns.each do |column|
      assert_equal @custom_column_values[column.data_type.to_sym][:expected_value], draft_item.column_value(column, require_prefilled_associations: false)
    end
  end

  def test_add_new_draft_item_after_copy
    perform_enqueued_jobs(only: [RebalanceMemexProjectJob]) do
      copier = MemexProject::Copier.new(
        base_project: @base_project,
        target_project: @target_project,
        actor: @creator,
      )

      project_copy = copier.execute.target_project

      item = project_copy.build_draft_issue(
        creator: @creator,
        title: "draft after copy",
        body: "body"
      )

      assert_nothing_raised { project_copy.save_with_priority!(item) }
    end
  end

  test "copying a project does not make excessive numbers of queries for draft issues" do
    @copier = MemexProject::Copier.new(
      base_project: @base_project,
      target_project: @target_project,
      actor: @creator,
      include_draft_issues: true
    )

    columns_to_create = 10
    items_to_create = 10

    columns = []

    # create N columns
    columns_to_create.times do
      columns << create(:memex_project_column, memex_project: @base_project, user_defined: true, data_type: :text)
    end

    # create M draft issues, each with a column value for each column
    items_to_create.times do |i|
      draft_issue = @base_project.build_draft_issue(
        creator: @creator,
        title: "draft #{i}",
        body: "body #{i}"
      )

      columns_to_create.times do |j|
        create(:memex_project_column_value, memex_project_item: draft_issue, memex_project_column: columns[j], value: "value #{i} #{j}", creator: @creator)
      end
    end

    assert_query_count_per_table({
      draft_issues: 12,
      memex_project_charts: 1,
      memex_project_column_values: 108,
      memex_project_columns: 23,
      memex_project_items: 23,
      memex_project_views: 3,
      memex_project_workflow_actions: 0,
      memex_project_workflows: 2,
      memex_projects: 0,
      memex_templates: 0,
      users: 16,
      memex_project_visits: 0,
    }, backtrace_lines: 3) do
      @copier.execute
    end
  end
end
