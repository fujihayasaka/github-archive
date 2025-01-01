# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnValueTest < GitHub::TestCase
  include HydroTestHelpers
  include StringFromBinaryTestHelper

  fixtures do
    @organization = create(:organization)
    @memex = create(:memex_project, owner: @organization)
    @title_column = @memex.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)
    @number_column = create(:memex_project_column, data_type: :number, user_defined: true, memex_project: @memex)
    @date_column = create(:memex_project_column, data_type: :date, user_defined: true, memex_project: @memex)

    @admin = create(:verified_user)
    @member = create(:verified_user)
    @repo = create(:private_repository, owner: @organization)
    @organization.add_member(@admin)
    @organization.add_member(@member)
    @issue = create(:issue, repository: @repo)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @admin)

    @issue_item = create(:memex_project_item, memex_project: @memex, content: @issue)
    @pull_item = create(:memex_project_item, memex_project: @memex, content: @pull)
  end

  setup do
    GitHub.context.push(actor: @admin)
  end

  def serialize_user_generated_content_message(payload)
    {
      **payload,
      actor: Hydro::EntitySerializer.user(payload[:actor]),
      request_context: Hydro::EntitySerializer.request_context(payload[:request_context]),
      content: Hydro::EntitySerializer.specimen_data(payload[:content])
    }
  end

  context "validations" do
    test "requires column" do
      value = build(:memex_project_column_value, memex_project_column: nil)

      refute value.save
      assert_includes value.errors.full_messages, "Memex project column can't be blank"
    end

    test "requires item" do
      value = build(:memex_project_column_value, memex_project_item: nil)

      refute value.save
      assert_includes value.errors.full_messages, "Memex project item can't be blank"
    end

    test "requires a creator" do
      value = build(:memex_project_column_value, creator: nil)

      refute value.save
      assert_includes value.errors.full_messages, "Creator can't be blank"
    end

    test "allows nil creator on update" do
      # initial creation
      creator = create(:user)
      column = create(:memex_project_column, data_type: :text)
      value = build(:memex_project_column_value,
        creator: creator,
        column: column,
        value: "foo",
        memex_project_item: create(:memex_project_item, memex_project: @memex)
      )
      assert value.save

      # delete creator and then update
      creator.destroy
      value.reload
      value.value = "bar"
      assert value.save
      assert value.validate!
    end

    test "requires value" do
      value = build(:memex_project_column_value, value: nil)

      refute value.save
      assert_includes value.errors.full_messages, "Value can't be blank"
    end

    test "requires json_value for the title column to be non-nil" do
      value = build(
        :memex_project_column_value,
        memex_project_column: @title_column,
        json_value: nil
      )
      refute value.save
      assert_includes value.errors.full_messages, "Json value must be a Hash"
    end

    test "requires json_value for the title column to be a hash" do
      value = build(
        :memex_project_column_value,
        memex_project_column: @title_column,
        json_value: "123"
      )
      refute value.save
      assert_includes value.errors.full_messages, "Json value must be a Hash"
    end

    test "requires json_value for title column to have a top-level 'title' key" do
      value = build(
        :memex_project_column_value,
        memex_project_column: @title_column,
        json_value: { "html" => "foo" }
      )
      refute value.save
      assert_includes value.errors.full_messages, "Json value must include a 'title' value"
    end

    test "requires 'title' key in json_value to have the correct sub-keys" do
      value = build(
        :memex_project_column_value,
        memex_project_column: @title_column,
        json_value: { "title" => { "bogus" => "foo" } }
      )
      refute value.save
      assert_includes value.errors.full_messages, "Json value 'title' object must include a 'raw' value"
      assert_includes value.errors.full_messages, "Json value 'title' object must include an 'html' value"
    end

    test "requires json_value for title column on an Issue item to include all required keys specific to issues" do
      MemexProjectColumnValue::JsonValueValidator::ISSUE_TITLE_REQUIRED_KEYS.each do |required_key|
        invalid_json_value = { "title" => { "raw" => "foo", "html" => "foo" } }

        # Fill in values for all but one of the required keys.
        (MemexProjectColumnValue::JsonValueValidator::ISSUE_TITLE_REQUIRED_KEYS - [required_key]).each do |k|
          invalid_json_value[k] = "x"
        end

        value = build(
          :memex_project_column_value,
          memex_project_column: @title_column,
          memex_project_item: @issue_item,
          json_value: invalid_json_value
        )
        refute value.save, "Should not have saved value without required key: '#{required_key}'"
        assert_includes value.errors.full_messages, "Json value Issue 'title' object must include '#{required_key}' value"
      end
    end

    test "requires json_value for title column on a PullRequest item to include all required keys specific to pulls" do
      MemexProjectColumnValue::JsonValueValidator::PULL_REQUEST_TITLE_REQUIRED_KEYS.each do |required_key|
        invalid_json_value = { "title" => { "raw" => "foo", "html" => "foo" } }

        # Fill in values for all but one of the required keys.
        (MemexProjectColumnValue::JsonValueValidator::PULL_REQUEST_TITLE_REQUIRED_KEYS - [required_key]).each do |k|
          invalid_json_value[k] = "x"
        end

        value = build(
          :memex_project_column_value,
          memex_project_column: @title_column,
          memex_project_item: @pull_item,
          json_value: invalid_json_value
        )
        refute value.save, "Should not have saved value without required key: '#{required_key}'"
        assert_includes value.errors.full_messages, "Json value PullRequest 'title' object must include '#{required_key}' value"
      end
    end

    test "sets memex_project_column_data_type upon validation" do
      value = build(:memex_project_column_value, memex_project_column: @number_column, value: 1)
      assert_nil value.memex_project_column_data_type

      value.validate!

      assert_equal MemexProjectColumn.data_types[:number], value.memex_project_column_data_type
    end
  end

  context "for columns of data_type :milestone" do
    test "requires json_value for milestone column to have an 'id' key" do
      value = build(
        :milestone_column_value,
        json_value: { type: "Milestone", value: { number: 2, state: "open", title: "GitHub Universe", url: "url" } }
      )

      assert value.memex_project_column.milestone?

      refute value.save
      assert_includes value.errors.full_messages, "Json value 'milestone' object must include 'id' value"
    end

    test "requires json_value for milestone column to have an 'number' key" do
      value = build(
        :milestone_column_value,
        json_value: { type: "Milestone", value: { id: 5, state: "open", title: "GitHub Universe", url: "url" } }
      )

      assert value.memex_project_column.milestone?

      refute value.save
      assert_includes value.errors.full_messages, "Json value 'milestone' object must include 'number' value"
    end

    test "requires json_value for milestone column to have an 'state' key" do
      value = build(
        :milestone_column_value,
        json_value: { type: "Milestone", value: { id: 5, number: 2, title: "GitHub Universe", url: "url" } }
      )

      assert value.memex_project_column.milestone?

      refute value.save
      assert_includes value.errors.full_messages, "Json value 'milestone' object must include 'state' value"
    end

    test "requires json_value for milestone column to have an 'title' key" do
      value = build(
        :milestone_column_value,
        json_value: { type: "Milestone", value: { id: 5, number: 2, state: "open", url: "url" } }
      )

      assert value.memex_project_column.milestone?

      refute value.save
      assert_includes value.errors.full_messages, "Json value 'milestone' object must include 'title' value"
    end

    test "requires json_value for milestone column to have an 'url' key" do
      value = build(
        :milestone_column_value,
        json_value: { type: "Milestone", value: { id: 5, number: 2, state: "open", title: "GitHub Universe" } }
      )

      assert value.memex_project_column.milestone?

      refute value.save
      assert_includes value.errors.full_messages, "Json value 'milestone' object must include 'url' value"
    end

    test "requires json_value for milestone column 'url' key a non-empty string" do
      value = build(
        :milestone_column_value,
        json_value: { type: "Milestone", value: { id: 5, number: 2, state: "open", title: "GitHub Universe", url: "" } }
      )

      assert value.memex_project_column.milestone?

      refute value.save
      assert_includes value.errors.full_messages, "Json value 'milestone' object must include 'url' value"
    end

    test "sets json_value_id column to milestone ID on save" do
      milestone = create(:milestone)
      issue = create(:issue, repository: milestone.repository, milestone: milestone)
      item = create(:memex_project_item, content: issue)
      milestone_column = item.memex_project.columns.find(&:milestone?)

      value = build(
        :memex_project_column_value,
        memex_project_item: item,
        memex_project_column: milestone_column,
        json_value: item.content.memex_denormalized_milestone_value
      )
      refute value.persisted?
      assert_nil value.json_value_id

      value.save!
      assert_equal milestone.id, value.json_value_id
    end
  end

  context "#memex_project" do
    test "returns the project associated with the column value" do
      column_value = create(:memex_project_column_value, memex_project_item: @issue_item,
        memex_project_column: @number_column, value: "10", creator: @admin)
      assert_equal @memex, column_value.memex_project
    end

    test "does not make any queries if column relation is already loaded" do
      column_value = create(:memex_project_column_value, memex_project_item: @issue_item,
        memex_project_column: @number_column, value: "10", creator: @admin)
      column_value.memex_project_column # make sure the column is loaded

      assert_query_count(0) do
        assert_equal @memex, column_value.memex_project
      end
    end

    test "does not make any queries if item relation is already loaded" do
      column_value = create(:memex_project_column_value, memex_project_item: @issue_item,
        memex_project_column: @number_column, value: "10", creator: @admin)
      column_value.memex_project_item # make sure the item is loaded

      assert_query_count(0) do
        assert_equal @memex, column_value.memex_project
      end
    end

    test "loads the project relation directly if neither item nor column are loaded on the column value" do
      column_value = create(:memex_project_column_value, memex_project_item: @issue_item,
        memex_project_column: @number_column, value: "10", creator: @admin)
      column_value = MemexProjectColumnValue.find(column_value.id) # make sure no relations are already loaded

      assert_query_count(1) do
        assert_equal @memex, column_value.memex_project
      end

      assert_predicate column_value.association(:memex_project), :loaded?
    end
  end

  context "for columns of data_type :text" do
    test "allows storing a short string value" do
      value = build(:memex_project_column_value, value: "This is text of a reasonable length.")
      assert value.memex_project_column.text?
      assert value.save
    end

    test "enforces a maximum length" do
      value = build(
        :memex_project_column_value,
        value: "x" * (MemexProjectColumnValue::TEXT_VALUE_BYTESIZE_LIMIT + 1)
      )
      assert value.memex_project_column.text?

      refute value.save
      assert_includes value.errors.full_messages, "Value is too long (maximum is 256 characters)"
    end

    test "validation keeps text column json_value in sync with value" do
      value = build(:memex_project_column_value, value: "Text value", json_value: { raw: "Wrong text value", html: "Wrong text value" })
      assert value.save
      assert_equal(
        { "raw" => "Text value", "html" => "Text value" },
        value.json_value
      )
    end

    test "json_value generated during validation correctly processes colon-emoji and auto-linked URLs" do
      value = build(:memex_project_column_value, value: ":tada: https://github.com :tada:")
      assert value.save
      assert_equal(
        {
          "raw" => ":tada: https://github.com :tada:",
          "html" => %Q(🎉 <a href="https://github.com">https://github.com</a> 🎉)
        },
        value.json_value
      )

    end

    test "json_value generated during validation is entity encoded properly" do
      url = "https://t.com/t/s/i/4863?notification_referrer_id=NT_kwDOBbVs27MzNDEyMDY5NjMzOjk1Nzc1OTYz&notifications_after=Y3Vyc29yOjI1#issuecomment-1213514002"
      value = build(:memex_project_column_value, value: url)
      value.save

      assert_equal({
        "raw" => "https://t.com/t/s/i/4863?notification_referrer_id=NT_kwDOBbVs27MzNDEyMDY5NjMzOjk1Nzc1OTYz&notifications_after=Y3Vyc29yOjI1#issuecomment-1213514002",
        "html" => "<a href=\"https://t.com/t/s/i/4863?notification_referrer_id=NT_kwDOBbVs27MzNDEyMDY5NjMzOjk1Nzc1OTYz&amp;notifications_after=Y3Vyc29yOjI1#issuecomment-1213514002\">https://t.com/t/s/i/4863?notification_referrer_id=NT_kwDOBbVs27MzNDEyMDY5NjMzOjk1Nzc1OTYz&amp;notifications_after=Y3Vyc29yOjI1#issuecomment-1213514002</a>"
      }, value.json_value)

      already_encoded_entity = "&lt; Hello"
      value = build(:memex_project_column_value, value: already_encoded_entity)
      value.save

      assert_equal({
        "raw" => already_encoded_entity,
        "html" => already_encoded_entity
      }, value.json_value)

      html_tag = "<a href=\"example.biz\">example</a>"
      value = build(:memex_project_column_value, value: html_tag)
      value.save

      assert_equal({
        "raw" => html_tag,
        "html" => html_tag
      }, value.json_value)

      text = "updates `column` to `test_column`"
      value = build(:memex_project_column_value, value: text)
      value.save

      assert_equal({
        "raw" => text,
        "html" => text
      }, value.json_value)
    end

    test "json_value generated during validation prevents XSS" do
      value = build(:memex_project_column_value, value: "&lt;script>alert('XSS')&lt;/script> :tada: https://github.com <script>alert('XSS')</script> :tada:")
      assert value.save
      refute_match %r{</?script>}, value.json_value["html"]
    end
  end

  context "for columns of data_type :single_select" do
    test "requires that value is an allowed value for single select columns" do
      column = create(:single_select_memex_column, memex_project: @memex)
      value = build(:memex_project_column_value, memex_project_column: column, value: 123)

      refute value.save
      assert_includes value.errors.full_messages, "Value is not a valid option for this column"

      value.value = "aaaaaaaa"
      assert value.save
    end

    test "validation keeps single_select column json_value in sync with value" do
      column = create(:single_select_memex_column, memex_project: @memex)
      value = build(:memex_project_column_value, memex_project_column: column, value: "aaaaaaaa", json_value: { id: "dddddddd" })
      assert value.save
      assert_equal(
        { "id" => "aaaaaaaa" },
        value.json_value
      )
    end
  end

  context "for columns of data_type :iteration" do
    test "requires that value is an allowed value for iteration columns" do
      column = create(:iteration_memex_column, memex_project: @memex)
      value = build(:memex_project_column_value, memex_project_column: column, value: "dddddddd")

      refute value.save
      assert_includes value.errors.full_messages, "Value is not a valid option for this column"

      value.value = column.settings.dig("configuration", "iterations").first["id"]
      assert value.save
    end

    test "validation keeps iteration column json_value in sync with value" do
      column = create(:iteration_memex_column, memex_project: @memex)
      second_iteration_value = column.settings.dig("configuration", "iterations")[1]["id"]
      value = build(:memex_project_column_value, memex_project_column: column, value: second_iteration_value, json_value: { id: "dddddddd" })
      assert value.save
      assert_equal(
        { "id" => second_iteration_value },
        value.json_value
      )
    end

    test "validation will update if a completed iteration value used" do
      column = create(:iteration_memex_column_with_completed_iterations, memex_project: @memex)
      first_completed_iteration_id = column.settings.dig("configuration", "completed_iterations")[0]["id"]
      value = build(:memex_project_column_value, memex_project_column: column, value: first_completed_iteration_id, json_value: { id: "dddddddd" })

      assert value.save
      assert_equal(
        { "id" => first_completed_iteration_id },
        value.json_value
      )
    end
  end

  context "for columns of data_type :number" do
    test "allows numeric value" do
      value = build(:memex_project_column_value, memex_project_column: @number_column, value: "Bloop!")

      refute value.save
      assert_includes value.errors.full_messages, "Value is not a number"

      # Integer as a string!
      value.value = "10"
      assert value.save

      # Integer works, too!
      value.value = 10
      assert value.save

      # Floats are supported!
      value.value = "4.90"
      assert value.save

      # Scientific numbers, too!
      value.value = "1E4"
      assert value.save
    end

    test "validates max and min value, and precision" do
      value = build(:memex_project_column_value, memex_project_column: @number_column, value: "10")

      assert value.save

      max = MemexProjectColumnValue::NUMBER_VALUE_SIGNED_INT_LIMIT

      value.value = max + 1
      refute value.save
      assert_includes value.errors.full_messages, "Value must be less than or equal to #{max}"

      value.value = -(max + 1)
      refute value.save
      assert_includes value.errors.full_messages, "Value must be greater than or equal to -#{max}"

      allowed_precision = MemexProjectColumnValue::NUMBER_VALUE_PRECISION
      lots_of_decimals = "1" * (allowed_precision + 1)
      value.value = "0.#{lots_of_decimals}"
      refute value.save
      assert_includes value.errors.full_messages, "Value must not exceed precision of #{allowed_precision}"

      maximum_decimals = "9" * allowed_precision
      value.value = "0.#{maximum_decimals}"
      assert value.save
    end

    test "validates weird rounding error case see https://github.com/github/memex/issues/9265" do
      weird_rounding_error_example_number = 45035997
      value = build(:memex_project_column_value, memex_project_column: @number_column, value: weird_rounding_error_example_number)
      assert value.save
      assert_equal value.value, weird_rounding_error_example_number.to_s
      assert_equal value.json_value["value"], weird_rounding_error_example_number
    end

    test "validation keeps number column json_value in sync with value" do
      value = build(:memex_project_column_value, memex_project_column: @number_column, value: "123", json_value: { value: 456 })
      assert value.save
      assert_equal(
        { "value" => 123 },
        value.json_value
      )
    end
  end

  context "for columns of data_type :date" do
    test "allows date value" do
      value = build(:memex_project_column_value, memex_project_column: @date_column, value: "Bloop!")

      refute value.save
      assert_includes value.errors.full_messages, "Value is not a date"

      # Basic date
      value.value = "2021-01-01"
      assert value.save

      # Slashes!
      value.value = "2021/01/01"
      assert value.save

      # ISO 8601
      value.value = "2021-04-23T18:25:43.511Z"
      assert value.save

      # mm-dd-yyyy style
      value.value = "01-01-2021"
      assert value.save

      # mm/dd/yyyy style
      value.value = "01/01/2021"
      assert value.save
    end

    test "validates non-date values" do
      value = build(:memex_project_column_value, memex_project_column: @date_column, value: "2021")
      refute value.save
      assert_includes value.errors.full_messages, "Value is not a date"

      value.value = "2021-01"
      refute value.save
      assert_includes value.errors.full_messages, "Value is not a date"

      [ # test for special date cases recently seen as of https://github.com/github/projects-backend/issues/505
        "232023-05-08T00:00:00+00:00",
        "162023-06-05T00:00:00+00:00",
        "212023-05-10T00:00:00+00:00",
        "232023-05-12T00:00:00+00:00"
      ].each do |invalid_date|
        value.value = invalid_date
        refute value.save
        assert_includes value.errors.full_messages, "Value is not a date"
      end
    end

    test "validation keeps date column json_value in sync with value" do
      value = build(:memex_project_column_value, memex_project_column: @date_column, value: "01-01-2021", json_value: { value: "02-02-2021" })
      assert value.save
      assert_equal(
        { "value" => "2021-01-01T00:00:00+00:00" },
        value.json_value
      )
    end
  end

  context "instrumentation" do
    test "publishes to hydro on column value create event" do
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        value = build(:memex_project_column_value, memex_project_item: @issue_item, memex_project_column: @number_column, value: "10", creator: @admin)
        assert value.save
        @memex.reload

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@admin),
          memex_project_column: Hydro::EntitySerializer.memex_project_column(@number_column),
          memex_project_item: Hydro::EntitySerializer.memex_project_item(@issue_item),
          memex_project: Hydro::EntitySerializer.memex_project(@memex),
          performed_at: now,
          name: "column_value_create",
          context: value.previous_changes[:json_value].to_json,
        }, schema: "github.memex.v1.Event")

        assert_hydro_published({
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@admin),
          project_column: Hydro::EntitySerializer.memex_project_column(@number_column),
          project_item: Hydro::EntitySerializer.memex_project_item(@issue_item),
          project: Hydro::EntitySerializer.memex_project(@memex),
          value: "10"
        }, schema: "github.memex.v0.MemexProjectColumnValueCreate")

        assert_hydro_published(serialize_user_generated_content_message({
          action_type: :CREATE,
          actor: @admin,
          content_type: :MEMEX_PROJECT_COLUMN_VALUE,
          content_database_id: @memex.id,
          content: "10",
        }), ignore_extra_keys: true, schema: "github.platform_health.v1.UserGeneratedContent")
      end
    end

    test "publishes to hydro on column value update event" do
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        GitHub.context.push(actor_id: @member.id)
        value = create(:memex_project_column_value, memex_project_item: @issue_item, memex_project_column: @number_column, value: "10", creator: @admin)
        reset_hydro

        value.value = "42"
        assert value.save

        @memex.reload

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@member),
          memex_project_column: Hydro::EntitySerializer.memex_project_column(@number_column),
          memex_project_item: Hydro::EntitySerializer.memex_project_item(@issue_item),
          memex_project: Hydro::EntitySerializer.memex_project(@memex),
          performed_at: now,
          name: "column_value_update",
          context: value.previous_changes[:json_value].to_json,
        }, schema: "github.memex.v1.Event")

        assert_hydro_published({
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@member),
          project_column: Hydro::EntitySerializer.memex_project_column(@number_column),
          project_item: Hydro::EntitySerializer.memex_project_item(@issue_item),
          project: Hydro::EntitySerializer.memex_project(@memex),
          value: "42",
          previous_value: "10"
        }, schema: "github.memex.v0.MemexProjectColumnValueUpdate")

        assert_hydro_published(serialize_user_generated_content_message({
          action_type: :UPDATE,
          actor: @member,
          content_type: :MEMEX_PROJECT_COLUMN_VALUE,
          content_database_id: @memex.id,
          content: "42",
        }), ignore_extra_keys: true, schema: "github.platform_health.v1.UserGeneratedContent")
      end
    end

    test "publishes to hydro on column value delete event" do
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        value = create(:memex_project_column_value, memex_project_item: @issue_item, memex_project_column: @number_column, value: "10", creator: @admin)
        reset_hydro

        value.destroy
        @memex.reload

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@admin),
          memex_project_column: Hydro::EntitySerializer.memex_project_column(@number_column),
          memex_project_item: Hydro::EntitySerializer.memex_project_item(@issue_item),
          memex_project: Hydro::EntitySerializer.memex_project(@memex),
          performed_at: now,
          name: "column_value_destroy",
        }, schema: "github.memex.v1.Event")

        assert_hydro_published({
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@admin),
          project_column: Hydro::EntitySerializer.memex_project_column(@number_column),
          project_item: Hydro::EntitySerializer.memex_project_item(@issue_item),
          project: Hydro::EntitySerializer.memex_project(@memex),
          value: "10",
        }, schema: "github.memex.v0.MemexProjectColumnValueDestroy")
      end
    end

    test "does not publish to hydro when attempting to set an invalid date" do
      now = DateTime.new(2023, 05, 06)

      Timecop.freeze(now) do
        value = build(:memex_project_column_value, memex_project_column: @date_column, value: "2021")
        reset_hydro
        refute value.save
        assert_includes value.errors.full_messages, "Value is not a date"
        @memex.reload

        refute_hydro_messages(schema: "github.memex.v0.MemexProjectColumnValueCreate")
      end
    end

    test "does not publish to hydro when attempting to update with an invalid date" do
      now = DateTime.new(2023, 05, 06)

      Timecop.freeze(now) do
        value = build(:memex_project_column_value, memex_project_column: @date_column, value: "2021-04-23T18:25:43.511Z")
        reset_hydro
        assert value.save
        value.value = "232023-05-12T00:00:00+00:00"
        reset_hydro
        refute value.save
        assert_includes value.errors.full_messages, "Value is not a date"
        @memex.reload

        refute_hydro_messages(schema: "github.memex.v0.MemexProjectColumnValueUpdate")
      end
    end

    test "does not publish to hydro on column delete event" do
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        value = create(:memex_project_column_value, memex_project_item: @issue_item, memex_project_column: @number_column, value: "10", creator: @admin)
        reset_hydro
        value.memex_project_column.destroy
        value.destroy

        refute_hydro_messages(schema: "github.memex.v0.MemexProjectColumnValueDestroy")
      end
    end

    test "does not publish to hydro on item delete event" do
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        value = create(:memex_project_column_value, memex_project_item: @issue_item, memex_project_column: @number_column, value: "10", creator: @admin)
        reset_hydro

        value.memex_project_item.destroy
        value.destroy

        refute_hydro_messages(schema: "github.memex.v0.MemexProjectColumnValueDestroy")
      end
    end
  end

  test "supports emoji for value" do
    value = create(:memex_project_column_value, value: "we ❤️ emojis")

    assert_multibyte_tracked_changes(value, :value)
  end

  context "notify socket subscribers after commit" do
    test "draft issue item column value create does nothing" do
      draft_issue = create(:draft_issue)
      draft_issue_item = create(:memex_project_item, memex_project: @memex, content: draft_issue)

      draft_issue.class.any_instance.expects(:notify_socket_subscribers).never
      value = create(:memex_project_column_value, memex_project_item: draft_issue_item, memex_project_column: @number_column, value: "10", creator: @admin)
    end

    test "draft issue item column value update does nothing" do
      draft_issue = create(:draft_issue)
      draft_issue_item = create(:memex_project_item, memex_project: @memex, content: draft_issue)
      value = create(:memex_project_column_value, memex_project_item: draft_issue_item, memex_project_column: @number_column, value: "10", creator: @admin)

      draft_issue.class.any_instance.expects(:notify_socket_subscribers).never
      value.value = "42"
      assert value.save
    end

    test "draft issue item column value destroy does nothing" do
      draft_issue = create(:draft_issue)
      draft_issue_item = create(:memex_project_item, memex_project: @memex, content: draft_issue)
      value = create(:memex_project_column_value, memex_project_item: draft_issue_item, memex_project_column: @number_column, value: "10", creator: @admin)

      draft_issue.class.any_instance.expects(:notify_socket_subscribers).never
      assert value.destroy
    end

    test "issue item column value create" do
      @issue.class.any_instance.expects(:notify_socket_subscribers).once
      value = create(:memex_project_column_value, memex_project_item: @issue_item, memex_project_column: @number_column, value: "10", creator: @admin)
    end

    test "issue item column value update" do
      value = create(:memex_project_column_value, memex_project_item: @issue_item, memex_project_column: @number_column, value: "10", creator: @admin)

      @issue.class.any_instance.expects(:notify_socket_subscribers).once
      value.value = "42"
      assert value.save
    end

    test "issue item column value destroy" do
      value = create(:memex_project_column_value, memex_project_item: @issue_item, memex_project_column: @number_column, value: "10", creator: @admin)

      @issue.class.any_instance.expects(:notify_socket_subscribers).once
      assert value.destroy
    end

    test "pull request item column value create" do
      @pull.class.any_instance.expects(:notify_socket_subscribers).once
      value = create(:memex_project_column_value, memex_project_item: @pull_item, memex_project_column: @number_column, value: "10", creator: @admin)
    end

    test "pull request item column value update" do
      value = create(:memex_project_column_value, memex_project_item: @pull_item, memex_project_column: @number_column, value: "10", creator: @admin)

      @pull.class.any_instance.expects(:notify_socket_subscribers).once
      value.value = "42"
      assert value.save
    end

    test "pull request item column value destroy" do
      value = create(:memex_project_column_value, memex_project_item: @pull_item, memex_project_column: @number_column, value: "10", creator: @admin)

      @pull.class.any_instance.expects(:notify_socket_subscribers).once
      assert value.destroy
    end
  end
end
