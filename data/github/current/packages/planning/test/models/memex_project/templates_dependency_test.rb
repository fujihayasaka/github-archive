# typed: true
# frozen_string_literal: true

require "test_helper"

class TemplatesDependencyTest < GitHub::TestCase
  TemplateWithBoardView = {
    columns: [
      {
        name: MemexProjectColumn::STATUS_COLUMN_NAME,
        data_type: :single_select,
        default_column: true,
        user_defined: true,
        settings: {
          options: [
            {
              name: "Backlog",
              color: "GRAY",
              description: ""
            },
            {
              name: "In progress",
              color: "GRAY",
              description: ""
            },
            {
              name: "Done",
              color: "GRAY",
              description: ""
            }
          ]
        }
      },
      {
        name: "Onboarding Timeframe",
        data_type: :single_select,
        default_column: true,
        user_defined: true,
        settings: {
          options: [
            {
              name: "First Week",
              color: "GRAY",
              description: ""
            },
            {
              name: "First Month",
              color: "GRAY",
              description: ""
            },
            {
              name: "First Quarter",
              color: "GRAY",
              description: ""
            },
            {
              name: "First Year",
              color: "GRAY",
              description: ""
            }
          ]
        }
      }
    ],
    views: [
      {
        name: "Current iteration",
        visible_fields_by_name: %w[title assignees status],
        layout: :board_layout,
        column_field_by_name: ["onboarding-timeframe"],
        slice_by_field_by_name: {
          field_name: "assignees",
          panel_width: 500,
          filter: "abc"
        }
      },
    ],
    workflows: [
      {
        name: "Item closed",
        trigger_type: "closed",
        enabled: true,
        content_types: %w[Issue PullRequest],
        actions_attributes: [
          {
            action_type: "set_field",
            arguments: { fieldName: "status", fieldOptionName: "Done" }
          }
        ]
      },
      {
        name: "Item reopened",
        trigger_type: "reopened",
        enabled: false,
        content_types: %w[Issue PullRequest],
        actions_attributes: [
          {
            action_type: "set_field",
            arguments: { fieldName: "status", fieldOptionName: "In progress" }
          }
        ]
      },
    ]
  }

  # This template has a user-defined single select column with the name Type that will conflict with the
  # future system-defined default issue_type column named Type. This test fixture is for test cases to ensure that the
  # system-defined issue_type column is deleted when a user uses a template that contains a user-defined column named
  # Type.
  TemplateWithUserDefinedTypeColumn = {
    columns: [
      {
        name: MemexProjectColumn::TYPE_COLUMN_NAME,
        data_type: :single_select,
        default_column: false,
        user_defined: true,
        settings: {
          options: [
            {
              name: "Custom bug",
              color: "GRAY",
              description: ""
            },
            {
              name: "Another bug",
              color: "GRAY",
              description: ""
            },
            {
              name: "Done",
              color: "GRAY",
              description: ""
            }
          ]
        }
      },
    ],
    views: [
      {
        name: "Home",
        visible_fields_by_name: %w[title type],
        layout: :table_layout
      },
    ],
    workflows: [],
  }

  TemplateWithSystemDefinedTypeColumn = {
    columns: [
      {
        name: MemexProjectColumn::TYPE_COLUMN_NAME,
        data_type: :issue_type,
        default_column: false,
        user_defined: false,
      },
    ],
    views: [
      {
        name: "Home",
        visible_fields_by_name: %w[title type],
        layout: :table_layout
      },
    ],
    workflows: [],
  }

  fixtures do
    enable_feature_flag(:tasklist_block)

    @admin  = create(:verified_user)
    @org    = create(:organization)

    @org_member = create(:verified_user)
    @org.add_member(@org_member)

    @user   = create(:verified_user)

    @memex  = create(:memex_project, owner: @org, title: "My Memex Project")
  end

  context "template creation" do
    test "is_template?" do
      refute @memex.is_template?
    end

    test "create_template!" do
      @memex.create_template!
      assert @memex.is_template?

      assert MemexTemplate.where(memex_project_id: @memex.id).exists?
    end

    test "remove_template! 'soft deletes'" do
      @memex.create_template!
      @memex.remove_template!
      refute @memex.is_template?

      template = MemexTemplate.where(memex_project_id: @memex.id).first
      assert template
      refute T.must(template).active?
    end
  end

  context "apply feature template" do
    test "creates all columns in the template" do
      assert_equal 13, @memex.memex_project_columns.count
      @memex.apply_default_template(creator: @admin, template: MemexProject::DefaultTemplates::FeatureTemplate.deep_dup)
      assert_equal 15, @memex.memex_project_columns.count
    end

    test "creates status column with 6 options" do
      @memex.apply_default_template(creator: @admin, template: MemexProject::DefaultTemplates::FeatureTemplate.deep_dup)

      status_col = @memex.status_column
      assert status_col
      assert_equal 6, status_col.settings["options"].count
      assert_same_elements status_col.settings["options"].map { |it| it["name"] }, MemexProject::DefaultTemplates::FeatureTemplate[:columns].find { |i| i[:name] == "Status" }[:settings][:options].map { |i| i[:name] }
    end

    test "creates iteration column with right config" do
      @memex.apply_default_template(creator: @admin, template: MemexProject::DefaultTemplates::FeatureTemplate.deep_dup)

      iteration_col = @memex.memex_project_columns.find_by(name: "Iteration")

      assert iteration_col
      assert_equal 7, iteration_col.settings["configuration"]["duration"]
    end

    test "creates views defined in the template, correctly prioritized" do
      @memex.apply_default_template(creator: @admin, template: MemexProject::DefaultTemplates::FeatureTemplate.deep_dup)
      assert_equal 4, @memex.memex_project_views.count

      assert  @memex.memex_project_views.each_cons(2).all? { |left, right| left.priority <= right.priority }
    end

    test "creates insights defined in the template" do
      @memex.apply_default_template(creator: @admin, template: MemexProject::DefaultTemplates::FeatureTemplate.deep_dup)
      assert_equal 2, @memex.charts.count
    end
  end

  context "apply backlog template" do
    test "creates all columns in the template" do
      assert_equal 13, @memex.memex_project_columns.count
      @memex.apply_default_template(creator: @admin, template: MemexProject::DefaultTemplates::BacklogTemplate)
      assert_equal 15, @memex.memex_project_columns.count
    end

    test "creates status column with 6 options" do
      @memex.apply_default_template(creator: @admin, template: MemexProject::DefaultTemplates::BacklogTemplate)

      status_col = @memex.status_column
      assert status_col
      assert_equal 6, status_col.settings["options"].count
      assert_same_elements status_col.settings["options"].map { |it| it["name"] }, MemexProject::DefaultTemplates::BacklogTemplate[:columns].find { |i| i[:name] == "Status" }[:settings][:options].map { |i| i[:name] }
    end

    test "creates views defined in the template" do
      @memex.apply_default_template(creator: @admin, template: MemexProject::DefaultTemplates::BacklogTemplate)
      assert_equal 3, @memex.memex_project_views.count
      refute_nil @memex.memex_project_views.find_by(name: "By priority").priority
    end

    test "creates insights defined in the template" do
      @memex.apply_default_template(creator: @admin, template: MemexProject::DefaultTemplates::BacklogTemplate)
      assert_equal 1, @memex.charts.count
    end
  end

  test "can apply the team planning template" do
    freeze_time do
      template = MemexProject::DefaultTemplates::TeamPlanningTemplate.with_indifferent_access

      assert_project_state_before_applying_template @memex
      @memex.apply_default_template(creator: @admin, template: template)
      assert_project_state_after_applying_template @memex, template

      # Size column should have the right options
      size_column = @memex.memex_project_columns.find_by(name: "Size")
      assert_equal %w[XS S M L XL], size_column.settings["options"].map { |o| o["name"] }

      # Iteration column should have the right options
      assert_template_iterations_equal "Iteration", template[:columns], @memex.memex_project_columns

      # Check sum aggregation ID matches the "estimate" column
      backlog_view = @memex.memex_project_views.find_by(name: "Backlog")
      estimate_column = @memex.memex_project_columns.find_by(name: "Estimate")
      assert_equal [estimate_column.id], backlog_view.aggregation_settings["sum"]
    end
  end

  test "can apply the bug tracker template" do
    freeze_time do
      template = MemexProject::DefaultTemplates::BugTrackerTemplate.with_indifferent_access

      assert_project_state_before_applying_template @memex
      @memex.apply_default_template(creator: @admin, template: template)
      assert_project_state_after_applying_template @memex, template

      # Status column should have the right options
      status_column = @memex.memex_project_columns.find_by(name: "Status")
      assert_equal ["To triage", "Backlog", "Ready", "In progress", "In review", "Done"], status_column.settings["options"].map { |o| o["name"] }

      # Iteration column should have the right options
      assert_template_iterations_equal "Iteration", template[:columns], @memex.memex_project_columns

      # Check that workflow IDs are resolved
      reopened = T.let(@memex.workflows.find { |w| w.name == "Item reopened" }, MemexProjectWorkflow)
      backlog_status = status_column.settings["options"].find { |o| o["name"] == "Backlog" }
      assert_equal backlog_status["id"], T.must(reopened.actions.first).arguments["fieldOptionId"]
    end
  end

  test "can apply the feature release template" do
    freeze_time do
      template = MemexProject::DefaultTemplates::FeatureReleaseTemplate.with_indifferent_access

      assert_project_state_before_applying_template @memex
      @memex.apply_default_template(creator: @admin, template: template)
      assert_project_state_after_applying_template @memex, template

      # Status column should have the right options
      status_column = @memex.memex_project_columns.find_by(name: "Status")
      assert_equal ["Backlog", "Ready", "In progress", "In review", "Done"], status_column.settings["options"].map { |o| o["name"] }

      # Priority column should have the right options
      priority_column = @memex.memex_project_columns.find_by(name: "Priority")
      assert_equal %w[P0 P1 P2], priority_column.settings["options"].map { |o| o["name"] }

      # Iteration column should have the right options
      assert_template_iterations_equal "Iteration", template[:columns], @memex.memex_project_columns
    end
  end

  test "can apply the iterative development template" do
    freeze_time do
      template = MemexProject::DefaultTemplates::IterativeDevelopmentTemplate.with_indifferent_access

      assert_project_state_before_applying_template @memex
      @memex.apply_default_template(creator: @admin, template: template)
      assert_project_state_after_applying_template @memex, template

      # Status column should have the right options
      status_column = @memex.memex_project_columns.find_by(name: "Status")
      assert_equal ["Backlog", "Ready", "In progress", "In review", "Done"], status_column.settings["options"].map { |o| o["name"] }

      # Priority column should have the right options
      priority_column = @memex.memex_project_columns.find_by(name: "Priority")
      assert_equal %w[P0 P1 P2], priority_column.settings["options"].map { |o| o["name"] }

      # Iteration column should have the right options
      assert_template_iterations_equal "Iteration", template[:columns], @memex.memex_project_columns
    end
  end

  test "can apply the kanban template" do
    template = MemexProject::DefaultTemplates::KanbanTemplate.with_indifferent_access

    assert_project_state_before_applying_template @memex
    @memex.apply_default_template(creator: @admin, template: template)
    assert_project_state_after_applying_template @memex, template

    # Status column should have the right options
    status_column = @memex.memex_project_columns.find_by(name: "Status")
    assert_equal ["Backlog", "Ready", "In progress", "In review", "Done"], status_column.settings["options"].map { |o| o["name"] }

    # Priority column should have the right options
    priority_column = @memex.memex_project_columns.find_by(name: "Priority")
    assert_equal %w[P0 P1 P2], priority_column.settings["options"].map { |o| o["name"] }

    # Check that column limits are copied over correctly
    backlog_view = @memex.memex_project_views.find_by(name: "Backlog")
    in_progress_option = status_column.settings["options"].find { |o| o["name"] == "In progress" }
    assert_equal 3, backlog_view.layout_settings["board"]["column_limits"][status_column.id.to_s][in_progress_option["id"]]
  end

  test "can apply the product launch template" do
    freeze_time do
      template = MemexProject::DefaultTemplates::ProductLaunchTemplate.with_indifferent_access

      assert_project_state_before_applying_template @memex
      @memex.apply_default_template(creator: @admin, template: template)
      assert_project_state_after_applying_template @memex, template

      # Status column should have the right options
      status_column = @memex.memex_project_columns.find_by(name: "Status")
      assert_equal ["Todo", "In progress", "Done"], status_column.settings["options"].map { |o| o["name"] }

      # Priority column should have the right options
      priority_column = @memex.memex_project_columns.find_by(name: "Priority")
      assert_equal %w[P0 P1 P2], priority_column.settings["options"].map { |o| o["name"] }

      # Iteration column should have the right options
      assert_template_iterations_equal "Iteration", template[:columns], @memex.memex_project_columns
    end
  end

  test "can apply the roadmap template" do
    freeze_time do
      template = MemexProject::DefaultTemplates::RoadmapTemplate.with_indifferent_access

      assert_project_state_before_applying_template @memex
      @memex.apply_default_template(creator: @admin, template: template)
      assert_project_state_after_applying_template @memex, template

      # Status column should have the right options
      status_column = @memex.memex_project_columns.find_by(name: "Status")
      assert_equal ["Todo", "In progress", "Done"], status_column.settings["options"].map { |o| o["name"] }

      # Team column should have the right options
      team_column = @memex.memex_project_columns.find_by(name: "Team")
      assert_equal ["Squad 1", "Squad 2", "Squad 3"], team_column.settings["options"].map { |o| o["name"] }

      # Iteration column should have the right options
      assert_template_iterations_equal "Iteration", template[:columns], @memex.memex_project_columns

      # Quarter column should have the right options
      assert_template_iterations_equal "Quarter", template[:columns], @memex.memex_project_columns
    end
  end

  test "can apply the team retrospective template" do
    template = MemexProject::DefaultTemplates::TeamRetrospectiveTemplate.with_indifferent_access

    assert_project_state_before_applying_template @memex
    @memex.apply_default_template(creator: @admin, template: template)
    assert_project_state_after_applying_template @memex, template

    # Status column should have the right options
    status_column = @memex.memex_project_columns.find_by(name: "Status")
    assert_equal ["Agenda ✍", "What went well 🟢", "What can be improved 🟡", "Action items ✍"], status_column.settings["options"].map { |o| o["name"] }

    # All workflows except auto-add sub-issues should be disabled
    assert_equal 3, @memex.workflows.count
    assert_equal 1, @memex.workflows.to_a.count(&:enabled)
    refute_nil @memex.workflows.find_by(enabled: true, trigger_type: "sub_issues")
  end

  test "enables auto-close workflow" do
    freeze_time do
      # Using bug tracker template arbitrarily, but should apply to most system templates
      template = MemexProject::DefaultTemplates::BugTrackerTemplate.with_indifferent_access

      assert_project_state_before_applying_template @memex
      @memex.apply_default_template(creator: @admin, template: template)

      assert_equal 6, @memex.workflows.length
      workflow = @memex.workflows.find_by(trigger_type: "project_item_column_update")
      refute_nil workflow
      assert workflow.enabled
    end
  end

  test "enables auto-add sub-issues workflow" do
    freeze_time do
      # Using bug tracker template arbitrarily, but should apply to most system templates
      template = MemexProject::DefaultTemplates::BugTrackerTemplate.with_indifferent_access

      assert_project_state_before_applying_template @memex
      @memex.apply_default_template(creator: @admin, template: template)

      assert_equal 6, @memex.workflows.length
      workflow = @memex.workflows.find_by(trigger_type: "sub_issues")
      refute_nil workflow
      assert workflow.enabled
    end
  end

  context "apply blank template" do
    test "does not create additional columns" do
      assert_equal 13, @memex.memex_project_columns.count
      @memex.apply_default_template(creator: @admin, template: MemexProject::DefaultTemplates::BlankTemplate)
      assert_equal 13, @memex.memex_project_columns.count
    end

    test "creates a table, board, and roadmap view" do
      assert_equal 1, @memex.memex_project_views.count
      @memex.apply_default_template(creator: @admin, template: MemexProject::DefaultTemplates::BlankTemplate)

      assert_equal 3, @memex.memex_project_views.count
      assert_equal "Table", @memex.memex_project_views[0].name
      assert_equal "table_layout", @memex.memex_project_views[0].layout
      assert_equal "Board", @memex.memex_project_views[1].name
      assert_equal "board_layout", @memex.memex_project_views[1].layout
      assert_equal "Roadmap", @memex.memex_project_views[2].name
      assert_equal "roadmap_layout", @memex.memex_project_views[2].layout
    end
  end

  context "apply_template" do
    test "updates column field for board view" do
      @memex.apply_template(creator: @admin, template: TemplateWithBoardView.deep_dup)

      assert vertical_group_field = @memex.memex_project_columns.find_by(name: "Onboarding Timeframe")
      assert_equal 1, @memex.memex_project_views.count

      refute_empty @memex.memex_project_views.first.vertical_group_by
      assert_equal vertical_group_field.id, @memex.memex_project_views.first.vertical_group_by.first
    end

    test "creates workflows listed in template" do
      @memex.apply_template(creator: @admin, template: TemplateWithBoardView.deep_dup)

      assert_equal @memex.workflows.length, 2
    end

    test "creates workflows with correct enabled status" do
      @memex.apply_template(creator: @admin, template: TemplateWithBoardView.deep_dup)

      workflow = @memex.workflows.find { |w| w.name == "Item reopened" }
      assert_equal workflow.enabled, false
    end

    test "creates slice by with the correct field and settings" do
      @memex.apply_template(creator: @admin, template: TemplateWithBoardView.deep_dup)

      assignees_column = @memex.memex_project_columns.find_by(name: "Assignees")
      view = @memex.memex_project_views.first

      expected_slice_by = {
        "panel_width" => 500,
        "filter" => "abc",
        "field" => assignees_column.id
      }
      assert_equal view.slice_by, expected_slice_by
    end

    test "creates empty slice by if it encounters an invalid field" do
      template = TemplateWithBoardView.deep_dup
      template[:views].first[:slice_by_field_by_name][:field_name] = "foo"
      @memex.apply_template(creator: @admin, template: template)

      assignees_column = @memex.memex_project_columns.find_by(name: "Assignees")
      view = @memex.memex_project_views.first

      expected_slice_by = {}
      assert_equal view.slice_by, expected_slice_by
    end

    test "does not create insights chart if not valid due to column not existing" do
      template = TemplateWithBoardView.deep_dup
      template[:insights] = [
        {
          name: "Not valid chart",
          configuration: {
            type: "line",
            xAxis: {
              dataSource: {
                columnName: ""
              }
            },
            yAxis: {
              aggregate: {
                operation: "count"
              }
            },
            filter: "iteration:@current"
          }
        },
        {
          name: "Current iteration",
          configuration: {
            type: "line",
            xAxis: {
              dataSource: {
                columnName: "status"
              }
            },
            yAxis: {
              aggregate: {
                operation: "count"
              }
            },
            filter: "iteration:@current"
          }
        }
      ]

      @memex.apply_template(creator: @admin, template: template)
      @memex.reload

      assert_equal 1, @memex.charts.count
      refute_equal "Not valid chart", @memex.charts.first.name
    end

    test "creates aggregation settings" do
      template = {
        columns: [
          {
            name: "Estimate",
            data_type: :number,
            default_column: false,
            user_defined: true,
          }
        ],
        views: [
          {
            name: "Current iteration",
            visible_fields_by_name: %w[title assignees status],
            layout: :board_layout,
            column_field_by_name: ["estimate"],
            aggregation_settings_by_name: {
              hide_items_count: true,
              sum: ["estimate"],
            }
          },
        ],
      }
      @memex.apply_template(creator: @admin, template: template)
      view = @memex.memex_project_views.first
      estimate_column = @memex.memex_project_columns.find_by(name: "Estimate")

      assert_equal [estimate_column.id], view.aggregation_settings["sum"]
      assert_equal true, view.aggregation_settings["hide_items_count"]
    end

    test "handles invalid columns in aggregation settings" do
      template = {
        columns: [
          {
            name: "Estimate",
            data_type: :number,
            default_column: false,
            user_defined: true,
          }
        ],
        views: [
          {
            name: "Current iteration",
            visible_fields_by_name: %w[title assignees status],
            layout: :board_layout,
            column_field_by_name: ["estimate"],
            aggregation_settings_by_name: {
              sum: ["nonexistent"],
            }
          },
        ],
      }
      @memex.apply_template(creator: @admin, template: template)
      view = @memex.memex_project_views.first

      assert_equal [], view.aggregation_settings["sum"]
      assert_equal false, view.aggregation_settings["hide_items_count"]
    end

    test "deletes original system-defined Type column if source project has user-defined Type column" do
      admin  = create(:verified_user)
      org    = create(:organization, admin: admin)
      memex  = create(:memex_project, owner: org, creator: admin, title: "My Memex Project")

      system_issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      assert system_issue_type_column, "expected project to have Type column"
      assert_predicate system_issue_type_column, :system_defined?, "expected project to have system-defined Type column"

      assert_no_changes -> { MemexProjectColumn.count }, "expected the same number of columns to exist after applying template" do
        MemexProject::Copier.with_copying do
          memex.apply_template(creator: admin, template: TemplateWithUserDefinedTypeColumn.deep_dup)
        end
      end

      assert_nil MemexProjectColumn.find_by(id: system_issue_type_column.id), "expected system-defined Type column to be deleted"
      user_issue_type_column = memex.memex_project_columns.find_by!(name: MemexProjectColumn::TYPE_COLUMN_NAME)
      assert user_issue_type_column, "expected project to have Type column"
      assert_predicate user_issue_type_column, :user_defined?, "expected project to have user-defined Type column"
    end

    test "does not delete original system-defined Type column if source project has no user-defined Type column" do
      admin  = create(:verified_user)
      org    = create(:organization, admin: admin)
      enable_feature_flag(:issue_types, org)
      memex  = create(:memex_project, owner: org, creator: admin, title: "My Memex Project")

      assert system_issue_type_column = memex.memex_project_columns.find_by!(name: MemexProjectColumn::TYPE_COLUMN_NAME), "expected project to have Type column"
      assert_predicate system_issue_type_column, :system_defined?, "expected project to have system-defined Type column"

      template = TemplateWithUserDefinedTypeColumn.deep_dup
      template[:columns] = []

      assert_no_changes -> { MemexProjectColumn.count } do
        memex.apply_template(creator: admin, template: template)
      end

      assert_equal system_issue_type_column, MemexProjectColumn.find_by(id: system_issue_type_column.id), "expected system-defined Type column to exist"
    end

    test "does not delete original user-defined Type column if source project has user-defined Type column" do
      admin  = create(:verified_user)
      org    = create(:organization, admin: admin)
      memex  = create(:memex_project, owner: org, creator: admin, title: "My Memex Project")
      memex.memex_project_columns.issue_type.destroy_all
      MemexProject::Copier.with_copying do
        user_issue_type_column = create(:single_select_memex_column, memex_project: memex, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)

        memex.reload

        assert_predicate user_issue_type_column, :user_defined?, "expected project to have user-defined Type column"
        assert_no_changes -> { MemexProjectColumn.count } do
          memex.apply_template(creator: admin, template: TemplateWithSystemDefinedTypeColumn.deep_dup)
        end

        assert_equal user_issue_type_column, MemexProjectColumn.find_by(id: user_issue_type_column.id), "expected user-defined Type column to exist"
      end
    end

    test "does not delete original system-defined Type column if source project also has a system-defined Type column" do
      admin  = create(:verified_user)
      org    = create(:organization, admin: admin)
      enable_feature_flag(:issue_types, org)
      memex  = create(:memex_project, owner: org, creator: admin, title: "My Memex Project")

      assert system_issue_type_column = memex.memex_project_columns.find_by!(name: MemexProjectColumn::TYPE_COLUMN_NAME), "expected project to have Type column"
      assert_predicate system_issue_type_column, :system_defined?, "expected project to have system-defined Type column"

      assert_no_changes -> { MemexProjectColumn.count } do
        memex.apply_template(creator: admin, template: TemplateWithSystemDefinedTypeColumn.deep_dup)
      end

      assert_equal system_issue_type_column, MemexProjectColumn.find_by(id: system_issue_type_column.id), "expected system-defined Type column to exist"
    end

    test "preserves Type field from view settings if destination project is eligble for system-defined Type column" do
      admin  = create(:verified_user)
      org    = create(:organization, admin: admin)
      enable_feature_flag(:issue_types, org)
      memex  = create(:memex_project, owner: org, creator: admin, title: "My Memex Project")

      assert system_issue_type_column = memex.memex_project_columns.find_by!(name: MemexProjectColumn::TYPE_COLUMN_NAME), "expected project to have Type column"
      assert_predicate system_issue_type_column, :system_defined?, "expected project to have system-defined Type column"

      memex.apply_template(creator: admin, template: TemplateWithSystemDefinedTypeColumn.deep_dup)

      contains_issue_type_field_in_views = memex.memex_project_views.any? do |view|
        view.visible_fields.any? do |column_id|
          memex.memex_project_columns.find(column_id).issue_type?
        end
      end
      assert contains_issue_type_field_in_views, "expected project to have Type field in any view settings"
    end
  end

  sig { params(template_workflows: T::Array[T::Hash[Symbol, T.untyped]], memex_workflows: T::Enumerable[MemexProjectWorkflow]).void }
  private def assert_template_workflows_equal(template_workflows, memex_workflows)
    # Check that workflows are created correctly
    expected_workflows = template_workflows.map do |w|
      {
        name: w[:name],
        trigger_type: w[:trigger_type],
        enabled: w[:enabled],
        content_types: w[:content_types],
        actions: w[:actions_attributes].map { |a| { action_type: a[:action_type] } }
      }
    end
    workflows = memex_workflows.map do |w|
      {
      name: w.name,
      trigger_type: w.trigger_type,
      enabled: w.enabled,
      content_types: w.content_types,
      actions: w.actions.map { |a| { action_type: a.action_type } }
      }
    end
    assert_equal expected_workflows, workflows
  end

  sig { params(column_name: String, template_columns: T::Enumerable[Hash], memex_columns: T::Enumerable[MemexProjectColumn]).void }
  private def assert_template_iterations_equal(column_name, template_columns, memex_columns)
    # Assert that the template configuration is copied over to the new column
    iteration_column = T.must(memex_columns.find { |c| c["name"] == column_name })
    new_iteration_dates = iteration_column.settings["configuration"]["iterations"].map { |o| o["start_date"] }
    template_iteration_column = T.must(template_columns.find { |c| c[:name] == column_name })
    template_iteration_dates = template_iteration_column[:settings]["configuration"]["iterations"].map { |i| i["start_date"] }.sort
    assert_equal template_iteration_dates, new_iteration_dates
  end

  sig { params(memex: MemexProject).void }
  private def assert_project_state_before_applying_template(memex)
    assert_equal 13, memex.memex_project_columns.count
    assert_equal 1, memex.memex_project_views.count
    assert_equal 0, memex.workflows.length
    assert_equal 0, memex.charts.count
  end

  sig { params(memex: MemexProject, template: T::Hash[T.untyped, T.untyped]).void }
  private def assert_project_state_after_applying_template(memex, template)
    excluded_default_column_names = MemexProject.excluded_default_columns(memex.creator, memex.owner)
    expected_system_defined_columns = MemexProjectColumn::SYSTEM_DEFINED_COLUMNS.reject do |sdc|
      excluded_default_column_names.include?(sdc[:name])
    end
    template_columns = template[:columns].reject do |c|
      expected_system_defined_columns.any? do |sdc|
        sdc[:name] == c[:name]
      end
    end
    template_created_memex_project_columns = (memex.memex_project_columns.pluck(:name) - expected_system_defined_columns.collect { |t| t[:name] })
    template_views = template[:views]
    template_workflows = template[:workflows]
    template_charts = template[:insights]

    assert_equal template_columns.length, template_created_memex_project_columns.length, "Expected number of columns to match"
    assert_equal template_views.length, memex.memex_project_views.count, "Expected number of views to match"
    assert_equal template_workflows.length, memex.workflows.length, "Expected number of workflows to match"
    assert_equal template_charts.length, memex.charts.count, "Expected number of charts to match"

    # Check that workflows are created correctly
    assert_template_workflows_equal template_workflows, @memex.workflows
  end
end
