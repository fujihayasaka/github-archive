# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectViewTest < GitHub::TestCase
  include HydroTestHelpers
  include StringFromBinaryTestHelper

  fixtures do
    @org = create(:organization)
    @user = create(:verified_user).tap { |u| @org.add_member(u) }
    @other_user = create(:verified_user).tap { |u| @org.add_member(u) }

    @repo = create(:private_repository, owner: @org)
    @issue = create(:issue, repository: @repo, user: @user)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)

    @memex = create(:memex_project, owner: @org)
    @view = @memex.memex_project_views.first
    @item = create(:memex_project_item, memex_project: @memex, content: @issue)
  end

  context ".new_with_defaults" do
    test "initializes record with defaults" do
      view = MemexProjectView.new_with_defaults

      assert_equal 1, view.id
      assert_equal 1, view.number
      assert_equal "View 1", view.name
      assert_equal [], view.group_by
      assert_equal [], view.vertical_group_by
      assert_equal [], view.sort_by
      assert_equal [], view.visible_fields
      assert_equal false, view.aggregation_settings["hide_items_count"]
      assert_equal [], view.aggregation_settings["sum"]
      assert_equal ({}), view.slice_by
      assert_nil view.filter
      assert_equal "table_layout", view.layout
      assert_kind_of Time, view.created_at
      assert_kind_of Time, view.updated_at
    end

    test "returns readonly instance" do
      view = MemexProjectView.new_with_defaults

      assert_predicate view, :readonly?
    end
  end

  context "validations" do
    test "limits views to a set max per project" do
      memex = create(:memex_project)

      MemexProjectView.stub_const(:MAX_VIEW_COUNT, 1) do
        view = create(:memex_project_view, memex_project: memex)
        assert view.persisted?

        view = build(:memex_project_view, memex_project: memex)
        refute view.valid?

        assert_includes view.errors[:base], "Views are limited to 1 per project"
      end
    end

    test "requires a creator" do
      view = build(:memex_project_view, creator: nil)
      refute view.valid?
      assert_includes view.errors[:creator], "can't be blank"
    end

    context "filter" do
      test "allows a UTF string in the filter" do
        view = build(:memex_project_view, filter: "other encoding".dup.tap { |t| t.force_encoding("ISO-8859-1") })
        view.save!

        assert_equal Encoding::UTF_8, view.filter.encoding
      end

      test "disallows too long of a filter" do
        view = build(:memex_project_view, filter: "x" * (MemexProjectView::FILTER_CHARACTERS_LIMIT + 1))
        refute view.valid?
        assert_includes view.errors[:filter], "is too long (maximum is 256 characters)"
      end

      test "allows 256 non-ASCII characters in a filter" do
        # 2 bytes chars
        view = build(:memex_project_view, filter: "ц" * (MemexProjectView::FILTER_CHARACTERS_LIMIT))
        assert view.valid?
        view.save!
      end

      test "allows no more than 256 ASCII and non-ASCII characters in a filter" do
        # 2 bytes and 1 byte chars
        view = build(:memex_project_view, filter: "цj" * (MemexProjectView::FILTER_CHARACTERS_LIMIT / 2))
        assert view.valid?
        view.save!

        view = build(:memex_project_view, filter: "цj" * (MemexProjectView::FILTER_CHARACTERS_LIMIT / 2) + "s")
        refute view.valid?
        assert_includes view.errors[:filter], "is too long (maximum is 256 characters)"
      end
    end

    context "group_by" do
      test "sets a default group_by" do
        view = build(:memex_project_view, group_by: nil)
        assert view.valid?
        assert_equal [], view.group_by
      end

      test "disallows too long of a group_by" do
        view = build(:memex_project_view, group_by: [MemexProjectView::MAX_BIGINT_VALUE] * 100)
        refute view.valid?
        assert_includes view.errors[:group_by], "must be fewer than #{MemexProjectView::JSON_BYTESIZE_LIMIT} bytes as JSON"
      end

      test "requires group_by values to be integers" do
        view = build(:memex_project_view, group_by: ["foo"])
        refute view.valid?
        assert_includes view.errors[:group_by], "must be an array of integers"
      end

      test "cleans columns not belonging to the project" do
        memex = create(:memex_project)
        view = build(:memex_project_view, memex_project: memex, group_by: [memex.columns.first.id, memex.columns.last.id + 1])
        assert view.valid?
        assert_equal [memex.columns.first.id], view.group_by
      end
    end

    context "vertical_group_by" do
      test "sets a default vertical_group_by" do
        view = build(:memex_project_view, vertical_group_by: nil)
        assert view.valid?
        assert_equal [], view.vertical_group_by
      end

      test "disallows too long of a vertical_group_by" do
        view = build(:memex_project_view, vertical_group_by: [MemexProjectView::MAX_BIGINT_VALUE] * 100)
        refute view.valid?
        assert_includes view.errors[:vertical_group_by], "must be fewer than #{MemexProjectView::JSON_BYTESIZE_LIMIT} bytes as JSON"
      end

      test "requires vertical_group_by values to be integers" do
        view = build(:memex_project_view, vertical_group_by: ["foo"])
        refute view.valid?
        assert_includes view.errors[:vertical_group_by], "must be an array of integers"
      end

      test "cleans columns not belonging to the project" do
        memex = create(:memex_project)
        view = build(:memex_project_view, memex_project: memex, vertical_group_by: [memex.columns.first.id, memex.columns.last.id + 1])
        assert view.valid?
        assert_equal [memex.columns.first.id], view.vertical_group_by
      end
    end

    context "layout" do
      test "sets a default layout" do
        view = build(:memex_project_view, layout: nil)
        assert view.valid?
        assert_equal "table_layout", view.layout
      end

      test "requires a valid layout type" do
        invalid_view = build(:memex_project_view, layout: "gantt")
        refute invalid_view.valid?
        assert_includes invalid_view.errors[:layout], "'gantt' is not a valid layout"

        valid_layout_types = %w[table_layout board_layout list_layout roadmap_layout]

        valid_layout_types.each do |layout_type|
          view = build(:memex_project_view, layout: layout_type)
          assert view.valid?
          assert_equal layout_type, view.layout
        end
      end
    end

    test "requires a Memex project" do
      view = build(:memex_project_view, memex_project: nil)
      refute view.valid?
      assert_includes view.errors[:memex_project], "can't be blank"
    end

    context "name" do
      test "disallows the empty string as a name" do
        view = build(:memex_project_view, name: "")
        refute view.valid?
        assert_includes view.errors[:name], "can't be blank"
      end

      test "disallows too long of a name" do
        view = build(:memex_project_view, name: "x" * (MemexProjectView::NAME_BYTESIZE_LIMIT + 1))
        refute view.valid?
        assert_includes view.errors[:name], "is too long (maximum is 32 characters)"
      end

      test "allows a UTF string in the name" do
        view = create(:memex_project_view, name: "🥇".dup.tap { |t| t.force_encoding("ISO-8859-1") })
        assert_equal view.reload.name, "🥇"
        assert_equal Encoding::UTF_8, view.name.encoding
      end
    end

    context "number" do
      test "requires a number greater than 0" do
        view = build(:memex_project_view, number: 0)
        refute view.valid?
        assert_includes view.errors[:number], "must be greater than 0"
      end

      test "requires number to be unique for the project" do
        existing_view = create(:memex_project_view)
        new_view = build(:memex_project_view, memex_project: existing_view.memex_project, number: existing_view.number)
        refute new_view.save
        assert_includes new_view.errors[:number], "has already been taken"
      end
    end

    context "sort_by" do
      test "sets a default sort_by" do
        view = build(:memex_project_view, sort_by: nil)
        assert view.valid?
        assert_equal [], view.sort_by
      end

      test "disallows too long of a sort_by" do
        view = build(:memex_project_view, sort_by: [MemexProjectView::MAX_BIGINT_VALUE, "desc"] * 100)
        refute view.valid?
        assert_includes view.errors[:sort_by], "must be fewer than #{MemexProjectView::JSON_BYTESIZE_LIMIT} bytes as JSON"
      end

      test "requires sort_by to be in the correct format" do
        view = build(:memex_project_view, sort_by: {})
        refute view.valid?
        assert_includes view.errors[:sort_by], "must be an array"

        column_id = view.memex_project.memex_project_columns.first.id

        view.sort_by = [[column_id.to_s, "asc"]]
        refute view.valid?
        assert_includes view.errors[:sort_by], MemexProjectView::SORT_BY_ERROR

        view.sort_by = [[column_id, "descending"]]
        refute view.valid?
        assert_includes view.errors[:sort_by], MemexProjectView::SORT_BY_ERROR

        view.sort_by = [[column_id, "asc", "extra"]]
        refute view.valid?
        assert_includes view.errors[:sort_by], MemexProjectView::SORT_BY_ERROR

        view.sort_by = [[column_id, "asc"], [column_id.to_s, "desc"]]
        refute view.valid?
        assert_includes view.errors[:sort_by], MemexProjectView::SORT_BY_ERROR

        view.sort_by = [[column_id, "asc"]]
        assert view.valid?
      end

      test "cleans columns not belonging to the project" do
        memex = create(:memex_project)
        view = build(:memex_project_view, memex_project: memex, sort_by: [[memex.columns.first.id, "asc"], [memex.columns.last.id + 1, "asc"]])
        assert view.valid?
        assert_equal [[memex.columns.first.id, "asc"]], view.sort_by
      end
    end

    context "visible_fields" do
      test "sets default visible_fields" do
        memex = create(:memex_project)
        column = memex.memex_project_columns.find_by!(name: "Labels", visible: false, user_defined: false)
        assert memex.update_column(column, visible: true)

        view = create(:memex_project_view, memex_project: memex, visible_fields: nil)
        assert view.valid?
        visible_system_column_titles = MemexProjectColumn::SYSTEM_DEFINED_COLUMNS.select { |c| c[:default_column] }.map { |c| c[:name] }
        view_visible_column_titles = view.memex_project.columns.select { |c| view.visible_fields.include?(c.id) }.map(&:name)
        assert_same_elements visible_system_column_titles, view_visible_column_titles
      end

      test "sets default visible_fields when given an empty array" do
        view = create(:memex_project_view, visible_fields: [])
        assert view.valid?
        visible_system_column_titles = MemexProjectColumn::SYSTEM_DEFINED_COLUMNS.select { |c| c[:default_column] }.map { |c| c[:name] }
        view_visible_column_titles = view.memex_project.columns.select { |c| view.visible_fields.include?(c.id) }.map(&:name)
        assert_same_elements visible_system_column_titles, view_visible_column_titles
      end

      test "disallows too long of a visible_fields" do
        view = build(:memex_project_view, visible_fields: [MemexProjectView::MAX_BIGINT_VALUE] * 100)
        refute view.valid?
        assert_includes view.errors[:visible_fields], "must be fewer than #{MemexProjectView::JSON_BYTESIZE_LIMIT} bytes as JSON"
      end

      test "requires visible_fields values to be integers" do
        view = build(:memex_project_view, visible_fields: ["foo"])
        refute view.valid?
        assert_includes view.errors[:visible_fields], "must be an array of integers"
      end

      test "cleans columns not belonging to the project" do
        memex = create(:memex_project)
        view = build(:memex_project_view, memex_project: memex, visible_fields: [memex.columns.first.id, memex.columns.last.id + 1])
        assert view.valid?
        assert_equal [memex.columns.first.id], view.visible_fields
      end
    end

    context "aggregation_settings" do
      test "sets a default aggregation_settings" do
        view = build(:memex_project_view, aggregation_settings: nil)
        assert view.valid?

        assert_equal false, view.aggregation_settings["hide_items_count"]
        assert_equal [], view.aggregation_settings["sum"]
      end

      test "disallows too long of a aggregation_settings" do
        view = build(:memex_project_view, aggregation_settings: { hide_items_count: true, sum: [MemexProjectView::MAX_BIGINT_VALUE] * 100 })
        refute view.valid?
        assert_includes view.errors[:aggregation_settings], "must be fewer than #{MemexProjectView::JSON_BYTESIZE_LIMIT} bytes as JSON"
      end

      test "filters out non -numerical columns and columns not belonging to the project" do
        number_column = create(:memex_project_column, data_type: :number, user_defined: true, name: "Points")
        memex = number_column.memex_project

        view = build(:memex_project_view, memex_project: memex, aggregation_settings: { hide_items_count: true, sum: [memex.columns.first.id, memex.columns.last.id + 10, number_column.id] })
        assert view.valid?
        assert_equal [number_column.id], view.aggregation_settings["sum"]
      end
    end

    context "slice_by" do
      test "sets default slice_by" do
        view = build(:memex_project_view, slice_by: nil)
        assert view.valid?

        assert_equal ({}), view.slice_by
      end

      test "disallows invalid keys" do
        view = build(:memex_project_view, slice_by: { foo: "bar" })
        refute view.valid?

        assert_includes view.errors[:slice_by], "contains unsupported keys: foo"
      end

      test "disallows invalid field type" do
        view = build(:memex_project_view, slice_by: { field: "bar" })
        refute view.valid?

        assert_includes view.errors["slice_by.field"], "must be an integer"
      end

      test "cleans column ids not belonging to the project" do
        memex = create(:memex_project)
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: memex.columns.last.id + 1 })
        assert view.valid?

        assert_equal ({}), view.slice_by
      end

      test "removes non-integer values for panel_width" do
        memex = create(:memex_project)

        status_column = memex.columns.find(&:status?)
        refute_nil status_column

        view = build(:memex_project_view, memex_project: memex, slice_by: { field: status_column.id , panel_width: "b" })
        assert view.valid?

        assert_equal ({ "field" => status_column.id }), view.slice_by
      end

      test "cleans invalid column types" do
        memex = create(:memex_project)

        title_column = memex.columns.find(&:title?)
        refute_nil title_column
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: title_column.id })
        assert view.valid?
        assert_equal ({}), view.slice_by

        linked_pull_requests_column = memex.columns.find(&:linked_pull_requests?)
        refute_nil linked_pull_requests_column
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: linked_pull_requests_column.id })
        assert view.valid?
        assert_equal ({}), view.slice_by
      end

      test "allows saving of valid column types" do
        memex = create(:memex_project, owner: @org)

        iteration_column = create(:memex_project_column, memex_project: memex, data_type: :iteration, user_defined: true)
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: iteration_column.id })
        assert view.valid?
        assert_equal ({ "field" => iteration_column.id }), view.slice_by

        single_select_column = create(:memex_project_column, memex_project: memex, data_type: :single_select, user_defined: true)
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: single_select_column.id })
        assert view.valid?
        assert_equal ({ "field" => single_select_column.id }), view.slice_by

        tracked_by_column = create(:memex_project_column, memex_project: memex, data_type: :tracked_by, user_defined: true)
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: tracked_by_column.id })
        assert view.valid?
        assert_equal ({ "field" => tracked_by_column.id }), view.slice_by

        assignees_column = memex.columns.find(&:assignees?)
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: assignees_column.id })
        assert view.valid?
        assert_equal ({ "field" => assignees_column.id }), view.slice_by

        labels_column = memex.columns.find(&:labels?)
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: labels_column.id })
        assert view.valid?
        assert_equal ({ "field" => labels_column.id }), view.slice_by

        milestone_column = memex.columns.find(&:milestone?)
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: milestone_column.id })
        assert view.valid?
        assert_equal ({ "field" => milestone_column.id }), view.slice_by

        repository_column = memex.columns.find(&:repository?)
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: repository_column.id })
        assert view.valid?
        assert_equal ({ "field" => repository_column.id }), view.slice_by

        issue_type_column = memex.columns.find(&:issue_type?)
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: issue_type_column.id })
        assert view.valid?
        assert_equal ({ "field" => issue_type_column.id }), view.slice_by

        parent_issue_column = memex.columns.find(&:parent_issue?)
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: parent_issue_column.id })
        assert view.valid?
        assert_equal ({ "field" => parent_issue_column.id }), view.slice_by

        text_column = create(:memex_project_column, memex_project: memex, data_type: :text, user_defined: true, name: "Comments")
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: text_column.id })
        assert view.valid?
        assert_equal ({ "field" => text_column.id }), view.slice_by

        number_column = create(:memex_project_column, memex_project: memex, data_type: :number, user_defined: true, name: "Effort")
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: number_column.id })
        assert view.valid?
        assert_equal ({ "field" => number_column.id }), view.slice_by

        date_column = create(:memex_project_column, memex_project: memex, data_type: :date, user_defined: true, name: "Start Date")
        view = build(:memex_project_view, memex_project: memex, slice_by: { field: date_column.id })
        assert view.valid?
        assert_equal ({ "field" => date_column.id }), view.slice_by
      end

      context "filter" do
        test "does not persist absent a field" do
          memex = create(:memex_project)
          view = build(:memex_project_view, memex_project: memex, slice_by: { filter: "foo" })

          assert view.valid?
          assert_equal ({}), view.slice_by
        end

        test "only allows strings" do
          memex = create(:memex_project)
          column = create(:memex_project_column, memex_project: memex, data_type: :single_select, user_defined: true)
          view = build(:memex_project_view, memex_project: memex, slice_by: { field: column.id, filter: 1 })
          refute view.valid?

          assert_includes view.errors["slice_by.filter"], "must be a string"
        end

        test "disallows too long of a filter" do
          memex = create(:memex_project)
          column = create(:memex_project_column, memex_project: memex, data_type: :single_select, user_defined: true)
          view = build(:memex_project_view, memex_project: memex, slice_by: { field: column.id, filter: "x" * (MemexProjectView::FILTER_CHARACTERS_LIMIT + 1) })
          refute view.valid?

          assert_includes view.errors["slice_by.filter"], "is too long (maximum is 256 characters)"
        end

        test "allows 256 non-ASCII characters in a filter" do
          memex = create(:memex_project)
          column = create(:memex_project_column, memex_project: memex, data_type: :single_select, user_defined: true)
          filter_value = "ц" * (MemexProjectView::FILTER_CHARACTERS_LIMIT)
          view = build(:memex_project_view, memex_project: memex, slice_by: { field: column.id, filter: filter_value })

          assert view.valid?
          assert_equal ({ "field" => column.id, "filter" => filter_value }), view.slice_by
        end

        test "allows no more than 256 ASCII and non-ASCII characters in a filter" do
          memex = create(:memex_project)
          column = create(:memex_project_column, memex_project: memex, data_type: :single_select, user_defined: true)
          filter_value = "цj" * (MemexProjectView::FILTER_CHARACTERS_LIMIT / 2)
          view = build(:memex_project_view, memex_project: memex, slice_by: { field: column.id, filter: "цj" * (MemexProjectView::FILTER_CHARACTERS_LIMIT / 2) })
          assert view.valid?
          assert_equal ({ "field" => column.id, "filter" => filter_value }), view.slice_by

          view = build(:memex_project_view, memex_project: memex, slice_by: { field: column.id, filter: "цj" * (MemexProjectView::FILTER_CHARACTERS_LIMIT / 2) + "s" })
          refute view.valid?
          assert_includes view.errors["slice_by.filter"], "is too long (maximum is 256 characters)"
        end
      end
    end

    context "layout settings" do
      test "sets default layout settings" do
        view = build(:memex_project_view, layout_settings: nil)
        assert view.valid?

        assert_equal MemexProjectView::DEFAULT_LAYOUT_SETTINGS, view.layout_settings
      end

      test "disallows layout settings that are too large" do
        view = build(:memex_project_view, layout_settings: { roadmap: { test_field: [999] * 4000 } })
        refute view.valid?

        assert_includes view.errors[:layout_settings], "must be fewer than #{MemexProjectView::LAYOUT_SETTINGS_JSON_BYTESIZE_LIMIT} bytes as JSON"
      end

      test "disallows layout settings with incorrect type" do
        view = build(:memex_project_view, layout_settings: ["this is not a hash"])
        refute view.valid?

        assert_includes view.errors[:layout_settings], "For '#', [\"this is not a hash\"] is not an object."
      end

      test "disallows unrecognized properties in layout settings" do
        view = build(:memex_project_view, layout_settings: { unsupported: "yes" })
        refute view.valid?

        assert_includes view.errors[:layout_settings], "\"unsupported\" is not a permitted key."
      end

      context "table layout" do
        test "disallows unrecognized properties" do
          view = build(:memex_project_view, layout_settings: { table: { unsupported: "yes" } })
          refute view.valid?

          assert_includes view.errors["layout_settings.table"], "\"unsupported\" is not a permitted key."
        end
      end

      context "board layout" do
        test "disallows unrecognized properties" do
          view = build(:memex_project_view, layout_settings: { board: { unsupported: "yes" } })
          refute view.valid?

          assert_includes view.errors["layout_settings.board"], "\"unsupported\" is not a permitted key."
        end
      end

      context "roadmap layout" do
        test "disallows unrecognized properties" do
          view = build(:memex_project_view, layout_settings: { roadmap: { unsupported: "yes" } })
          refute view.valid?

          assert_includes view.errors["layout_settings.roadmap"], "\"unsupported\" is not a permitted key."
        end

        context "zoom level" do
          test "is valid when value is month, quarter, or year" do
            project = create(:memex_project)

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { zoom_level: "month" } })
            assert view.valid?
            assert_equal "month", view.layout_settings["roadmap"]["zoom_level"]

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { zoom_level: "quarter" } })
            assert view.valid?
            assert_equal "quarter", view.layout_settings["roadmap"]["zoom_level"]

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { zoom_level: "year" } })
            assert view.valid?
            assert_equal "year", view.layout_settings["roadmap"]["zoom_level"]
          end

          test "disallow invalid capitalization" do
            project = create(:memex_project)
            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { zoom_level: "Month" } })

            refute view.valid?
            assert_includes view.errors["layout_settings.roadmap.zoom_level"], "Month is not a member of [\"month\", \"quarter\", \"year\"]."
          end

          test "with invalid zoom level adds error to view object" do
            project = create(:memex_project)

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { zoom_level: "day" } })
            refute view.valid?
            assert_equal "day is not a member of [\"month\", \"quarter\", \"year\"].", view.errors["layout_settings.roadmap.zoom_level"].first
          end
        end

        context "marker fields" do
          test "filters out non-date columns and columns not belonging to the project" do
            project = create(:memex_project)
            start_date_field = create(:memex_project_column, memex_project: project, data_type: :date, user_defined: true, name: "Start date")
            end_date_field = create(:memex_project_column, memex_project: project, data_type: :date, user_defined: true, name: "End date")
            another_date_field = create(:memex_project_column, memex_project: project, data_type: :date, user_defined: true, name: "Date 3")
            number_field = create(:memex_project_column, memex_project: project, data_type: :number, user_defined: true, name: "Number")

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { marker_fields: [number_field.id, project.columns.last.id + 100] } })
            assert view.valid?
            assert_equal [], view.layout_settings["roadmap"]["marker_fields"]

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { marker_fields: [number_field.id, start_date_field.id] } })
            assert view.valid?
            assert_equal [start_date_field.id], view.layout_settings["roadmap"]["marker_fields"]
          end
        end

        context "date fields" do
          test "filters out non-date columns and columns not belonging to the project" do
            project = create(:memex_project)
            start_date_field = create(:memex_project_column, memex_project: project, data_type: :date, user_defined: true, name: "Start date")
            end_date_field = create(:memex_project_column, memex_project: project, data_type: :date, user_defined: true, name: "End date")
            another_date_field = create(:memex_project_column, memex_project: project, data_type: :date, user_defined: true, name: "Date 3")
            number_field = create(:memex_project_column, memex_project: project, data_type: :number, user_defined: true, name: "Number")

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { date_fields: [number_field.id, project.columns.last.id + 100] } })
            assert view.valid?
            assert_equal [], view.layout_settings["roadmap"]["date_fields"]

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { date_fields: [number_field.id, start_date_field.id] } })
            assert view.valid?
            assert_equal [start_date_field.id], view.layout_settings["roadmap"]["date_fields"]
          end

          test "accepts up to 2 date fields" do
            project = create(:memex_project)
            start_date_field = create(:memex_project_column, memex_project: project, data_type: :date, user_defined: true, name: "Start date")
            end_date_field = create(:memex_project_column, memex_project: project, data_type: :date, user_defined: true, name: "End date")
            another_date_field = create(:memex_project_column, memex_project: project, data_type: :date, user_defined: true, name: "Date 3")

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { date_fields: "string" } })
            refute view.valid?
            assert_includes view.errors["layout_settings.roadmap.date_fields"], "For 'properties/date_fields', \"string\" is not an array."

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { date_fields: ["string"] } })
            refute view.valid?
            assert_equal view.errors["layout_settings.roadmap.date_fields.0"], ["No subschema in \"oneOf\" matched.", "For 'oneOf/0', \"string\" is not an integer.", "string is not a member of [\"none\"]."]

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { date_fields: [start_date_field.id, end_date_field.id, another_date_field.id] } })
            refute view.valid?
            assert_includes view.errors["layout_settings.roadmap.date_fields"], "No more than 2 items are allowed; 3 were supplied."

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { date_fields: [start_date_field.id, end_date_field.id] } })
            assert view.valid?
            assert_equal [start_date_field.id, end_date_field.id], view.layout_settings["roadmap"]["date_fields"]

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { date_fields: [start_date_field.id] } })
            assert view.valid?
            assert_equal [start_date_field.id], view.layout_settings["roadmap"]["date_fields"]

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { date_fields: [start_date_field.id, "none"] } })
            assert view.valid?
            assert_equal [start_date_field.id, "none"], view.layout_settings["roadmap"]["date_fields"]

            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { date_fields: [] } })
            assert view.valid?
            assert_equal [], view.layout_settings["roadmap"]["date_fields"]
          end

          test "date fields can be iteration columns" do
            project = create(:memex_project)
            date_field = create(:memex_project_column, memex_project: project, data_type: :date, user_defined: true, name: "Date")
            iteration = create(:memex_project_column, memex_project: project, data_type: :iteration, user_defined: true, name: "Iteration 1")

            # Works with a single iteration field
            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { date_fields: [iteration.id] } })
            assert view.valid?
            assert_equal [iteration.id], view.layout_settings["roadmap"]["date_fields"]

            # Works with the same iteration field provided twice
            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { date_fields: [iteration.id, iteration.id] } })
            assert view.valid?
            assert_equal [iteration.id, iteration.id], view.layout_settings["roadmap"]["date_fields"]

            # Works with the mixed date and iteration fields
            view = build(:memex_project_view, memex_project: project, layout_settings: { roadmap: { date_fields: [iteration.id, date_field.id] } })
            assert view.valid?
            assert_equal [iteration.id, date_field.id], view.layout_settings["roadmap"]["date_fields"]
          end
        end
      end


      context "#column_limits" do
        test "disallow invalid types for column limits" do
          view = build(:memex_project_view, layout_settings: {
            board: {
              column_limits: "invalid"
            }
          })

          refute view.valid?
          assert_includes view.errors["layout_settings.board.column_limits"], "For 'properties/column_limits', \"invalid\" is not an object."
        end

        test "disallow invalid types for column limits for a column" do
          project = create(:memex_project)
          field = create(:single_select_memex_column, memex_project: project, name: "New field")

          view = build(:memex_project_view, layout_settings: {
            board: {
              column_limits: {
                "#{field.id}": "invalid"
              }
            }
          })

          refute view.valid?
          assert_includes view.errors["layout_settings.board.column_limits.#{field.id}"], "For 'properties/column_limits', \"invalid\" is not an object."
        end

        test "allow emtpy limit hashes" do
          project = create(:memex_project)
          field = create(:single_select_memex_column, memex_project: project, name: "New field")

          view = build(:memex_project_view, layout_settings: {
            board: {
              column_limits: {
                "#{field.id}": {}
              }
            }
          })

          assert view.valid?
        end

        test "allow a limit hash with an option id and number" do
          project = create(:memex_project)
          field = create(:single_select_memex_column, memex_project: project, name: "New field")

          view = build(:memex_project_view, memex_project: project, layout_settings: {
            board: {
              column_limits: {
                "#{field.id}": {
                  "#{field.settings["options"][0]["id"]}" => 12
                }
              }
            }
          })

          assert view.valid?
          assert_equal view.layout_settings["board"]["column_limits"],  {
            "#{field.id}" => {
              "#{field.settings["options"][0]["id"]}" => 12
            }
          }
        end

        test "allow a limit hash with an option id and null" do
          project = create(:memex_project)
          field = create(:single_select_memex_column, memex_project: project, name: "New field")

          view = build(:memex_project_view, memex_project: project, layout_settings: {
            board: {
              column_limits: {
                "#{field.id}": {
                  "#{field.settings["options"][0]["id"]}" => nil
                }
              }
            }
          })

          refute view.valid?
          assert_includes view.errors["layout_settings.board.column_limits.#{field.id}.#{field.settings["options"][0]["id"]}"], "For 'properties/column_limits', nil is not an integer."
        end

        test "disallow a limit hash with an option id and non-numerical value" do
          project = create(:memex_project)
          field = create(:single_select_memex_column, memex_project: project, name: "New field")

          view = build(:memex_project_view, memex_project: project, layout_settings: {
            board: {
              column_limits: {
                "#{field.id}": {
                  "#{field.settings["options"][0]["id"]}" => "invalid"
                }
              }
            }
          })

          refute view.valid?
          assert_includes view.errors["layout_settings.board.column_limits.#{field.id}.#{field.settings["options"][0]["id"]}"], "For 'properties/column_limits', \"invalid\" is not an integer."
        end

        test "disallow a limit hash with an option id and number less than 0" do
          project = create(:memex_project)
          field = create(:single_select_memex_column, memex_project: project, name: "New field")

          view = build(:memex_project_view, memex_project: project, layout_settings: {
            board: {
              column_limits: {
                "#{field.id}": {
                  "#{field.settings["options"][0]["id"]}" => -1
                }
              }
            }
          })

          refute view.valid?
          assert_includes view.errors["layout_settings.board.column_limits.#{field.id}.#{field.settings["options"][0]["id"]}"], "-1 must be greater than or equal to 0."
        end

        test "disallow a limit hash with an option id and number greater than 1000000" do
          project = create(:memex_project)
          field = create(:single_select_memex_column, memex_project: project, name: "New field")

          view = build(:memex_project_view, memex_project: project, layout_settings: {
            board: {
              column_limits: {
                "#{field.id}": {
                  "#{field.settings["options"][0]["id"]}" => 1000001
                }
              }
            }
          })

          refute view.valid?
          assert_includes view.errors["layout_settings.board.column_limits.#{field.id}.#{field.settings["options"][0]["id"]}"], "1000001 must be less than or equal to 1000000."
        end

        test "invalid field ids are filtered" do
          project = create(:memex_project)
          field = create(:single_select_memex_column, memex_project: project, name: "New field")
          field.destroy
          view = build(:memex_project_view, memex_project: project, layout_settings: {
            board: {
              column_limits: {
                "#{field.id}": {
                  "#{field.settings["options"][0]["id"]}" => 1
                }
              }
            }
          })

          assert view.valid?
          assert_equal view.layout_settings["board"]["column_limits"],  {}
        end

        test "invalid field option ids are filtered" do
          project = create(:memex_project)
          field = create(:single_select_memex_column, memex_project: project, name: "New field")
          view = build(:memex_project_view, memex_project: project, layout_settings: {
            board: {
              column_limits: {
                "#{field.id}": {
                  "aaa" => 1
                }
              }
            }
          })

          assert view.valid?
          assert_equal view.layout_settings["board"]["column_limits"],  {
            "#{field.id}" => {}
          }
        end
      end

      context "#column_widths" do
        %w[table roadmap].each do |layout|
          test "disallows invalid types for #{layout}" do
            view = build(:memex_project_view, layout_settings: { "#{layout}" => { column_widths: "yes" } })
            refute view.valid?

            assert_includes view.errors["layout_settings.#{layout}.column_widths"], "For 'properties/column_widths', \"yes\" is not an object."
          end

          test "disallows invalid value types for #{layout}" do
            project = create(:memex_project)
            field = create(:memex_project_column, memex_project: project, name: "New field")

            view = build(:memex_project_view, layout_settings: { "#{layout}" => { column_widths: { "#{field.id}" => "aaa" } } })
            refute view.valid?

            assert_includes view.errors["layout_settings.#{layout}.column_widths.#{field.id}"], "For 'definitions/column_widths', \"aaa\" is not an integer."
          end

          test "disallows values exceeding range for #{layout}" do
            project = create(:memex_project)
            field = create(:memex_project_column, memex_project: project, name: "New field")

            view = build(:memex_project_view, layout_settings: { "#{layout}" => { column_widths: { "#{field.id}" => 10001 } } })
            refute view.valid?

            assert_includes view.errors["layout_settings.#{layout}.column_widths.#{field.id}"], "10001 must be less than or equal to 10000."
          end

          test "disallows invalid keys for #{layout}" do
            view = build(:memex_project_view, layout_settings: { "#{layout}" => { column_widths: { "aaa": 400 } } })
            refute view.valid?

            assert_includes view.errors["layout_settings.#{layout}.column_widths"], "\"aaa\" is not a permitted key."
          end

          test "filters out settings for nonexistent column ids for #{layout}" do
            view = build(:memex_project_view, layout_settings: { "#{layout}" => { column_widths: { -2 => 400 } } })
            assert view.valid?

            assert_equal ({}), view.layout_settings[layout]["column_widths"]
          end

          test "filters out settings for deleted column ids for #{layout}" do
            project = create(:memex_project)
            field = create(:memex_project_column, memex_project: project, name: "New field")
            field.destroy

            view = build(:memex_project_view, layout_settings: { "#{layout}" => { column_widths: { "#{field.id}" => 400 } } })
            assert view.valid?

            assert_equal ({}), view.layout_settings[layout]["column_widths"]
          end

          test "allows settings for valid columns for #{layout}" do
            project = create(:memex_project)
            field = create(:memex_project_column, memex_project: project, name: "New field")
            field_2 = create(:memex_project_column, memex_project: project, name: "New field 2")

            view = build(:memex_project_view, memex_project: project, layout_settings: { "#{layout}" => { column_widths: { "#{field.id}" => 400,  "#{field_2.id}" => 400 } } })
            assert view.valid?

            assert_equal ({ "#{field.id}" => 400, "#{field_2.id}" => 400  }), view.layout_settings[layout]["column_widths"]
          end
        end
      end
    end
  end



  context "#visible_columns" do
    test "returns column objects that match the IDs in visible_fields" do
      memex = create(:memex_project)

      # The visible column on the `memex_project_columns` table should be ignored.
      memex.memex_project_columns.update_all(visible: false)

      title_column = memex.columns.find(&:title?)
      assignees_column = memex.columns.find(&:assignees?)

      view = create(
        :memex_project_view,
        memex_project: memex,
        visible_fields: [
          # This column that doesn't belong to the memex should be ignored.
          memex.columns.map(&:id).min - 1,

          # These columns should be returned.
          title_column.id,
          assignees_column.id,

          # This column that doesn't belong to the memex should be ignored.
          memex.columns.map(&:id).max + 1,
        ]
      )

      assert_equal [title_column, assignees_column], view.visible_columns
    end
  end

  context "#set_name" do
    test "sets a default name for a view when none is provided" do
      view = create(:memex_project_view, name: nil)
      assert_equal "View #{view.number}", view.name
    end
  end

  context "#set_number" do
    test "generates a unique number per Memex project" do
      memex_1 = create(:memex_project)
      memex_2 = create(:memex_project)
      memex_3 = create(:memex_project)

      # Reminder: Each project has a default view with a number of `1`.
      assert_equal 2, create(:memex_project_view, memex_project: memex_1).number
      assert_equal 2, create(:memex_project_view, memex_project: memex_2).number
      assert_equal 3, create(:memex_project_view, memex_project: memex_1).number
      assert_equal 2, create(:memex_project_view, memex_project: memex_3).number
      assert_equal 4, create(:memex_project_view, memex_project: memex_1).number
      assert_equal 3, create(:memex_project_view, memex_project: memex_2).number
    end
  end

  context "#remove_column!" do
    test "removes the column from group_by" do
      project = create(:memex_project)
      view = project.default_view
      column = create(:memex_project_column, memex_project: project, name: "Test", user_defined: true)
      column_2 = create(:memex_project_column, memex_project: project, name: "Test 2", user_defined: true)

      view.make_column_visible!(column)
      view.make_column_visible!(column_2)

      view.update!(group_by: [column.id, column_2.id])
      view.remove_column!(column)
      assert_equal [column_2.id], view.group_by
    end

    test "removes the column from vertical_group_by" do
      project = create(:memex_project)
      view = project.default_view
      column = create(:memex_project_column, memex_project: project, name: "Test", user_defined: true)
      column_2 = create(:memex_project_column, memex_project: project, name: "Test 2", user_defined: true)

      view.make_column_visible!(column)
      view.make_column_visible!(column_2)

      view.update!(vertical_group_by: [column.id, column_2.id])
      view.remove_column!(column)
      assert_equal [column_2.id], view.vertical_group_by
    end

    test "allows removing a column if vertical_group_by is nil" do
      project = create(:memex_project)
      view = project.default_view
      column = create(:memex_project_column, memex_project: project, name: "Test", user_defined: true)
      column_2 = create(:memex_project_column, memex_project: project, name: "Test 2", user_defined: true)

      view.make_column_visible!(column)
      view.make_column_visible!(column_2)

      view.update_attribute(:vertical_group_by, nil)
      view.remove_column!(column)
      assert_equal [], view.vertical_group_by
    end

    test "removes the column from sort_by" do
      project = create(:memex_project)
      view = project.default_view
      column = create(:memex_project_column, memex_project: project, name: "Test", user_defined: true)
      column_2 = create(:memex_project_column, memex_project: project, name: "Test 2", user_defined: true)

      view.reload

      view.update!(sort_by: [[column.id, "asc"], [column_2.id, "desc"]])
      view.remove_column!(column)
      assert_equal [[column_2.id, "desc"]], view.sort_by
    end

    test "removes the column from visibility" do
      project = create(:memex_project)
      view = project.default_view
      column = create(:memex_project_column, memex_project: project, name: "Test", user_defined: true)

      view.make_column_visible!(column)
      assert view.reload.column_visible?(column)

      view.remove_column!(column)
      refute view.reload.column_visible?(column)
    end

    test "removes the column from sum aggregation" do
      column = create(:memex_project_column, data_type: :number, user_defined: true, name: "Points")
      memex = column.memex_project

      view = create(:memex_project_view, memex_project: memex, aggregation_settings: { hide_items_count: true, sum: [column.id] })

      assert view.reload.column_summed?(column)

      view.remove_column!(column)
      refute view.reload.column_summed?(column)
    end

    test "removes the column from roadmap date fields" do
      column = create(:memex_project_column, data_type: :date, user_defined: true, name: "Date")
      memex = column.memex_project

      view = create(:memex_project_view, memex_project: memex, layout_settings: { roadmap: { date_fields: [column.id] } })

      assert view.reload.column_in_roadmap_date_fields?(column)
      view.remove_column!(column)
      refute view.reload.column_in_roadmap_date_fields?(column)
    end

    test "removes the column from roadmap marker fields" do
      column = create(:memex_project_column, data_type: :date, user_defined: true, name: "Date")
      memex = column.memex_project

      view = create(:memex_project_view, memex_project: memex, layout_settings: { roadmap: { marker_fields: [column.id] } })

      assert view.reload.column_in_roadmap_marker_fields?(column)
      view.remove_column!(column)
      refute view.reload.column_in_roadmap_marker_fields?(column)
    end

    test "removes the column widths for table and roadmap" do
      column = create(:memex_project_column)
      memex = column.memex_project

      view = create(:memex_project_view, memex_project: memex, layout_settings: { table: { column_widths: { "#{column.id}" => 300 } }, roadmap: { column_widths: { "#{column.id}" => 200 } } })

      assert view.reload.column_has_width_for_layout?(column, "table")
      assert view.reload.column_has_width_for_layout?(column, "roadmap")
      view.remove_column!(column)
      refute view.reload.column_has_width_for_layout?(column, "table")
      refute view.reload.column_has_width_for_layout?(column, "roadmap")
    end

    test "removes the column from slice_by" do
      column = create(:memex_project_column, data_type: :single_select, user_defined: true)
      memex = column.memex_project

      view = create(:memex_project_view, memex_project: memex, slice_by: { field: column.id })
      assert view.reload.column_sliced?(column)

      view.remove_column!(column)
      refute view.reload.column_sliced?(column)
    end

    test "does not check sum aggregation if it does not exist" do
      column = create(:memex_project_column, data_type: :number, user_defined: true, name: "Points")
      memex = column.memex_project

      view = build(:memex_project_view, memex_project: memex)

      refute view.column_summed?(column)
    end

    test "removes the column from limits" do
      column = create(:single_select_memex_column, memex_project: @memex, name: "New field")
      memex = column.memex_project

      view = create(:memex_project_view, memex_project: memex, layout_settings: { board: { column_limits: { "#{column.id}" => { "#{column.settings["options"][0]["id"]}": 1 } } } })

      assert view.reload.column_has_limits_for_board?(column)

      view.remove_column!(column)
      refute view.reload.column_has_limits_for_board?(column)
    end
  end

  test "disallows deleting the last view of a project" do
    project = create(:memex_project)
    view = project.default_view
    view_2 = create(:memex_project_view, memex_project: project)

    assert view.destroy
    assert view.destroyed?

    refute view_2.destroy
    refute view_2.destroyed?
    assert_includes view_2.errors[:base], "Cannot destroy the last remaining view of a project"
  end

  context "Project View instrumentation" do
    test "instruments default view" do
      Timecop.freeze do
        GitHub.context.push(actor_id: @user.id)
        events = subscribe "project_view.create"
        project = create(:memex_project, creator: @user, owner: @org, public: true)

        view = project.default_view

        expected_payload = {
          view_id: view.id,
          actor: @user.login,
          actor_id: @user.id,
          org: @org.login,
          org_id: @org.id,
          project_id: project.id,
          project_number: project.number,
          public_project: true,
          project_kind: "MemexProject"
        }

        assert event = events.pop, "an event was expected"
        assert_equal "project_view.create", event.name
        assert_equal expected_payload, event.payload

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(view.creator),
          project_view: Hydro::EntitySerializer.memex_project_view(view),
          project: Hydro::EntitySerializer.memex_project(project)
        }, schema: "github.memex.v0.MemexProjectViewCreate")
      end
    end

    test "instruments project view creation" do
      Timecop.freeze do
        GitHub.context.push(actor_id: @user.id)
        events = subscribe "project_view.create"
        project = create(:memex_project, creator: @user, owner: @org)

        reset_hydro

        view = create(:memex_project_view, memex_project: project, creator: @user)

        expected_payload = {
          view_id: view.id,
          actor: view.creator.login,
          actor_id: view.creator.id,
          org: @org.login,
          org_id: @org.id,
          project_id: project.id,
          project_number: project.number,
          public_project: false,
          project_kind: "MemexProject"
        }

        assert event = events.pop, "an event was expected"
        assert_equal "project_view.create", event.name
        assert_equal expected_payload, event.payload

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(view.creator),
          project_view: Hydro::EntitySerializer.memex_project_view(view),
          project: Hydro::EntitySerializer.memex_project(project.reload)
        }, schema: "github.memex.v0.MemexProjectViewCreate")
      end
    end

    test "instruments project view update" do
      Timecop.freeze do
        GitHub.context.push(actor_id: @other_user.id)
        events = subscribe "project_view.update"
        project = create(:memex_project, creator: @user, owner: @org)
        view = create(:memex_project_view, memex_project: project)
        reset_hydro

        view.update!(name: "New name")

        expected_payload = {
          view_id: view.id,
          actor: @other_user.login,
          actor_id: @other_user.id,
          org: @org.login,
          org_id: @org.id,
          project_id: project.id,
          project_number: project.number,
          public_project: false,
          project_kind: "MemexProject"
        }

        assert event = events.pop, "an event was expected"
        assert_equal "project_view.update", event.name
        assert_equal expected_payload, event.payload

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@other_user),
          project_view: Hydro::EntitySerializer.memex_project_view(view),
          project: Hydro::EntitySerializer.memex_project(project.reload)
        }, schema: "github.memex.v0.MemexProjectViewUpdate")
      end
    end

    test "instruments project view deletion" do
      Timecop.freeze do
        GitHub.context.push(actor_id: @other_user.id)
        events = subscribe "project_view.delete"
        project = create(:memex_project, creator: @user, owner: @org, public: false)
        view = create(:memex_project_view, memex_project: project)

        project.reload

        expected_payload = {
          view_id: view.id,
          actor: @other_user.login,
          actor_id: @other_user.id,
          org: @org.login,
          org_id: @org.id,
          project_id: project.id,
          project_number: project.number,
          public_project: project.public?,
          project_kind: "MemexProject"
        }

        assert view.destroy
        assert view.destroyed?

        assert event = events.pop, "an event was expected"
        assert_equal "project_view.delete", event.name
        assert_equal expected_payload, event.payload

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@other_user),
          project_view: Hydro::EntitySerializer.memex_project_view(view),
          project: Hydro::EntitySerializer.memex_project(project)
        }, schema: "github.memex.v0.MemexProjectViewDestroy")
      end
    end
  end

  [:filter, :name].each do |field|
    test "supports emoji for #{field}" do
      view = create(:memex_project_view, field => "we ❤️ emojis")

      assert_multibyte_tracked_changes(view, field)
    end
  end

  context "#async_group_by_column" do
    test "returns the horizontal group by column if in table view" do
      view = create(:memex_project_view)
      column = view.memex_project.status_column
      view.update!(layout: "table_layout", group_by: [column.id])

      assert_equal column, view.async_group_by_column.sync
    end

    test "returns nil if ungrouped in table view" do
      view = create(:memex_project_view)
      view.update!(layout: "table_layout")

      assert_nil view.async_group_by_column.sync
    end

    test "returns the vertical group by column if in board view" do
      view = create(:memex_project_view)
      column = view.memex_project.status_column
      view.update!(layout: "board_layout", group_by: [column.id])

      assert_equal column, view.async_group_by_column.sync
    end

    test "returns status column if ungrouped in board view" do
      view = create(:memex_project_view)
      view.update!(layout: "board_layout")

      assert_equal view.memex_project.status_column, view.async_group_by_column.sync
    end

    # This is testing a very edgy-case. Reading through our domain code we should never end up in this state but
    # we have records which will end up in a state where vertical_group_by is nil.  Also it should be noted that
    # all callers of vertical_group_by protect themselves from a nil value so this test is to follow in that
    # existing paved path. Issue for future reference: https://github.com/github/mobile/issues/3793
    test "returns status column if vertical_group_by is explicity nil" do
      view = create(:memex_project_view)
      view.update!(layout: "board_layout")

      # We want to update this view record directly as there are callbacks that would prevent us from setting the
      # vertical_group_by column to nil.
      view.update_column(:vertical_group_by, nil)

      assert_nil   view.vertical_group_by
      assert_equal view.memex_project.status_column, view.async_group_by_column.sync
    end
  end

  context "async_sort_by_column" do
    test "returns the sort by column if set" do
      view = create(:memex_project_view)
      column = view.memex_project.status_column
      view.update!(sort_by: [[column.id, "asc"]])

      expected = { column: column, direction: "asc" }
      assert_equal expected, view.async_sort_by_column.sync
    end

    test "returns nil if sort by column is not set" do
      view = create(:memex_project_view)

      assert_nil view.async_sort_by_column.sync
    end
  end

  context "set_number" do
    test "uses a unique sequence scoped to the memex project for numbering" do
      # The first view created should be numbered starting from 1
      project = create(:memex_project)
      assert_equal project.memex_project_views.count, 1
      assert_equal project.memex_project_views.first.number, 1

      # Create a new workflow
      initial_workflows_count = project.workflows.count
      create(:memex_project_workflow, memex_project: project)
      assert_equal project.workflows.count, initial_workflows_count + 1

      # Create a chart
      create(:memex_project_chart, memex_project: project)
      assert_equal project.charts.count, 1

      # The second view created should be numbered 2, independent of other entities that
      # were just created
      new_view = create(:memex_project_view, memex_project: project)
      assert_equal new_view.number, 2
    end

    test "it uses a unique view sequence per memex_project" do
      memex_project_1 = create(:memex_project)
      memex_project_2 = create(:memex_project)
      refute_equal memex_project_1.id, memex_project_2.id

      assert_equal memex_project_1.memex_project_views.first.number, 1
      assert_equal memex_project_2.memex_project_views.first.number, 1
    end

    test "For views that previously used the shared sequence, it continues the numbering with the next available number \
      but uses the new sequence" do
      # view created with the (MemexProjectView, memex_project.id) sequence
      project = create(:memex_project)
      view_1 = project.memex_project_views.first
      assert_equal project.memex_project_views.count, 1
      view_1.update_attribute(:number, 2)
      assert_equal view_1.number, 2

      # To simulate this being a view that was created with the shared sequence,
      # we will delete the (MemexProjectView, memex_project.id) sequence
      sql = "DELETE FROM sequences WHERE context_type=\"#{view_1.class.name}\" AND context_id=\"#{view_1.memex_project.id}\""
      ApplicationRecord::Domain::Sequences.connection.execute(sql)

      # Create a second view. It should be numbered 3
      view_2 = create(:memex_project_view, memex_project: project)
      assert_equal view_2.number, 3

      # A (MemexProjectView, memex_project.id) sequence should be created with the correct default
      ApplicationRecord::Domain::Sequences.table_name = "sequences"
      view_sequence = ApplicationRecord::Domain::Sequences.find_by(context_type: "MemexProjectView", context_id: view_1.memex_project.id)
      refute_nil view_sequence
      assert_equal view_sequence.number, 3
    end
  end
end
