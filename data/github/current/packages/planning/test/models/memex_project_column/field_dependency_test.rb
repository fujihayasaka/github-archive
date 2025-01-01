# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnFieldDependencyTest < GitHub::TestCase

  IGNORED_FIELD_SUBCLASSES = %w(
    MemexProjectColumnWriteableTest::DefaultField
  )

  fixtures do
    @unsupported_column = create(:memex_project_column)
    @assignees_column = create(:memex_project_column, data_type: :assignees)
  end

  setup do
    Failbot.reports.clear
  end

  context "FIELD_CLASS_REGISTRY" do
    test "includes all subclasses of MemexProjectColumn::Field::Base that are defined in the expected location" do
      # Load all MemexProjectColumn::Field::Base subclasses that exist in the expected location so that
      # subclass tracking later in this test works as expected.
      Dir.glob(Rails.root.join("packages/planning/app/models/memex_project_column/*.rb")).each { |f| require(f) }

      defined_field_subclasses = MemexProjectColumn::Field::Base.subclasses.map(&:name)
      unregistered_field_subclasses = (
        defined_field_subclasses -
        MemexProjectColumn::FieldDependency::FIELD_CLASS_REGISTRY -
        IGNORED_FIELD_SUBCLASSES
      )

      assert_empty(
        unregistered_field_subclasses,
        "Found the following unregistered MemexProjectColumn::Field::Base subclasses: #{unregistered_field_subclasses}. " +
        "Please add the missing subclasses to the registry in MemexProjectColumn::FieldDependency::FIELD_CLASS_REGISTRY"
      )
    end

    test "does not includes any subclass of MemexProjectColumn::Field::Base that doesn't actually exist" do
      MemexProjectColumn::FieldDependency::FIELD_CLASS_REGISTRY.each do |class_name|
        begin
          assert_kind_of MemexProjectColumn::Field::Base, class_name.constantize.new
        rescue NameError
          assert_nil(
            class_name,
            "#{class_name} does not exist. " +
            "Please remove it from MemexProjectColumn::FieldDependency::FIELD_CLASS_REGISTRY"
          )
        end
      end
    end
  end

  context "#to_field" do
    test "returns a Field" do
      field = @assignees_column.to_field
      refute_nil field
      assert field.is_a?(MemexProjectColumn::Field::Base)
    end

    test "raises in non-production environments when no MemexProjectColumn subclass exists for the instance's data_type" do
      @unsupported_column.stubs(:data_type).returns("unsupported")
      error = assert_raises(MemexProjectColumn::FieldDependency::MissingFieldImplementation) { @unsupported_column.to_field }
      assert_match /subclass named MemexProjectColumn::Field::Unsupported/, error.message
    end

    test "raises in non-production environments when no Field subclass exists for the instance's data type" do
      # Resist becoming the Field subclass to mock a column with
      # a valid data_type, but no corresponding Field subclass
      @unsupported_column.expects(:becomes).with(MemexProjectColumn::Field::Text).returns(@unsupported_column)
      error = assert_raises(MemexProjectColumn::FieldDependency::MissingFieldImplementation) { @unsupported_column.to_field }
      assert_match /subclass named MemexProjectColumn./, error.message
    end

    test "returns nil in production when no Field exists for the instance's data type", skip_enterprise: true do
      Rails.env.stubs(:production?).returns(true)
      @unsupported_column.stubs(:data_type).returns("unsupported")
      assert_nil @unsupported_column.to_field

      report = Failbot.reports.last
      refute_nil report
      assert_equal(
        "MemexProjectColumn::FieldDependency::MissingFieldImplementation",
        report.dig("exception_detail", 0, "type")
      )
      assert_match /subclass named MemexProjectColumn::Field::Unsupported/, report.dig("exception_detail", 0, "value")
    end

    test "memoizes its result" do
      # Call `to_field` once to memoize the value.
      @assignees_column.to_field

      # Stub a method such that `to_field` would raise if it were really executed a second time.
      @assignees_column.stubs(:becomes).raises(NameError)

      # Confirm we don't raise because the previous invocation was memoized.
      assert_nothing_raised { @assignees_column.to_field }
    end
  end
end
