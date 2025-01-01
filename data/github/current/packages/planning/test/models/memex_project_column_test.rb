# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @org = create(:organization)
    @memex = create(:memex_project, owner: @org)
    @user = create(:verified_user).tap { |u| @org.add_member(u) }
  end

  setup do
    GitHub.context.push(actor: @user)
  end

  context "reserved_column_names" do
    test "returns the reserved column names by default" do
      assert_equal MemexProjectColumn::RESERVED_COLUMN_NAMES, MemexProjectColumn.reserved_column_names
    end

    test "includes Type column for org-owned projects when not copying" do
      expected_reserved_column_names = MemexProjectColumn::RESERVED_COLUMN_NAMES + [MemexProjectColumn::TYPE_COLUMN_NAME]

      refute_predicate MemexProject::Copier, :copying?
      assert_equal expected_reserved_column_names, MemexProjectColumn.reserved_column_names(actor: @user, owner: @org)
    end

    test "does not include Type column for org-owned projects while copying" do
      MemexProject::Copier.with_copying do
        assert_predicate MemexProject::Copier, :copying?
        assert_equal MemexProjectColumn::RESERVED_COLUMN_NAMES, MemexProjectColumn.reserved_column_names(actor: @user, owner: @org)
      end
    end

    test "does not include Type column for user-owned projects" do
      refute_includes MemexProjectColumn.reserved_column_names(actor: @user, owner: @user), MemexProjectColumn::TYPE_COLUMN_NAME
    end
  end

  context "#matches_identifier?" do
    test "returns true for a system column when given a matching identifier" do
      column = create(:memex_project_column, user_defined: false, memex_project: @memex)
      assert column.matches_identifier?(column.id)
      assert column.matches_identifier?(column.name)
      assert column.matches_identifier?(column.name.upcase), "should ignore case"
    end

    test "returns true for a user column when given a matching identifier" do
      column = create(:memex_project_column, user_defined: true, memex_project: @memex)
      assert column.matches_identifier?(column.id)
    end

    test "returns false for a system column when given a different identifier" do
      column = create(:memex_project_column, user_defined: false, memex_project: @memex)
      refute column.matches_identifier?(column.id + 1)
      refute column.matches_identifier?(column.name + "otherStuff")
    end

    test "returns false for a user column when given a different identifier" do
      column = create(:memex_project_column, user_defined: true, memex_project: @memex)
      refute column.matches_identifier?(column.name), "should not match a user column by its name"
      refute column.matches_identifier?(column.id + 1)
      refute column.matches_identifier?(column.name + "otherStuff")
    end

    test "returns false when not given an identifier" do
      column = create(:memex_project_column, memex_project: @memex)
      refute column.matches_identifier?(nil)
      refute column.matches_identifier?("")
      refute column.matches_identifier?("  ")
    end
  end

  context "validations" do
    test "requires memex project" do
      column = build(:memex_project_column, memex_project: nil)

      refute column.save
      assert_includes column.errors.full_messages, "Memex project can't be blank"
    end

    test "requires name" do
      column = build(:memex_project_column, name: nil)

      refute column.save
      assert_includes column.errors.full_messages, "Name can't be blank"
    end

    test "requires that name of a user-defined column not conflict with the name of a system-defined column" do
      %w[Title title TiTlE].each do |title_variation|
        column = build(:memex_project_column, user_defined: true, name: title_variation)

        refute column.save
        assert_includes column.errors.full_messages, "Name cannot have a reserved value"
      end
    end

    test "requires that name of a user-defined column does not contain restricted ':' character" do
      column = build(:memex_project_column, user_defined: true, name: "Column with: colon")

      refute column.save
      assert_includes column.errors.full_messages, "Name cannot contain any of the following characters: :"
    end

    test "disallows creating a user-defined column with a reserved column name" do
      ["Assignees", "Reviewers", "Labels", "Linked Issues", "Linked Pull Requests", "Milestone", "Repository", "Title", "Status", "Repo",
        "Assignee", "Reviewer", "Label", "Linked Issue", "Linked Pull Request", "Tracks", "Tracked By", "is", "no", "author", "created", "updated"].each do |title|
        column = build(:memex_project_column, user_defined: true, name: title)

        refute column.save
        assert_includes column.errors.full_messages, "Name cannot have a reserved value"
      end
      column = build(:memex_project_column, user_defined: true, name: "Status")

      refute column.save
      assert_includes column.errors.full_messages, "Name cannot have a reserved value"
    end

    test "allows creating a user-defined column with a Type column name when user-owned project" do
      user_owned_memex = create(:memex_project, owner: @user)
      column = build(:memex_project_column, memex_project: user_owned_memex, user_defined: true, name: "Type")

      assert_predicate user_owned_memex, :user_owned?, "memex should be user-owned"
      assert column.save
      assert_equal "Type", column.reload.name
    end

    test "does not allow creating a user-defined column with a Type column name when org-owned project" do
      column = build(:memex_project_column, memex_project: @memex, user_defined: true, name: "Type")

      assert_predicate @memex, :org_owned?, "memex should be org-owned"
      refute column.save
      assert_includes column.errors.full_messages, "Name cannot have a reserved value"
    end

    test "allows creating a user-defined column with a Type column for org-owned project when copying projects" do
      reserved_columns = MemexProjectColumn.reserved_column_names(actor: @user, owner: @org)
      assert_predicate @memex, :org_owned?, "memex should be org-owned"
      assert_includes reserved_columns, MemexProjectColumn::TYPE_COLUMN_NAME, "expected Type column to be reserved"
      @memex.memex_project_columns.issue_type.destroy_all

      MemexProject::Copier.with_copying do
        memex_project_column = create(:memex_project_column, memex_project: @memex, user_defined: true, name: MemexProjectColumn::TYPE_COLUMN_NAME)
        assert_predicate memex_project_column, :persisted?
        assert_predicate memex_project_column, :user_defined?
      end
    end

    test "allows creating a user-defined column with a Type column name when user-owned project and copying projects" do
      user_owned_memex = create(:memex_project, owner: @user)
      reserved_columns = MemexProjectColumn.reserved_column_names(actor: @user, owner: @user)
      assert_predicate user_owned_memex, :user_owned?, "memex should be user-owned"
      refute_includes reserved_columns, MemexProjectColumn::TYPE_COLUMN_NAME, "expected Type column to be reserved"

      MemexProject::Copier.with_copying do
        memex_project_column = create(:memex_project_column, memex_project: user_owned_memex, user_defined: true, name: MemexProjectColumn::TYPE_COLUMN_NAME)
        assert_predicate memex_project_column, :persisted?
        assert_predicate memex_project_column, :user_defined?
      end
    end

    test "allows creating a system-defined column with a Type column name when issue_types is enabled and copying projects" do
      reserved_columns = MemexProjectColumn.reserved_column_names(actor: @user, owner: @org)
      assert_includes reserved_columns, MemexProjectColumn::TYPE_COLUMN_NAME, "expected Type column to be reserved"

      MemexProject::Copier.with_copying do
        memex_project_column = create(:memex_project_column, user_defined: false, name: MemexProjectColumn::TYPE_COLUMN_NAME)
        assert_predicate memex_project_column, :persisted?
        refute_predicate memex_project_column, :user_defined?
      end
    end

    test "disallows updating a user-defined column to have the name 'Status'" do
      column = create(:memex_project_column, memex_project: @memex, user_defined: true, name: "Stage")

      refute column.update(name: "Status")
      assert_includes column.errors.full_messages, "Name cannot have a reserved value"
    end

    test "does not complain if a column already named 'Status' is updated" do
      column = @memex.status_column

      # Just to make this particularly tricky, make sure that we don't complain if the update to
      # a non-name attribute (in this case, `visible`) also contains a no-op update to `name`.
      assert column.update(name: "Status", visible: !column.visible)

      assert_predicate column, :valid?
      assert_equal "Status", column.reload.name
    end

    test "requires the 'Status' column to have valid options" do
      column = @memex.status_column

      column.settings = { options: nil }

      refute column.save
      assert_includes column.errors.full_messages, "Settings requires a minimum of one Status value"
    end

    test "requires the 'Status' column to have a minimum of one value" do
      column = @memex.status_column

      column.settings = { options: [] }

      refute column.save
      assert_includes column.errors.full_messages, "Settings requires a minimum of one Status value"
    end

    test "requires that name be unique within the scope of a memex project" do
      memex = create(:memex_project)
      another_memex = create(:memex_project)
      column = build(:memex_project_column, name: "Column 1", memex_project: memex)
      valid_column = build(:memex_project_column, name: "Column 1", memex_project: another_memex)
      duplicate_column = build(:memex_project_column, name: "Column 1", memex_project: memex, user_defined: true, position: column.position + 1)

      assert column.save
      assert valid_column.save
      refute duplicate_column.save
      assert_includes duplicate_column.errors.full_messages, "Name has already been taken"
    end

    test "name uniqueness validation should also work on update" do
      memex = create(:memex_project)
      column1 = create(:memex_project_column, name: "Column 1", memex_project: memex)
      column2 = create(:memex_project_column, name: "Column 2", memex_project: memex, user_defined: true)

      column2.reload

      # it saves if we update its name without breaking uniqueness
      column2.name = "What a cool & unique name!"
      assert column2.save

      # but if fails if we try to use an existing name
      column2.name = "Column 1"
      refute column2.save
      assert_includes column2.errors.full_messages, "Name has already been taken"
    end

    test "requires that name be case-insesitivly unique within the scope of a memex project" do
      memex = create(:memex_project)
      column = build(:memex_project_column, name: "Custom Column", memex_project: memex)
      duplicate_column = build(:memex_project_column, name: "custom column", memex_project: memex, user_defined: true, position: column.position + 1)

      assert column.save
      refute duplicate_column.save
      assert_includes duplicate_column.errors.full_messages, "Name has already been taken"
    end

    test "requires that name using dashes and spaces within the scope of a memex project is equal" do
      memex = create(:memex_project)
      column = build(:memex_project_column, name: "Custom Column Name", memex_project: memex)
      assert column.save

      ["Custom-Column Name", "custom-column-name", "custom column name"].each do |title_variation|
        duplicate_column = build(:memex_project_column, name: title_variation, memex_project: memex, user_defined: true, position: column.position + 1)

        refute duplicate_column.save
        assert_includes duplicate_column.errors.full_messages, "Name has already been taken"
      end
    end

    test "encodes name as UTF-8" do
      column = build(
        :memex_project_column,
        name: "other encoding".dup.tap { |t| t.force_encoding("ISO-8859-1") }
      )

      assert_equal Encoding::UTF_8, column.name.encoding
    end

    test "validation for names using emoji" do
      memex = create(:memex_project)
      column = build(:memex_project_column, name: "Kolumna Piąta 😬👴🏻👨‍👩‍👧‍👧", memex_project: memex)
      assert column.save
      ["Kolumna Piąta 😬👴🏻👨‍👩‍👧‍👧", "kolumna-piąta-😬👴🏻👨‍👩‍👧‍👧"].each do |title_variation|
        duplicate_column = build(:memex_project_column, name: title_variation, memex_project: memex, user_defined: true, position: column.position + 1)
        refute duplicate_column.save
        assert_includes duplicate_column.errors.full_messages, "Name has already been taken"
      end
    end

    test "requires name be within size limit" do
      column = build(:memex_project_column, name: "x" * (MemexProjectColumn::NAME_BYTESIZE_LIMIT + 1))

      refute column.save
      assert_includes column.errors.full_messages, "Name is too long (maximum is 63 characters)"
    end

    test "does not allow a system-defined column name to be updated" do
      memex = create(:memex_project)
      column = memex.find_column_by_name_or_id("Title")
      assert_predicate column, :system_defined?

      column.name = "New Name"
      refute column.save
      assert_includes column.errors.full_messages, "Name cannot be changed for a system defined column"
    end

    test "allows a user-defined column name to be updated" do
      memex = create(:memex_project)
      column = create(:memex_project_column, memex_project: memex, user_defined: true, name: "Old Name")
      assert_equal "Old Name", column.name

      column.name = "New Name"
      assert column.save
      assert_equal "New Name", column.reload.name
    end

    test "requires data_type" do
      column = build(:memex_project_column, data_type: nil)

      refute column.save
      assert_includes column.errors.full_messages, "Data type can't be blank"
    end

    test "requires data_type to be a defined value" do
      assert_raises ArgumentError do
        build(:memex_project_column, data_type: "multi_select")
      end
    end

    test "requires user_defined" do
      column = build(:memex_project_column, user_defined: nil)

      refute column.save
      assert_includes column.errors.full_messages, "User defined is not included in the list"
    end

    test "requires visible" do
      column = build(:memex_project_column, visible: nil)

      refute column.save
      assert_includes column.errors.full_messages, "Visible is not included in the list"
    end

    test "requires position" do
      column = build(:memex_project_column, position: nil)

      refute column.save
      assert_includes column.errors.full_messages, "Position can't be blank"
    end

    test "requires position be positive" do
      column = build(:memex_project_column, position: 0)

      refute column.save
      assert_includes column.errors.full_messages, "Position must be greater than 0"
    end

    test "requires position be unique within the project" do
      existing_column = create(:memex_project_column, user_defined: false)
      new_column = build(
        :memex_project_column,
        memex_project: existing_column.memex_project,
        position: existing_column.position
      )

      refute new_column.save
      assert_includes new_column.errors.full_messages, "Position has already been taken"
    end

    test "can create and delete column when a column with position over/at max column limit already exists" do
      fake_column_limit = MemexProjectColumn.default_columns.length + 2
      events = subscribe "project_field.delete"

      MemexProject.stub_const(:COLUMN_LIMIT, fake_column_limit) do
        # create a column with position at the limit
        new_column = create(
          :memex_project_column,
          user_defined: false,
          position: fake_column_limit
        )

        #create another column, position should be set over the limit
        column_past_limit = build(
          :memex_project_column,
          memex_project: new_column.memex_project,
          user_defined: true,
          data_type: "text",
          creator: @user
        )

        assert column_past_limit.save
        assert_equal column_past_limit.reload.position, fake_column_limit + 1

        new_column.destroy
        assert event = events.pop, "a delete event was expected"
        assert_equal "project_field.delete", event.name
      end
    end


    test "requires the creator to have a verified email for user-defined columns" do
      column = build(:memex_project_column, creator: create(:user), user_defined: true)
      refute column.creator.emails.verified.any?

      refute column.save
      assert_includes column.errors.full_messages, "Creator must have a verified email address"
    end unless GitHub.enterprise?

    test "does not require the creator to have a verified email for user-defined columns within Enterprise", enterprise_only: true do
      column = build(:memex_project_column, creator: create(:user), user_defined: true)
      refute column.creator.emails.verified.any?

      assert column.save
    end

    test "rejects a user-defined column from being persisted unless the default columns have been persisted" do
      memex = build(:memex_project, omit_default_columns: true)

      # Must save without validation to allow creation without default columns.
      assert memex.save(validate: false)

      column = memex.build_user_defined_column(name: "My Column", data_type: "text", creator: memex.creator)

      refute column.save
      assert_includes column.errors.full_messages, "User defined column cannot be added until default columns have been persisted"
    end

    test "rejects a user-defined column from being created when the memex project has hit the column limit" do
      memex = create(:memex_project)
      fake_column_limit = MemexProjectColumn.default_columns(excluding: [MemexProjectColumn::TYPE_COLUMN_NAME]).length

      MemexProject.stub_const(:COLUMN_LIMIT, fake_column_limit) do
        column_past_limit = build(:memex_project_column, memex_project: memex, user_defined: true)
        refute column_past_limit.save
        assert_includes column_past_limit.errors.full_messages, "Projects cannot have more than #{fake_column_limit} columns"
      end
    end

    test "does not reject a system-defined column from being created when the memex project has hit the column limit" do
      memex = create(:memex_project)
      fake_column_limit = MemexProjectColumn.default_columns.length

      MemexProject.stub_const(:COLUMN_LIMIT, fake_column_limit) do
        column_past_limit = build(:memex_project_column, memex_project: memex, user_defined: false)
        assert column_past_limit.save
      end
    end

    test "allows valid column settings" do
      memex = create(:memex_project)

      # Only change these emoji with caution: they have been specifically selected because they are
      # only returned from the database correctly it has been configured to decode and return
      # results with the `utf8mb4` character set rather than the usual `utf8` one.
      option_names = ["gold 🥇", "silver 🥈", "bronze 🥉"]

      single_select_column = build(
        :single_select_memex_column,
        memex_project: memex,
        settings: { width: 100, options: option_names.map { |name| { name: name, color: "GRAY", description: "" } } }
      )

      single_select_column.save!
      assert_equal option_names, single_select_column.reload.settings["options"].map { |o| o["name"] }
    end

    test "allows setting to be set to nil explicitly" do
      memex = create(:memex_project)
      single_select_column = build(:single_select_memex_column, memex_project: memex, settings: nil)

      assert single_select_column.save
    end

    test "wipes column values in the background when an option has been removed" do
      memex = create(:memex_project)

      single_select_column = build(
        :single_select_memex_column,
        memex_project: memex,
        settings: { width: 100, options: [{ name: "In Progress", color: "GREEN", description: "" }] }
      )

      single_select_column.save!
      option_id = single_select_column.reload.settings["options"][0]["id"]

      value = create(:single_select_memex_project_column_value, memex_project_column: single_select_column, value: option_id)

      assert_equal [value], single_select_column.memex_project_column_values

      perform_enqueued_jobs(only: RemoveMemexProjectColumnValuesJob) do
        single_select_column.update!(settings: nil)
      end

      assert_empty single_select_column.reload.memex_project_column_values
    end

    test "wipes column values in the background when an iteration has been removed" do
      iteration_column = create(
        :iteration_memex_column,
      )
      assert_equal 2, iteration_column.settings_iterations.size

      iteration_id = iteration_column.settings_iterations[0]["id"]

      value = create(:iteration_memex_project_column_value, memex_project_column: iteration_column, value: iteration_id)

      assert_equal [value], iteration_column.memex_project_column_values

      perform_enqueued_jobs(only: RemoveMemexProjectColumnValuesJob) do
        iteration_column.update!(settings: {
          configuration: {
            start_day: 1,
            duration: 14,
            iterations: iteration_column.settings_iterations[1] # update to delete the first iteration which was used in the column value
          }
        })
      end

      assert_equal 1, iteration_column.settings_iterations.size
      assert_empty iteration_column.reload.memex_project_column_values
    end

    test "wipes column values in the background when a completed iteration has been removed" do
      memex = create(:memex_project)

      iteration_column = create(
        :iteration_memex_column_with_completed_iterations,
        memex_project: memex
      )
      assert_equal 1, iteration_column.settings_completed_iterations.size

      iteration_id = iteration_column.settings_completed_iterations[0]["id"]

      value = create(:iteration_memex_project_column_value, memex_project_column: iteration_column, value: iteration_id)

      assert_equal [value], iteration_column.memex_project_column_values

      perform_enqueued_jobs(only: RemoveMemexProjectColumnValuesJob) do
        iteration_column.update!(settings: {
          configuration: {
            start_day: 1,
            duration: 14,
            iterations: iteration_column.settings_iterations,
            completed_iterations: []
          }
        })
      end

      assert_empty iteration_column.settings_completed_iterations
      assert_empty iteration_column.reload.memex_project_column_values
    end

    test "rejects invalid column settings" do
      memex = create(:memex_project)

      title_column = memex.memex_project_columns.title.first
      title_column.settings = { bloop: "hello!" }

      refute title_column.save
      assert_includes title_column.errors.full_messages, "Settings contains unsupported keys: bloop"
    end
  end

  context "by_position_and_creation_time scope" do
    test "sorts columns by position ascending and then created_at ascending" do
      column_pos_3 = @memex.memex_project_columns.find_by(position: 3)
      refute_nil column_pos_3
      newer_memex = create(:memex_project)
      column_pos_1 = newer_memex.memex_project_columns.find_by(position: 1)
      refute_nil column_pos_1
      column_pos_2 = newer_memex.memex_project_columns.find_by(position: 2)
      refute_nil column_pos_2
      old_memex = travel_to(1.week.ago) { create(:memex_project) }
      column_pos_2_old = travel_to(1.week.ago) { old_memex.memex_project_columns.find_by(position: 2) }
      refute_nil column_pos_2_old
      ids = [column_pos_3, column_pos_1, column_pos_2, column_pos_2_old].map(&:id)

      result = MemexProjectColumn.where(id: ids).by_position_and_creation_time

      assert_equal [column_pos_1, column_pos_2_old, column_pos_2, column_pos_3], result
    end
  end

  context ".default_columns" do
    test "returns valid default columns" do
      memex = build(:memex_project, omit_default_columns: true)

      MemexProjectColumn.default_columns.each do |col|
        # These columns are not attached to a memex by default, so add one to clear that particular
        # validation error.
        col.memex_project = memex
        assert col.valid?, col.errors.full_messages
      end
    end

    test "still returns valid default columns when the status column is included" do
      memex = build(:memex_project, omit_default_columns: true)
      defaults = MemexProjectColumn.default_columns(excluding: [])

      refute_nil defaults.find { |c| c.name == MemexProjectColumn::STATUS_COLUMN_NAME }

      defaults.each do |col|
        # These columns are not attached to a memex by default, so add one to clear that particular
        # validation error.
        col.memex_project = memex
        assert col.valid?, col.errors.full_messages
      end
    end

    test "includes id, name, and name_html keys in options for default status column" do
      status = MemexProjectColumn.default_column(MemexProjectColumn::STATUS_COLUMN_NAME, excluding: [])

      refute_empty status.settings["options"]
      assert status.settings["options"].all? { |o| o["id"] }, "options must all have 'id' keys"
      assert status.settings["options"].all? { |o| o["name"] }, "options must all have 'name' keys"
      assert status.settings["options"].all? { |o| o["name_html"] }, "options must all have 'name_html' keys"
    end

    test "title column is a default column" do
      column = MemexProjectColumn.default_column(MemexProjectColumn::TITLE_COLUMN_NAME)

      assert_predicate column, :default_column?
    end

    test "assignees column is a default column" do
      column = MemexProjectColumn.default_column(MemexProjectColumn::ASSIGNEES_COLUMN_NAME)

      assert_predicate column, :default_column?
    end

    test "status column is a default column" do
      column = MemexProjectColumn.default_column(MemexProjectColumn::STATUS_COLUMN_NAME)

      assert_predicate column, :default_column?
    end

    test "labels column is a default column" do
      column = MemexProjectColumn.default_column(MemexProjectColumn::LABELS_COLUMN_NAME)

      refute_predicate column, :default_column?
    end

    test "repository column is a default column" do
      column = MemexProjectColumn.default_column(MemexProjectColumn::REPOSITORY_COLUMN_NAME)

      refute_predicate column, :default_column?
    end

    test "milestone column is a default column" do
      column = MemexProjectColumn.default_column(MemexProjectColumn::MILESTONE_COLUMN_NAME)

      refute_predicate column, :default_column?
    end

    test "issue type column is a default column" do
      column = MemexProjectColumn.default_column(MemexProjectColumn::TYPE_COLUMN_NAME)

      refute_predicate column, :default_column?
    end
  end

  context "#normalize_settings" do
    test "converts width setting to an integer" do
      column = build(:memex_project_column)
      assert column.save
      column.settings = { width: "24" }
      assert column.save
      assert_equal column.settings, { "width" => 24 }
    end
  end

  context "#generate_name_slug" do
    test "generates name_slug on create" do
      tests_data = [
        { name: "My Column", name_slug: "my-column" },
        { name: "Gold 🥇", name_slug: "gold-🥇" },
        { name: "Kolumna Piąta 😬👴🏻👨‍👩‍👧‍👧", name_slug: "kolumna-piąta-😬👴🏻👨‍👩‍👧‍👧" }
      ]

      tests_data.each do |data|
        column = create(:memex_project_column, name: data[:name])
        assert_equal column.name_slug, data[:name_slug]
      end
    end

    test "generates name_slug on update" do
      column = create(:memex_project_column)
      column.name = "My Custom Name"
      column.save
      assert_equal column.name_slug, "my-custom-name"
    end
  end

  context "after_commit" do
    test "destroys column values after the column was destroyed" do
      memex = create(:memex_project)
      column = create(:memex_project_column, memex_project: memex, user_defined: true, data_type: :text)
      values = create_list(:memex_project_column_value, 2, memex_project_column: column)

      assert MemexProjectColumn.exists?(column.id)
      refute_empty MemexProjectColumnValue.where(id: values.map(&:id))

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        column.destroy
      end

      refute MemexProjectColumn.exists?(column.id)
      assert_empty MemexProjectColumnValue.where(id: values.map(&:id))
    end

    test "calls for removal of orphaned workflows when options are deleted" do
      project = create(:memex_project)
      status_column = project.status_column
      id_to_remove = status_column.settings_options.last["id"]
      DisableMemexWorkflowsWithInvalidOptionJob.expects(:perform_later).once.with(
        column_id: status_column.id,
        removed_option_ids: [id_to_remove]
        )
      edited_options = status_column.settings_options.select { |option| option["id"] != id_to_remove }
      status_column.settings["options"] = edited_options
      status_column.save
    end

    test "does not call for removal of orphaned workflows when column being updated is not single-select" do
      project = create(:memex_project)
      title_column = project.columns.find(&:title?)
      DisableMemexWorkflowsWithInvalidOptionJob.expects(:perform_later).never
      title_column.position = title_column.position + 1
      title_column.save
    end

    test "does not call for removal of orphaned workflows if settings are not changed" do
      project = create(:memex_project)
      status_column = project.status_column
      DisableMemexWorkflowsWithInvalidOptionJob.expects(:perform_later).never
      status_column.position = status_column.position + 1
      status_column.save
    end

    test "does not call for removal of orphaned workflows if option title is changed" do
      project = create(:memex_project)
      status_column = project.status_column
      DisableMemexWorkflowsWithInvalidOptionJob.expects(:perform_later).never
      options = status_column.settings_options
      options.last["name"] = "testing: different name"
      status_column.save
    end

    test "does not call for removal of orphaned workflows if option is added" do
      project = create(:memex_project)
      status_column = project.status_column
      DisableMemexWorkflowsWithInvalidOptionJob.expects(:perform_later).never
      options = status_column.settings_options
      options.push("id": "foo-id", "name": "foo-option", "name_html": "foo-option")
      status_column.save
    end
  end

  context "hydro instrumentation" do
    test "publishes to hydro on column create" do
      owner = create(:verified_user)
      org = create(:organization)
      org.add_member(owner)
      memex = create(:memex_project, owner: org)
      now = DateTime.new(2021, 05, 06)
      Timecop.freeze(now) do
        GitHub.context.push(actor_id: owner.id)
        column = create(:memex_project_column, memex_project: memex, user_defined: true, data_type: :text, creator: owner)

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(owner),
          memex_project: Hydro::EntitySerializer.memex_project(memex),
          memex_project_column: Hydro::EntitySerializer.memex_project_column(column),
          performed_at: now,
          name: "field_create"
        }, schema: "github.memex.v1.Event")

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(owner),
          memex_project: Hydro::EntitySerializer.memex_project(memex),
          memex_project_column: Hydro::EntitySerializer.memex_project_column(column)
        }, schema: "github.memex.v1.MemexProjectColumnCreate")
      end
    end

    test "does not publish event for system defined column" do
      owner = create(:verified_user)
      org = create(:organization)
      org.add_member(owner)
      create(:memex_project, owner: org)

      refute_hydro_messages(schema: "github.memex.v1.Event")
      refute_hydro_messages(schema: "github.memex.v1.MemexProjectColumnCreate")
    end

    test "publishes to hydro on column update" do
      owner = create(:verified_user)
      member = create(:verified_user)
      org = create(:organization)
      org.add_member(owner)
      org.add_member(member)
      memex = create(:memex_project, owner: org)
      now = DateTime.new(2021, 05, 06)
      Timecop.freeze(now) do
        GitHub.context.push(actor_id: member.id)
        column = create(:memex_project_column, memex_project: memex, user_defined: true, data_type: :text, creator: owner)
        reset_hydro

        column.update!(name: "new name")

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(member),
          memex_project: Hydro::EntitySerializer.memex_project(memex),
          memex_project_column: Hydro::EntitySerializer.memex_project_column(column),
          previous_changes: column.previous_changes.to_json,
        }, schema: "github.memex.v1.MemexProjectColumnUpdate")
      end
    end

    test "publishes to hydro on column destroy" do
      owner = create(:verified_user)
      member = create(:verified_user)
      org = create(:organization)
      org.add_member(owner)
      memex = create(:memex_project, owner: org)
      now = DateTime.new(2021, 05, 06)
      Timecop.freeze(now) do
        GitHub.context.push(actor_id: member.id)
        column = create(:memex_project_column, memex_project: memex, user_defined: true, data_type: :text, creator: owner)
        reset_hydro

        column.destroy!

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(member),
          memex_project: Hydro::EntitySerializer.memex_project(memex),
          memex_project_column: Hydro::EntitySerializer.memex_project_column(column),
        }, schema: "github.memex.v1.MemexProjectColumnDestroy")
      end
    end
  end

  context "audit log instrumentation" do
    context "Creation" do
      test "does not create an audit log for system defined column" do
        events = subscribe "project_field.create"
        memex = create(:memex_project, owner: @org)

        assert_nil events.pop, "no event was expected"
      end

      test "creates the project_field.create log on success" do
        events = subscribe "project_field.create"
        now = DateTime.new(2021, 05, 06)
        memex = create(:memex_project, owner: @org)

        Timecop.freeze(now) do
          memex_field = create(:memex_project_column, memex_project: memex, user_defined: true, data_type: :text, creator: @user)

          expected_payload = {
            project_field_id: memex_field.id,
            project_id: memex.id,
            project_number: memex.number,
            public_project: memex.public?,
            actor: @user.login,
            actor_id: @user.id,
            org_id: @org.id,
            org: @org.login,
            performed_at: now,
          }

          assert event = events.pop, "an event was expected"
          assert_equal "project_field.create", event.name
          assert_equal expected_payload, event.payload
        end
      end
    end

    context "Deletion" do
      test "creates the project_field.delete log on success" do
        events = subscribe "project_field.delete"
        now = DateTime.new(2021, 05, 06)
        memex = create(:memex_project, owner: @org)
        creator = create(:verified_user).tap { |u| @org.add_member(u) }

        Timecop.freeze(now) do
          GitHub.context.push(actor_id: @user.id)
          memex_field = create(:memex_project_column, memex_project: memex, user_defined: true, data_type: :text, creator: creator)
          memex_field.destroy

          expected_payload = {
            project_field_id: memex_field.id,
            project_id: memex.id,
            project_number: memex.number,
            public_project: memex.public?,
            actor: @user.login,
            actor_id: @user.id,
            org_id: @org.id,
            org: @org.login,
            performed_at: now,
          }

          assert event = events.pop, "a delete event was expected"
          assert_equal "project_field.delete", event.name
          assert_equal expected_payload, event.payload
        end
      end
    end
  end

  context "#synthetic_id" do
    test "returns system column name" do
      memex = create(:memex_project)

      MemexProjectColumn.default_columns.each do |column|
        assert_predicate column, :system_defined?
        assert_equal column.name, column.synthetic_id
      end

      memex.reload.columns.each do |column|
        # even after being saved, `name` is still used as synthetic_id
        assert_equal column.name, column.synthetic_id
      end
    end

    test "returns user_defined column id once persisted" do
      memex = create(:memex_project)
      column = build(:memex_project_column, user_defined: true, memex_project: memex)
      assert_predicate column, :user_defined?
      refute_predicate column, :persisted?
      assert_nil column.synthetic_id # `nil` id since the record isn't saved

      column.save!
      column.reload
      assert_equal column.id, column.synthetic_id
    end

    test "when flag is enabled makes the casing of Linked pull requests as such" do
      linked_pr_column = @memex.columns.find(&:linked_pull_requests?)
      assert_equal "Linked pull requests", linked_pr_column.synthetic_id
    end
  end

  context "#to_hash" do
    test "when flag is enabled, fixes casing of linked pull requests" do
      linked_pr_column = @memex.columns.find(&:linked_pull_requests?)
      hash = linked_pr_column.to_hash
      assert_equal "Linked pull requests", hash[:name]
    end

    test "validates a complete representation of a single select column" do
      column = create(
        :memex_project_column,
        data_type: :single_select,
        settings: {
          "width" => 600,
          "options" => [
            { name: "foo", color: "PURPLE", description: "" },
            { name: "bar", color: "ORANGE", description: "" },
            { name: "baz", color: "BLUE", description: "" },
          ]
        }
      )

      expected_base_hash = {
        dataType: "singleSelect",
        databaseId: column.id,
        id: column.synthetic_id,
        name: column.name,
        nameSlug: column.name_slug,
        position: column.position,
        userDefined: column.user_defined,
        visible: column.visible,
        partialFailures: nil
      }

      assert_equal expected_base_hash, column.to_hash.except(:settings)

      serialized_settings = column.to_hash[:settings]

      assert_equal(600, serialized_settings["width"])
      options = serialized_settings["options"]
      assert_equal %w[foo bar baz], options.map { |o| o["name"] }
      assert_equal %w[PURPLE ORANGE BLUE], options.map { |o| o["color"] }
      assert options.all? { |o| o["id"].present? }
      assert options.all? { |o| o["nameHtml"].present? }
      assert options.all? { |o| !o["descriptionHtml"].nil? } # empty string is fine here

    end

    test "defaultColumn included for new records" do
      column = MemexProjectColumn.default_column(MemexProjectColumn::TITLE_COLUMN_NAME)

      assert_equal true, column.to_hash[:defaultColumn]
    end

    test "validates a complete representation of an iteration column" do
      title = "Iteration 2 <script>alert('foo')</script>"
      settings = {
        "configuration" => {
          "start_day": 1,
          "duration": 14,
          "ahead_count": 4,
          "iterations": [
            {
              "id": "bbbbbbbb",
              "title": title,
              "start_date": Date.today.to_s,
              "duration": 14
            }
          ]
        }
      }

      column = create(
        :iteration_memex_column,
        settings: settings
      )

      expected_base_hash = {
        dataType: "iteration",
        databaseId: column.id,
        id: column.synthetic_id,
        name: column.name,
        nameSlug: column.name_slug,
        position: column.position,
        userDefined: column.user_defined,
        visible: column.visible,
        partialFailures: nil
      }

      assert_equal expected_base_hash, column.to_hash.except(:settings)

      serialized_settings = column.to_hash[:settings]
      iterations = serialized_settings.dig("configuration", "iterations")

      assert iterations.first["id"].present?
      assert_equal title, iterations.first["title"]
      assert_equal "Iteration 2 ", iterations.first["titleHtml"]
    end

    test "validates a representation of an interation column with a completed iteration" do
      title = "Iteration 2 <script>alert('foo')</script>"
      settings = {
        "configuration" => {
          "start_day": 1,
          "duration": 14,
          "ahead_count": 4,
          "completed_iterations": [
            {
              "id": "bbbbbbbb",
              "title": title,
              "start_date": "#{Date.today - 3.weeks}",
              "duration": 14
            }
          ]
        }
      }

      column = create(
        :iteration_memex_column,
        settings: settings
      )

      expected_base_hash = {
        dataType: "iteration",
        databaseId: column.id,
        id: column.synthetic_id,
        name: column.name,
        nameSlug: column.name_slug,
        position: column.position,
        userDefined: column.user_defined,
        visible: column.visible,
        partialFailures: nil
      }

      assert_equal expected_base_hash, column.to_hash.except(:settings)

      serialized_settings = column.to_hash[:settings]
      completed_iterations = serialized_settings.dig("configuration", "completedIterations")

      assert completed_iterations.first["id"].present?
      assert_equal title, completed_iterations.first["title"]
      assert_equal "Iteration 2 ", completed_iterations.first["titleHtml"]
    end

    test "adds a default color & description if none is present" do
      column = create(
        :memex_project_column,
        data_type: :single_select,
        settings: {
          "width" => 600,
          "options" => [
            { name: "foo", color: "RED", description: "foo description" }
          ]
        }
      )

      # Creating a new option without any color will default to GRAY upon creation, but we also want to default to GRAY
      # when reading columns that haven't been updated since colors were added
      column.settings["options"][0].delete("color")
      column.settings["options"][0].delete("description")

      assert_equal column.to_hash[:settings]["options"][0]["color"], "GRAY"
      assert_equal column.to_hash[:settings]["options"][0]["description"], ""
    end

    test "returns partial failure if prefilled association has partial failures" do
      column = @memex.columns.find(&:tracked_by?)

      expected_base_hash = {
        dataType: "trackedBy",
        id: column.synthetic_id,
        databaseId: column.id,
        name: column.name,
        nameSlug: column.name_slug,
        position: column.position,
        userDefined: column.user_defined,
        visible: column.visible,
        partialFailures: { memexProjectColumn: "Tracked by", message: "We encountered a problem retrieving the \"Tracked by\" data. Please try again later." }
      }

      prefilled_associations = MemexProjectItem::PrefilledAssociations.new(
        partial_failures: [{
          memex_project_column: MemexProjectColumn::TRACKED_BY_COLUMN_NAME,
          message: "We encountered a problem retrieving the \"Tracked by\" data. Please try again later."
        }]
      )
      assert_equal expected_base_hash, column.to_hash(prefilled_associations: prefilled_associations).except(:settings)
    end
  end

  context "#special_type_association" do
    test "raises NotImplementedError for a generic column type" do
      memex_with_status = create(:memex_project)

      status_column = memex_with_status.status_column
      assert_predicate status_column, :system_defined?
      assert_predicate status_column, :generic_type?

      assert_raises(NotImplementedError) { status_column.special_type_association }
    end

    test "returns the correct association for assignees" do
      assignees_column = @memex.find_column_by_name_or_id(MemexProjectColumn::ASSIGNEES_COLUMN_NAME)
      assert_equal :assignees, assignees_column.special_type_association
    end

    test "returns the correct association for labels" do
      labels_column = @memex.find_column_by_name_or_id(MemexProjectColumn::LABELS_COLUMN_NAME)
      assert_equal :labels, labels_column.special_type_association
    end

    test "returns the correct association for milestone" do
      milestone_column = @memex.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)
      assert_equal :milestone, milestone_column.special_type_association
    end

    test "returns the correct association for repository" do
      repository_column = @memex.find_column_by_name_or_id(MemexProjectColumn::REPOSITORY_COLUMN_NAME)
      assert_equal :repository, repository_column.special_type_association
    end

    test "returns the correct association for issue_type" do
      issue_type_column = @memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
      assert_equal :issue_type, issue_type_column.special_type_association
    end

    test "returns the correct association for title" do
      title_column = @memex.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)

      # Titles are special because they are stored directly on the content object (i.e. the Issue
      # or DraftIssue), so we never need to load an association for them.
      assert_nil title_column.special_type_association
    end
  end

  context "#settings_option_ids" do
    test "name matching is case-insensitive" do
      column = create(
        :memex_project_column,
        data_type: :single_select,
        settings: {
          "width" => 600,
          "options" => [
            { name: "Option 99", color: "PURPLE", description: "" },
          ]
        }
      )

      names        = ["OpTiOn 99"]
      actual_ids   = column.settings_option_ids(names)
      expected_ids = column.settings_option_ids

      assert_equal 1, expected_ids.length
      assert_same_elements expected_ids, actual_ids
    end
  end

  context "#settings_options_names_html" do
    test "return an empty array for text columns" do
      memex = create(:memex_project)
      column = create(:memex_project_column, memex_project: memex, user_defined: true, data_type: :text)

      assert_equal [], column.settings_options_names_html
    end

    test "marks name_html as safe" do
      column = create(
        :memex_project_column,
        data_type: :single_select,
        settings: {
          "width" => 600,
          "options" => [
            { name: ":rocket: test" , color: "PURPLE", description: "" },
          ]
        }
      )

      assert_equal 1, column.settings_options_names_html.size
      assert column.settings_options_names_html.first["name_html"].html_safe?
    end
  end

  context "#settings_iteration_ids" do
    test "returns array of iterations ids" do
      col = build(:iteration_memex_column)
      assert_equal col.settings.dig("configuration", "iterations").map { |i| i["id"] },
        col.settings_iteration_ids
    end

    test "returns empty array when no iterations" do
      col = build(:empty_iteration_memex_column)
      assert_equal [], col.settings_iteration_ids
    end
  end

  context "#settings_iteration_id" do
    test "returns a specific iteration" do
      col = build(:iteration_memex_column)
      id = col.settings_iterations.first["id"]
      assert_equal col.settings_iterations.first, col.settings_iteration(id)
    end

    test "returns nil when no matching iteration" do
      col = build(:iteration_memex_column)
      assert_nil col.settings_iteration("lolno")
    end

    test "returns empty nil when no iterations" do
      col = build(:empty_iteration_memex_column)
      assert_nil col.settings_iteration("lolno")
    end
  end

  context "#settings_iterations" do
    test "returns array of iterations" do
      col = build(:iteration_memex_column)
      assert_equal col.settings.dig("configuration", "iterations"),
        col.settings_iterations
    end

    test "returns empty array when no iterations" do
      col = build(:empty_iteration_memex_column)
      assert_equal [], col.settings_iterations
    end
  end

  context "#settings_all_iterations_ids" do
    test "title matching is case-insensitive" do
      iteration_column = build(:iteration_memex_column)
      titles           = ["ItErAtIoN 1", "ITERATION 2"]

      actual_ids   = iteration_column.settings_all_iterations_ids(titles)
      expected_ids = iteration_column.settings_all_iterations_ids

      assert_equal 2, expected_ids.length
      assert_same_elements expected_ids, actual_ids
    end
  end

  context "#settings_iterations_objects_all" do
    test "returns array of active and completed iterations objects" do
      col = build(:iteration_memex_column_with_completed)
      active_starts = col.settings_iterations.map { |i| i["start_date"] }
      completed_starts = col.settings_completed_iterations.map { |i| i["start_date"] }
      starts = active_starts + completed_starts
      assert_same_elements starts,
        col.settings_iterations_objects_all.map(&:start_date)
    end

    test "returns empty array when no iterations" do
      col = build(:empty_iteration_memex_column)
      assert_equal [], col.settings_iterations_objects_all
    end
  end

  context "#settings_completed_iterations" do
    test "returns array of completed iterations" do
      col = build(:iteration_memex_column_with_completed)
      assert_equal col.settings.dig("configuration", "completed_iterations"),
        col.settings_completed_iterations
    end

    test "returns empty array when no iterations" do
      col = build(:empty_iteration_memex_column)
      assert_equal [], col.settings_completed_iterations
    end
  end

  context "#settings_all_iterations" do
    test "returns array of active and completed iterations" do
      col = build(:iteration_memex_column_with_completed)

      # active iterations are returned in chronological order
      active_iterations = col.settings["configuration"]["iterations"]

      # completed iterations are returned in reverse chronological order
      completed_iterations = col.settings["configuration"]["completed_iterations"]

      # reverse the completed iterations so all iterations are returned in chronological order
      assert_equal completed_iterations.reverse + active_iterations, col.settings_all_iterations
    end

    test "returns empty array when no active or completed iterations" do
      col = build(:empty_iteration_memex_column)
      assert_empty col.settings_all_iterations
    end
  end

  context "saved views" do
    test "does not add new column to views on creation" do
      view = @memex.default_view
      view2 = create(:memex_project_view, memex_project: @memex)

      new_text_column = create(:memex_project_column, memex_project: @memex, user_defined: true, data_type: :text)

      refute_includes view.reload.visible_fields, new_text_column.id
      refute_includes view2.reload.visible_fields, new_text_column.id
    end
  end

  context "visibility double-write" do
    test "removing the column removes the column from related views" do
      column = create(:memex_project_column, memex_project: @memex, user_defined: true, name: "Stage")
      view = column.memex_project.default_view
      view2 = create(:memex_project_view, memex_project: @memex)
      view2.make_column_visible!(column)

      assert_includes view2.visible_fields, column.id

      column.reload.destroy
      refute_includes view2.reload.visible_fields, column.id
    end
  end

  context "sync_iteration_column_completed_iterations" do
    test "it does not do anything if `iterations` is empty" do
      iteration_column = create(:empty_iteration_memex_column, memex_project: @memex)

      iteration_column.sync_iteration_column_completed_iterations

      assert_empty iteration_column.settings_iterations
      assert_empty iteration_column.settings_completed_iterations
    end

    test "when there are `iterations` that are in the past, it moves them" \
      "from `iterations` to `completed_iterations`" do
      today_date = Date.today
      today = today_date.to_s

      two_weeks_ago = today_date - 2.weeks
      four_weeks_ago = today_date - 4.weeks
      two_weeks_later = today_date + 2.weeks

      new_completed_iteration = {
        "id": "aaaaaaaa",
        "title": "Iteration 1",
        "start_date": two_weeks_ago.to_s,
        "duration": 14
      }

      next_planned_iteration = {
        "id": "bbbbbbbb",
        "title": "Iteration 2",
        "start_date": today,
        "duration": 14
      }

      last_planned_iteration = {
        "id": "bbbbbbbb",
        "title": "Iteration 3",
        "start_date": two_weeks_later.to_s,
        "duration": 14
      }

      iteration_column = build(
        :iteration_memex_column,
        settings: {
          "configuration" => {
            "start_day": 1,
            "duration": 14,
            "ahead_count": 4,
            "iterations": [
              new_completed_iteration,
              next_planned_iteration,
              last_planned_iteration
            ],
            "completed_iterations": [
              {
                "id": "dddddddd",
                "title": "Iteration 0",
                "start_date": four_weeks_ago.to_s,
                "duration": 14
              }
            ]
          }
        }
      )
      iteration_column.save!

      iteration_column.sync_iteration_column_completed_iterations

      iteration_column.reload
      assert_equal 2, iteration_column.settings_completed_iterations.count
      assert_equal 2, iteration_column.settings_iterations.count

      # Verify that completed iterations are sorted in descending order of start_date
      iteration_column.settings_completed_iterations.each_cons(2).all? { |left, right| left["start_date"] > right["start_date"] }
    end

    test "when there are `iterations` that are in the past, it moves them" \
    "from `iterations` to `completed_iterations` even if `completed_iterations` is nil" do
      memex = create(:memex_project)

      today = "2021-01-20"
      today_date = Date.parse(today)

      two_weeks_ago = today_date.prev_day(14).strftime("%Y-%m-%d")
      four_weeks_ago = today_date.prev_day(28).strftime("%Y-%m-%d")
      two_weeks_later = today_date.next_day(14).strftime("%Y-%m-%d")

      new_completed_iteration = {
        "id": "aaaaaaaa",
        "title": "Iteration 1",
        "start_date": two_weeks_ago,
        "duration": 14
      }

      next_planned_iteration = {
        "id": "bbbbbbbb",
        "title": "Iteration 2",
        "start_date": today,
        "duration": 14
      }

      last_planned_iteration = {
        "id": "bbbbbbbb",
        "title": "Iteration 3",
        "start_date": two_weeks_later,
        "duration": 14
      }

      iteration_column = build(
        :iteration_memex_column,
        memex_project: memex,
        settings: {
          "configuration" => {
            "start_day": 1,
            "duration": 14,
            "ahead_count": 4,
            "iterations": [
              new_completed_iteration,
              next_planned_iteration,
              last_planned_iteration
            ],
            "completed_iterations": nil
          }
        }
      )
      iteration_column.save!

      Timecop.freeze(today_date) do
        iteration_column.sync_iteration_column_completed_iterations
      end

      iteration_column.reload
      assert_equal 1, iteration_column.settings_completed_iterations.count
      assert_equal 2, iteration_column.settings_iterations.count
    end

    test "when none of the `iterations` are in the past, it does not change" \
    "`iterations` nor `completed_iterations`" do
      memex = create(:memex_project)

      today = "2021-01-20"
      today_date = Date.parse(today)

      one_day_later = today_date.next_day(1).strftime("%Y-%m-%d")
      four_weeks_later = today_date.next_day(28).strftime("%Y-%m-%d")
      four_weeks_ago = today_date.prev_day(28).strftime("%Y-%m-%d")

      iteration1 = {
        "id": "aaaaaaaa",
        "title": "one day later",
        "start_date": one_day_later,
        "duration": 14
      }

      iteration2 = {
        "id": "bbbbbbbb",
        "title": "four weeks later",
        "start_date": four_weeks_later,
        "duration": 14
      }

      iteration_column = build(
        :iteration_memex_column,
        memex_project: memex,
        settings: {
          "configuration" => {
            "start_day": 1,
            "duration": 14,
            "ahead_count": 4,
            "iterations": [
              iteration1,
              iteration2
            ],
            "completed_iterations": [
              {
                "id": "dddddddd",
                "title": "four weeks ago",
                "start_date": four_weeks_ago,
                "duration": 14
              }
            ]
          }
        }
      )
      iteration_column.save!

      Timecop.freeze(today_date) do
        iteration_column.sync_iteration_column_completed_iterations
      end

      # Nothing changes, the counts of both iterations and completed_iterations remain
      # the same
      iteration_column.reload
      assert_equal 2, iteration_column.settings_iterations.count
      assert_equal 1, iteration_column.settings_completed_iterations.count
    end
  end

  context "#json_value_id" do
    test "returns nil for a column with type other than milestone" do
      # At time of writing milestones are the only columns with a denormalized
      # value that contain an embedded ID that we want to index.

      milestone = create(:milestone)
      issue = create(:issue, repository: milestone.repository, milestone: milestone)
      item = create(:memex_project_item, content: issue)
      title_column = item.memex_project.columns.find(&:title?)

      assert_nil title_column.json_value_id(item.denormalized_milestone_value)
    end

    test "returns nil for an item type that doesn't support milestones" do
      item = create(:memex_project_item, content: create(:draft_issue))
      milestone_column = item.memex_project.columns.find(&:milestone?)

      assert_nil milestone_column.json_value_id(item.denormalized_milestone_value)
    end

    test "returns nil when invoked on a milestone column with an item that is not assigned to a milestone" do
      issue = create(:issue)
      assert_nil issue.milestone
      item = create(:memex_project_item, content: issue)
      milestone_column = item.memex_project.columns.find(&:milestone?)

      assert_nil milestone_column.json_value_id(item.denormalized_milestone_value)
    end

    test "returns milestone ID when invoked on the milestone column with an item that is assigned to a milestone" do
      milestone = create(:milestone)
      issue = create(:issue, repository: milestone.repository, milestone: milestone)
      item = create(:memex_project_item, content: issue)
      milestone_column = item.memex_project.columns.find(&:milestone?)

      assert_equal milestone.id, milestone_column.json_value_id(item.denormalized_milestone_value)
    end
  end

  context "#platform_type_name" do
    test "supports single_select platform_type_name" do
      column = create(
        :memex_project_column,
        data_type: :single_select,
        settings: {
          "width" => 600,
          "options" => [
            { name: ":rocket: test" , color: "PURPLE", description: "" },
          ]
        }
      )

      assert_equal "ProjectV2SingleSelectField", column.platform_type_name
    end

    test "supports iteration platform_type_name" do
      column = create(
        :iteration_memex_column,
      )

      assert_equal "ProjectV2IterationField", column.platform_type_name
    end

    test "supports generic platform_type_name" do
      column = date_column = create(
        :memex_project_column,
      )

      assert_equal "ProjectV2Field", column.platform_type_name
    end
  end

  context "#backfill_system_defined_type_column" do
    context "for organization-owned project" do
      test "backfills system-defined Type column when user-defined Type column is renamed" do
        memex_project = create(:memex_project, owner: @org, creator: @user)
        # Org owned projects have it by default, have to go through some hoops to create user-defined Type column
        memex_project.memex_project_columns.issue_type.destroy_all
        MemexProject::Copier.with_copying do
          @user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)
        end

        assert_predicate memex_project, :org_owned?, "project should be org-owned"
        assert_changes -> { memex_project.memex_project_columns.issue_type.count }, from: 0, to: 1 do
          success = memex_project.update_column(
            @user_defined_issue_type_column,
            name: "Another Type",
          )

          assert success, "update_column should succeed"
        end
      end

      test "backfills system-defined Type column when user-defined Type column is destroyed" do
        memex_project = create(:memex_project, owner: @org, creator: @user)
        # Org owned projects have it by default, have to go through some hoops to create user-defined Type column
        memex_project.memex_project_columns.issue_type.destroy_all
        MemexProject::Copier.with_copying do
          @user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)
        end

        assert_predicate memex_project, :org_owned?, "project should be org-owned"
        assert_changes -> { memex_project.memex_project_columns.issue_type.count }, from: 0, to: 1 do
          @user_defined_issue_type_column.destroy!
        end
      end

      test "backfills case-insensitive user-defined Type column being renamed" do
        memex_project = create(:memex_project, owner: @org, creator: @user)
        # Org owned projects have it by default, have to go through some hoops to create user-defined Type column
        memex_project.memex_project_columns.issue_type.destroy_all
        MemexProject::Copier.with_copying do
          @user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: "type", user_defined: true)
        end

        assert_predicate memex_project, :org_owned?, "project should be org-owned"
        refute_equal @user_defined_issue_type_column.name, MemexProjectColumn::TYPE_COLUMN_NAME, "user-defined column should be a different case than system-defined column"
        assert_changes -> { memex_project.memex_project_columns.issue_type.count }, from: 0, to: 1 do
          success = memex_project.update_column(
            @user_defined_issue_type_column,
            name: "Another Type",
          )

          assert success, "update_column should succeed"
        end
      end

      test "backfills case-insensitive user-defined Type column being destroyed" do
        memex_project = create(:memex_project, owner: @org, creator: @user)
        # Org owned projects have it by default, have to go through some hoops to create user-defined Type column
        memex_project.memex_project_columns.issue_type.destroy_all
        MemexProject::Copier.with_copying do
          @user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: "type", user_defined: true)
        end

        assert_predicate memex_project, :org_owned?, "project should be org-owned"
        refute_equal @user_defined_issue_type_column.name, MemexProjectColumn::TYPE_COLUMN_NAME, "user-defined column should be a different case than system-defined column"
        assert_changes -> { memex_project.memex_project_columns.issue_type.count }, from: 0, to: 1 do
          @user_defined_issue_type_column.destroy!
        end
      end

      test "system-defined Type column backfilled at end of column list" do
        memex_project = create(:memex_project, owner: @org, creator: @user)
        # Org owned projects have it by default, have to go through some hoops to create user-defined Type column
        memex_project.memex_project_columns.issue_type.destroy_all
        MemexProject::Copier.with_copying do
          @user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)
        end
        expected_position = memex_project.memex_project_columns.maximum(:position) + 1

        memex_project.update_column(
          @user_defined_issue_type_column,
          name: "Another Type",
        )

        system_defined_issue_type_column = memex_project.memex_project_columns.issue_type.first!
        assert_equal expected_position, system_defined_issue_type_column.position
        assert_predicate memex_project, :org_owned?, "project should be org-owned"
      end

      test "user-defined Type column being destroyed is rolled back if issue with system-defined Type column being introduced" do
        memex_project = create(:memex_project, owner: @org, creator: @user)
        # Org owned projects have it by default, have to go through some hoops to create user-defined Type column
        memex_project.memex_project_columns.issue_type.destroy_all
        MemexProject::Copier.with_copying do
          @user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)
        end

        # Since users do not control the input to creating the system-defined column, we need to mock an invalid record
        invalid_column = memex_project.memex_project_columns.new
        @user_defined_issue_type_column.memex_project.stubs(:backfill_issue_type_column).returns(invalid_column)

        assert_predicate memex_project, :org_owned?, "project should be org-owned"
        assert_no_difference -> { memex_project.memex_project_columns.issue_type.count } do
          success = @user_defined_issue_type_column.destroy

          refute success, "destroying column should not have succeeded"
          assert @user_defined_issue_type_column.errors.of_kind?(:base, :issue_type_column_backfill_failed), "Expected MemexProjectColumn to have issue_type_column_backfill_failed error"
        end
      end

      test "user-defined Type column rename is rolled back if issue with system-defined Type column being introduced" do
        memex_project = create(:memex_project, owner: @org, creator: @user)
        # Org owned projects have it by default, have to go through some hoops to create user-defined Type column
        memex_project.memex_project_columns.issue_type.destroy_all
        MemexProject::Copier.with_copying do
          @user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)
        end

        # Since users do not control the input to creating the system-defined column, we need to mock an invalid record
        invalid_column = memex_project.memex_project_columns.new
        @user_defined_issue_type_column.memex_project.stubs(:backfill_issue_type_column).returns(invalid_column)

        assert_predicate memex_project, :org_owned?, "project should be org-owned"
        assert_no_difference -> { memex_project.memex_project_columns.issue_type.count } do
          success = memex_project.update_column(
            @user_defined_issue_type_column,
            name: "Another Type",
          )

          refute success, "update_column should not have succeeded"
          assert @user_defined_issue_type_column.errors.of_kind?(:base, :issue_type_column_backfill_failed), "Expected MemexProjectColumn to have issue_type_column_backfill_failed error"
        end
      end

      test "user-defined Type column rename rollback reports a IssueTypeColumnCreationError to Failbot", skip_enterprise: true do
        memex_project = create(:memex_project, owner: @org, creator: @user)
        # Org owned projects have it by default, have to go through some hoops to create user-defined Type column
        memex_project.memex_project_columns.issue_type.destroy_all
        MemexProject::Copier.with_copying do
          @user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)
        end

        # Since users do not control the input to creating the system-defined column, we need to mock an invalid record
        invalid_column = memex_project.memex_project_columns.new
        @user_defined_issue_type_column.memex_project.stubs(:backfill_issue_type_column).returns(invalid_column)

        assert_predicate memex_project, :org_owned?, "project should be org-owned"
        assert_difference -> { Failbot.reports.length } do
          success = memex_project.update_column(
            @user_defined_issue_type_column,
            name: "Another Type",
          )

          refute success, "update_column should not have succeeded"
          assert report = Failbot.reports.last
          assert_equal "github-user", report["app"], "expected user bucket"
          assert_equal "MemexProjectColumn::IssueTypeColumnBackfillError", report.dig("exception_detail", 0, "type")
          assert_equal memex_project.id, report["sensitive_context"]["memex_project_id"]
        end
      end

      test "user-defined Type column being destroyed rollback reports a IssueTypeColumnCreationError to Failbot", skip_enterprise: true do
        memex_project = create(:memex_project, owner: @org, creator: @user)
        # Org owned projects have it by default, have to go through some hoops to create user-defined Type column
        memex_project.memex_project_columns.issue_type.destroy_all
        MemexProject::Copier.with_copying do
          @user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)
        end

        # Since users do not control the input to creating the system-defined column, we need to mock an invalid record
        invalid_column = memex_project.memex_project_columns.new
        @user_defined_issue_type_column.memex_project.stubs(:backfill_issue_type_column).returns(invalid_column)

        assert_predicate memex_project, :org_owned?, "project should be org-owned"
        assert_difference -> { Failbot.reports.length } do
          success = @user_defined_issue_type_column.destroy

          refute success, "destroying column should not have succeeded"
          assert report = Failbot.reports.last
          assert_equal "github-user", report["app"], "expected user bucket"
          assert_equal "MemexProjectColumn::IssueTypeColumnBackfillError", report.dig("exception_detail", 0, "type")
          assert_equal memex_project.id, report["sensitive_context"]["memex_project_id"]
        end
      end

      test "does not backfill system-defined Type column when user-defined Type column is modified" do
        memex_project = create(:memex_project, owner: @org, creator: @user)
        # Org owned projects have it by default, have to go through some hoops to create user-defined Type column
        memex_project.memex_project_columns.issue_type.destroy_all
        MemexProject::Copier.with_copying do
          @user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)
        end

        assert_predicate memex_project, :org_owned?, "project should be org-owned"
        assert_no_changes -> { memex_project.memex_project_columns.issue_type.count }, from: 0 do
          success = memex_project.update_column(
            @user_defined_issue_type_column,
            visible: !@user_defined_issue_type_column.visible?,
          )

          assert success, "update_column should succeed"
        end
      end

      test "does not backfill system-defined Type column unless user-defined column name was Type" do
        memex_project = create(:memex_project, owner: @org, creator: @user)
        # Org owned projects have it by default, have to go through some hoops to create user-defined Type column
        memex_project.memex_project_columns.issue_type.destroy_all
        MemexProject::Copier.with_copying do
          @user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)
        end
        memex_project_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: "Not Type", user_defined: true)

        assert_no_changes -> { memex_project.memex_project_columns.issue_type.count }, from: 0 do
          success = memex_project.update_column(
            memex_project_column,
            name: "Another name",
          )

          assert success, "update_column should succeed"
        end
      end

      test "queues project reindex when system-defined Type column is backfilled" do
        memex_project = create(:memex_project, owner: @org, creator: @user)
        # Org owned projects have it by default, have to go through some hoops to create user-defined Type column
        memex_project.memex_project_columns.issue_type.destroy_all
        MemexProject::Copier.with_copying do
          @user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)
        end

        # Stub out this method so that we continue to enqueue the job even if `queue_reindex_items` is called multiple
        # times in quick succession. Without this stub, this test will fail in the gauntlet run.
        # Because the test here is mainly concerned with the job being enqueued when `queue_reindex_items` is called, not
        # with the rate limiting behavior, we are good to stub this out.
        RedisRateLimiter::Result.any_instance.stubs(:at_limit?).returns(false)

        assert_difference -> { memex_project.memex_project_columns.issue_type.count } do
          assert_enqueued_with(job: ResyncMemexProjectItemsIndexJob) do
            success = memex_project.update_column(
              @user_defined_issue_type_column,
              name: "Another Type",
            )

            assert success, "update_column should succeed"
          end
        end
      end

      test "does not queue project reindex when could not create system-defined Type column" do
        memex_project = create(:memex_project, owner: @org, creator: @user)
        # Org owned projects have it by default, have to go through some hoops to create user-defined Type column
        memex_project.memex_project_columns.issue_type.destroy_all
        MemexProject::Copier.with_copying do
          @user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)
        end

        # Since users do not control the input to creating the system-defined column, we need to mock an invalid record
        invalid_column = memex_project.memex_project_columns.new
        @user_defined_issue_type_column.memex_project.stubs(:backfill_issue_type_column).returns(invalid_column)

        # Stub out this method so that we continue to enqueue the job even if `queue_reindex_items` is called multiple
        # times in quick succession. Without this stub, this test will fail in the gauntlet run.
        # Because the test here is mainly concerned with the job being enqueued when `queue_reindex_items` is called, not
        # with the rate limiting behavior, we are good to stub this out.
        RedisRateLimiter::Result.any_instance.stubs(:at_limit?).returns(false)

        assert_no_difference -> { memex_project.memex_project_columns.count } do
          assert_no_enqueued_jobs only: ResyncMemexProjectItemsIndexJob do
            success = memex_project.update_column(
              @user_defined_issue_type_column,
              name: "Another Type",
            )

            refute success, "update_column should not have succeeded"
          end
        end
      end
    end

    context "for user-owned project" do
      test "does not backfill system-defined Type column when user-defined Type column is renamed" do
        memex_project = create(:memex_project, owner: @user, creator: @user)
        user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)

        assert_predicate memex_project, :user_owned?, "project should be user-owned"
        assert_no_changes -> { memex_project.memex_project_columns.issue_type.count }, from: 0 do
          success = memex_project.update_column(
            user_defined_issue_type_column,
            name: "Another Type",
          )

          assert success, "update_column should succeed"
        end
      end

      test "does not backfill system-defined Type column when user-defined Type column is destroyed" do
        memex_project = create(:memex_project, owner: @user, creator: @user)
        user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)

        assert_predicate memex_project, :user_owned?, "project should be user-owned"
        assert_no_changes -> { memex_project.memex_project_columns.issue_type.count }, from: 0 do
          user_defined_issue_type_column.destroy!
        end
      end

      test "does not backfill case-insensitive user-defined Type column being renamed" do
        memex_project = create(:memex_project, owner: @user, creator: @user)
        user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: "type", user_defined: true)

        refute_equal user_defined_issue_type_column.name, MemexProjectColumn::TYPE_COLUMN_NAME, "user-defined column should be a different case than system-defined column"
        assert_predicate memex_project, :user_owned?, "project should be user-owned"
        assert_no_changes -> { memex_project.memex_project_columns.issue_type.count }, from: 0 do
          success = memex_project.update_column(
            user_defined_issue_type_column,
            name: "Another Type",
          )

          assert success, "update_column should succeed"
        end
      end

      test "does not backfill case-insensitive user-defined Type column being destroyed" do
        memex_project = create(:memex_project, owner: @user, creator: @user)
        user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: "type", user_defined: true)

        refute_equal user_defined_issue_type_column.name, MemexProjectColumn::TYPE_COLUMN_NAME, "user-defined column should be a different case than system-defined column"
        assert_predicate memex_project, :user_owned?, "project should be user-owned"
        assert_no_changes -> { memex_project.memex_project_columns.issue_type.count }, from: 0 do
          user_defined_issue_type_column.destroy!
        end
      end

      test "does not backfill system-defined Type column when user-defined Type column is modified" do
        memex_project = create(:memex_project, owner: @user, creator: @user)
        user_defined_issue_type_column = create(:memex_project_column, creator: @user, memex_project: memex_project, name: MemexProjectColumn::TYPE_COLUMN_NAME, user_defined: true)

        assert_predicate memex_project, :user_owned?, "project should be user-owned"
        assert_no_changes -> { memex_project.memex_project_columns.issue_type.count }, from: 0 do
          success = memex_project.update_column(
            user_defined_issue_type_column,
            visible: !user_defined_issue_type_column.visible?,
          )

          assert success, "update_column should succeed"
        end
      end
    end
  end
end
