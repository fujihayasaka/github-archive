# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/planning"

class MemexProjectColumnWriteableTest < GitHub::TestCase
  include MemexHelpers
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  fixtures do
    @item = create(:memex_project_item)
    @actor = create(:user)
  end

  setup do
    @index = Elastomer::Indexes::MemexProjectItems.new
  end

  context ".writeable?" do
    test "is false by default" do
      refute_predicate DefaultField, :writeable?
    end
  end

  context "#update_field_value" do
    test "raises an InterfaceNotSupportedError by default" do
      error = assert_raises(MemexProjectColumn::Field::Base::InterfaceNotSupportedError) do
        DefaultField.new.update_field_value(item: @item, new_value: true, actor: @actor)
      end

      assert_equal "field is not writeable", error.message
    end

    test "returns a result that reflects success of both write operations when they both succeed" do
      DefaultField.stubs(:writeable?).returns(true)
      DefaultField
        .any_instance
        .stubs(:update_mysql_field_value)
        .returns(MemexProjectColumn::Interface::Writeable::PartialResult.success)
      DefaultField
        .any_instance
        .stubs(:update_elasticsearch_field_value)
        .returns(MemexProjectColumn::Interface::Writeable::PartialResult.success)

      result = DefaultField.new.update_field_value(item: @item, new_value: true, actor: @actor)

      assert_predicate result.mysql, :succeeded?
      assert_predicate result.elasticsearch, :succeeded?
    end

    test "returns a result that reflects failure of the MySQL write" do
      error_message = "connection timeout"

      DefaultField.stubs(:writeable?).returns(true)
      DefaultField
        .any_instance
        .stubs(:update_mysql_field_value)
        .returns(MemexProjectColumn::Interface::Writeable::PartialResult.failure(error_message))

      # Make sure that we short-circuit the Elasticsearch write if the MySQL write fails.
      DefaultField.any_instance.expects(:update_elasticsearch_field_value).never

      result = DefaultField.new.update_field_value(item: @item, new_value: true, actor: @actor)

      assert_predicate result.mysql, :failed?
      assert_equal error_message, T.must(result.mysql.error).message
      assert_equal error_message, @item.errors.full_messages.join(", ")

      assert_nil result.elasticsearch
    end

    test "returns a result that reflects failure of the Elasticsearch write" do
      error_message = "connection timeout"

      DefaultField.stubs(:writeable?).returns(true)
      DefaultField
        .any_instance
        .stubs(:update_mysql_field_value)
        .returns(MemexProjectColumn::Interface::Writeable::PartialResult.success)

      DefaultField
        .any_instance
        .stubs(:update_elasticsearch_field_value)
        .returns(MemexProjectColumn::Interface::Writeable::PartialResult.failure(error_message))

      result = DefaultField.new.update_field_value(item: @item, new_value: true, actor: @actor)

      assert_predicate result.mysql, :succeeded?
      assert_predicate result.elasticsearch, :failed?
      assert_equal error_message, T.must(result.elasticsearch&.error).message
    end

    test "skips elasticsearch writes when instructed to do so" do
      DefaultField.stubs(:writeable?).returns(true)
      DefaultField
        .any_instance
        .stubs(:update_mysql_field_value)
        .returns(MemexProjectColumn::Interface::Writeable::PartialResult.success)

      # Make sure that we short-circuit the Elasticsearch write
      # since we will explicitly instruct `update_field_value` to do so.
      DefaultField.any_instance.expects(:update_elasticsearch_field_value).never

      result = DefaultField.new.update_field_value(
        item: @item,
        new_value: true,
        actor: @actor,
        skip_elasticsearch_updates: true
      )

      assert_predicate result.mysql, :succeeded?
      assert_nil result.elasticsearch
    end

    MemexHelpers.for_each_field_subclass(:writeable?).each do |class_name|
      context "for the #{class_name.demodulize} field type" do

        # The title field is special in that it is always populated, so we need to account for that in our test cases.
        value_required = class_name.demodulize == "Title"

        # Since we've made the blank_item nilable, we enforce that it is only nilable for fields that require a value
        # (currently only the title field).
        test "validate attributes" do
          assert value_required || load_test_case(class_name).blank_item.present?, "All fields except title must specify a blank_item attribute"
        end

        unless value_required
          test "can set a new value for the field" do
            test_case = load_test_case(class_name)

            assert_unordered_changes(-> { mysql_field_value(test_case.field, test_case.blank_item&.reload).presence }, from: nil, to: test_case.expected_mysql_value) do
              assert_unordered_changes(-> { es_field_value(test_case.field, test_case.blank_item&.reload).presence }, from: nil, to: test_case.expected_es_value) do
                test_case.field.update_field_value(
                  item: T.must(test_case.blank_item),
                  new_value: test_case.new_value,
                  actor: test_case.actor || @actor
                )
              end
            end
          end
        end

        test "can update a value for the field" do
          test_case = load_test_case(class_name)

          assert_unordered_changes(-> { mysql_field_value(test_case.field, test_case.populated_item.reload) }, to: test_case.expected_mysql_value) do
            assert_unordered_changes(-> { es_field_value(test_case.field, test_case.populated_item.reload) }, to: test_case.expected_es_value) do
              test_case.field.update_field_value(
                item: test_case.populated_item,
                new_value: test_case.new_value,
                actor: test_case.actor || @actor
              )
            end
          end
        end

        unless value_required
          test "can clear a value for the field" do
            test_case = load_test_case(class_name)

            assert_unordered_changes(-> { mysql_field_value(test_case.field, test_case.populated_item.reload).presence }, to: nil) do
              assert_unordered_changes(-> { es_field_value(test_case.field, test_case.populated_item.reload).presence }, to: nil) do
                test_case.field.update_field_value(
                  item: test_case.populated_item,
                  new_value: nil,
                  actor: test_case.actor || @actor
                )
              end
            end
          end
        end

        test "skips Elasticsearch writes when the feature flag is disabled" do
          test_case = load_test_case(class_name)
          T.must(test_case.populated_item.memex_project).disable_feature(:memex_sync_write_to_es)

          assert_no_changes(-> { es_field_value(test_case.field, test_case.populated_item) }) do
            test_case.field.update_field_value(
              item: test_case.populated_item,
              new_value: test_case.new_value,
              actor: test_case.actor || @actor
            )
          end
        end

        test "logs the failure of an Elasticsearch write" do
          test_case = load_test_case(class_name)

          Search::Memex::Client.any_instance.expects(:update).returns(
            Elastomer::Interfaces::Api::Update::Response.from_es_response({
              _index: "test",
              _id: "1",
              _primary_term: 1,
              _shards: {
                total: 1,
                successful: 1,
                failed: 0
              },
              _seq_no: 1,
              _version: 1,
              result: "not_found",
            })
          )

          expected_log = {
            "Body" => "Synchronous update of project item field value in Elasticsearch failed",
            "code.namespace" => class_name,
            "code.function" => "update_elasticsearch_field_value",
            "gh.user.id" => test_case.actor&.id || @actor.id,
            "gh.memex.project.id" => test_case.populated_item.memex_project_id,
            "gh.memex.item.id" => test_case.populated_item.id,
          }

          assert_logged(**expected_log) do
            test_case.field.update_field_value(
              item: test_case.populated_item,
              new_value: test_case.new_value,
              actor: test_case.actor || @actor
            )
          end
        end

        unless value_required
          test "ignores errors from a missing item document" do
            test_case = load_test_case(class_name)

            @index.remove(Elastomer::Adapters::MemexProjectItem.create(test_case.populated_item))
            Failbot.reports.clear

            assert_no_changes -> { Failbot.reports.size } do
              test_case.field.update_field_value(
                item: test_case.populated_item,
                new_value: nil,
                actor: test_case.actor || @actor
              )
            end

            assert_dogstats_increment(
              1,
              MemexProjectColumn::Interface::Writeable::DOCUMENT_MISSING_STAT,
              tags: ["context:#{class_name}"]
            )
          end
        end
      end
    end
  end

  context "#elasticsearch_bulk_update_action" do
    test "returns nil if the field is not writeable" do
      assert_nil DefaultField.new.elasticsearch_bulk_update_action(@item)
    end

    test "returns nil if the feature flag is not enabled for the associated project" do
      DefaultField.stubs(:writeable?).returns(true)
      @item.memex_project.disable_feature(:memex_sync_write_to_es)

      assert_nil DefaultField.new.elasticsearch_bulk_update_action(@item)
    end

    MemexHelpers.for_each_field_subclass(:writeable?).each do |class_name|
      context "for the #{class_name.demodulize} field type" do
        test "returns an update that can be successfully applied with the bulk API" do
          test_case = load_test_case(class_name)

          test_case.field.update_field_value(
            item: test_case.populated_item,
            new_value: test_case.new_value,
            actor: test_case.actor || @actor,
            skip_elasticsearch_updates: true
          )

          assert_unordered_changes(-> { es_field_value(test_case.field, test_case.populated_item) }, to: test_case.expected_es_value) do
            Search::Memex::Client.new(@index).bulk do |bulk|
              action = T.must(test_case.field.elasticsearch_bulk_update_action(test_case.populated_item.reload))
              bulk.update(action.body, action.params)
            end
          end
        end
      end
    end
  end

  # A minimal field that inherits all the defaults of the Writeable interface.
  class DefaultField < MemexProjectColumn::Field::Base
    sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
    def self.elasticsearch_mapping
      Elastomer::Interfaces::Mapping::FieldDataTypes::Boolean.new
    end
  end

  sig { params(field_class_name: String).returns(Planning::MemexProjectColumn::WriteableTestCase) }
  private def load_test_case(field_class_name)
    test_case = load_field_test_case(field_class_name, :setup_writeable_test) do |test_case|

      blank_item_present = test_case.blank_item.present?

      if blank_item_present
        assert_predicate(
          mysql_field_value(test_case.field, test_case.blank_item),
          :blank?,
          "`test_case.blank_item` should not have a value stored in MySQL for its #{field_class_name} field"
        )
      end

      assert_predicate(
        mysql_field_value(test_case.field, test_case.populated_item),
        :present?,
        "`test_case.populated_item` should have a non-nil value stored in MySQL for its #{field_class_name} field"
      )

      refute_equal(
        test_case.expected_mysql_value, mysql_field_value(test_case.field, test_case.populated_item),
        "`test_case.populated_item` should have a value that is different from `test_case.expected_mysql_value`"
      )

      populate_elasticsearch_index!([test_case.blank_item, test_case.populated_item].compact)

      if blank_item_present
        assert_predicate(
          es_field_value(test_case.field, test_case.blank_item),
          :blank?,
          "`test_case.blank_item` should not have a value stored in Elasticsearch for its #{field_class_name} field"
        )
      end

      assert_predicate(
        es_field_value(test_case.field, test_case.populated_item),
        :present?,
        "`test_case.populated_item` should have a non-nil value stored in Elasticsearch for its #{field_class_name} field"
      )

      refute_equal(
        test_case.expected_es_value, es_field_value(test_case.field, test_case.populated_item),
        "`test_case.populated_item` should have a value that is different from `test_case.expected_es_value`"
      )

      test_case.populated_item.memex_project.enable_feature(:memex_sync_write_to_es)
    end

    skip("No test case defined for #{field_class_name}") unless test_case

    test_case
  end

  sig { params(field: MemexProjectColumn::Field::Base, item: MemexProjectItem).returns(T.untyped) }
  private def mysql_field_value(field, item)
    item
      .reload
      .column_values(columns: [field], require_prefilled_associations: false)
      .first
      &.dig(:value)
  end

  sig { params(field: MemexProjectColumn::Field::Base, item: MemexProjectItem).returns(T.untyped) }
  private def es_field_value(field, item)
    @index
      .docs
      .get(type: Elastomer::Adapters::MemexProjectItem.document_type, routing: item.memex_project_id, id: item.id)
      .dig("_source", "field_values")
      .find { _1["field_id"] == field.id }
      &.dig(field.class.value_name.to_s)
  end

  UNSPECIFIED = "__unspecified__"
  class UnexpectedTypeMismatch < StandardError; end

  # This provides an assertion helper that is similar to `assert_changes`, but that allows for two arrays that contain
  # same elements to compare as equal, even if those elements appear in different orders.
  sig { params(fetch: T.proc.returns(T.untyped), from: T.untyped, to: T.untyped, block: T.proc.void).void }
  private def assert_unordered_changes(fetch, from: UNSPECIFIED, to: UNSPECIFIED, &block)
    initial_value = fetch.call
    assert_equal_undordered(from, initial_value) if from != UNSPECIFIED

    yield

    final_value = fetch.call
    assert_equal_undordered(to, final_value) if to != UNSPECIFIED
  end

  private def assert_equal_undordered(expected, actual)
    if expected.is_a?(Array) && actual.is_a?(Array)
      assert_same_elements expected, actual
    elsif expected.nil?
      # Using `assert_equal` to compare against `nil` is deprecated in a upcoming version of Minitest and so generates
      # a warning. Instead, use `assert_nil` in this special case.
      assert_nil actual
    elsif !(expected.is_a?(Array) || actual.is_a?(Array))
      assert_equal expected, actual
    else
      raise UnexpectedTypeMismatch.new("#{expected.class.name} != #{actual.class.name}")
    end
  end
end
