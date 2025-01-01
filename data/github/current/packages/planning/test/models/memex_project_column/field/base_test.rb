# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnFieldBaseTest < GitHub::TestCase

  IGNORED_FIELD_SUBCLASSES = %w(
    MemexProjectColumnWriteableTest::DefaultField
  )

  setup do
    # Load all MemexProjectColumn::Field::Base subclasses that exist in the expected location so that
    # we can test that they all exhibit certain properties.
    Dir.glob(Rails.root.join("packages/planning/app/models/memex_project_column/field/*.rb")).each { |f| require(f) }
  end

  context "subclasses" do
    test "define valid data types" do
      MemexProjectColumn::Field::Base.subclasses.each do |klass|
        next if IGNORED_FIELD_SUBCLASSES.include?(klass.name)
        assert_includes(
          MemexProjectColumn.data_types.keys,
          klass.data_type.to_s,
          "#{klass.name} defined an invalid data type: #{klass.data_type}"
        )
      end
    end

    test "each define a unique data type" do
      counter = Hash.new(0)
      MemexProjectColumn::Field::Base.subclasses.each { |klass| counter[klass.data_type] += 1 }
      duplicates = counter.select { |_data_type, count| count > 1 }.keys

      assert_empty duplicates, "The following data types are incorrectly declared twice: #{duplicates}"
    end

    test "return a nilable type from #elasticsearch_document" do
      field_klasses_allowed_non_nil_returns_values = [MemexProjectColumn::Field::Title]

      MemexProjectColumn::Field::Base.subclasses.map do |klass|
        next if field_klasses_allowed_non_nil_returns_values.include?(klass)
        assert T::Utils
                .signature_for_instance_method(klass, :elasticsearch_document)
                .return_type
                .types
                .map { |t| t.name }
                .include?("NilClass"), "return type of #elasticsearch_document implementation for #{klass} should be nilable"
      end
    end

    context "disabled fields" do
      test "base class implements disabled predicate as NOT disabled by default" do
        refute MemexProjectColumn::Field::Base.disabled?
      end

      test "subclasses implement disabled predicate as not disabled by default" do
        subclasses_count = MemexProjectColumn::Field::Base.subclasses.count { |k| !IGNORED_FIELD_SUBCLASSES.include?(k.name) }
        refute subclasses_count == 0, "No subclasses found"
        results = MemexProjectColumn::Field::Base.subclasses.reduce({ enabled: 0, disabled: 0 }) do |acc, kclass|
          next acc if IGNORED_FIELD_SUBCLASSES.include?(kclass.name)
          acc[kclass.disabled? ? :disabled : :enabled] += 1
          acc
        end

        assert_equal 2, disabled = results.fetch(:disabled, 0), "Expected 2 subclasses to be disabled, but found #{disabled}"
        assert_equal expected = subclasses_count - disabled, results.fetch(:enabled, 0), "Expected #{expected} subclasses to be enabled"
      end
    end
  end
end
