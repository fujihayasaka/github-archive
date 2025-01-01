# typed: true
# frozen_string_literal: true

require "test_helper"

class UI::ValidatorTest < GitHub::TestCase

  class MockValidator < UI::Validator
    attr_reader :counter

    def initialize(schema)
      super(schema)
      @counter = 0
    end

    def validate!
      unless schema.is_a? Hash
        errors.add(:base, "expected an hash")
      end
      @counter += 1
    end
  end

  fixtures do
    @feature_flag = :ui_validator_test_flipper
  end

  setup do
    enable_feature_flag(@feature_flag)
  end

  context "#validate!" do
    test "raises NotImplementedError" do
      validator = UI::Validator.new({})
      assert_raises NotImplementedError do
        validator.validate!
      end
    end

    context "with the MockValidator" do
      test "does not raise NotImplementedError" do
        validator = MockValidator.new({})
        assert_nothing_raised do
          validator.validate!
        end
      end
    end
  end

  context "#valid?" do
    test "raises NotImplementedError" do
      validator = UI::Validator.new({})
      assert_raises NotImplementedError do
        validator.valid?
      end
    end

    context "with the MockValidator" do
      test "does not raise" do
        validator = MockValidator.new({})
        assert_nothing_raised do
          validator.valid?
        end
      end

      test "returns true when schema is a hash" do
        validator = MockValidator.new({})
        assert_predicate validator, :valid?
      end

      test "returns false when schema is not a hash" do
        validator = MockValidator.new("not_a_hash")
        refute_predicate validator, :valid?
      end

      test "calling valid? doesn't invoke validate! more than once" do
        validator = MockValidator.new("not_a_hash")
        validator.valid?
        validator.valid?
        validator.valid?
        assert_equal 1, validator.counter
      end
    end
  end

  context "#deprecate" do
    test "says to remove all usage" do
      validator = MockValidator.new({})
      validator.send(:deprecate, "field", use_instead: nil, code_block: nil)
      assert_equal ["`field` is deprecated. Please remove all usage of it"], validator.deprecation_warnings.full_messages
    end

    test "says to use instead" do
      validator = MockValidator.new({})
      validator.send(:deprecate, "field", use_instead: "new_field", code_block: nil)
      assert_equal ["`field` is deprecated. Please use `new_field` instead"], validator.deprecation_warnings.full_messages
    end

    context "with a code block" do
      test "appends a code block when given" do
        code_block = <<~ABOUT_DEPRECATION
          ```diff
          - about: this template...
          + description: this template...
          ```
        ABOUT_DEPRECATION

        validator = MockValidator.new({})
        validator.send(:deprecate, "about", use_instead: "description", code_block: code_block)
        assert_equal(
          ["`about` is deprecated. Please use `description` instead:\n  ```diff\n  - about: this template...\n  + description: this template...\n  ```\n"],
          validator.deprecation_warnings.full_messages
        )
      end

      test "doesn't add an extra newline when a `date` is given" do
        now_date = Time.now.to_date

        code_block = <<~ABOUT_DEPRECATION
          ```diff
          - about: this template...
          + description: this template...
          ```
        ABOUT_DEPRECATION

        validator = MockValidator.new({})
        validator.send(
          :deprecate,
          "about",
          use_instead: "description",
          code_block: code_block,
          date: now_date
        )
        assert_equal(
          ["`about` is deprecated. Please use `description` instead:\n  ```diff\n  - about: this template...\n  + description: this template...\n  ```\n  <i>Deprecation in effect on **#{now_date}**</i>"],
          validator.deprecation_warnings.full_messages
        )
      end
    end

    test "adds a 'Deprecation in effect on' blurb when a `date` is given" do
      now_date = Time.now.to_date
      validator = MockValidator.new({})
      validator.send(:deprecate, "field", use_instead: nil, code_block: nil, date: now_date)
      assert_equal ["`field` is deprecated. Please remove all usage of it\n  <i>Deprecation in effect on **#{now_date}**</i>"], validator.deprecation_warnings.full_messages
    end

    test "warns when feature flag is not given" do
      validator = MockValidator.new({})
      validator.send(:deprecate, "field", use_instead: nil, code_block: nil)
      assert_equal ["`field` is deprecated. Please remove all usage of it"], validator.deprecation_warnings.full_messages
    end

    test "warns when feature flag is not enabled" do
      disable_feature_flag(@feature_flag)
      validator = MockValidator.new({})
      validator.send(:deprecate, "field", use_instead: nil, code_block: nil, feature_flag: @feature_flag)
      assert_equal ["`field` is deprecated. Please remove all usage of it"], validator.deprecation_warnings.full_messages
    end

    test "errors when feature flag is enabled" do
      validator = MockValidator.new({})
      validator.send(:deprecate, "field", use_instead: nil, code_block: nil, feature_flag: @feature_flag)
      assert_equal ["`field` is deprecated. Please remove all usage of it"], validator.errors.full_messages
    end
  end

  context "#deprecate_value" do
    test "invokes #deprecate with the field:value" do
      validator = MockValidator.new({})
      validator.expects(:deprecate)
        .with("field:value", use_instead: "new_field:new_value", code_block: nil, date: nil, feature_flag: @feature_flag)
        .returns

      validator.send(
        :deprecate_value,
        "field",
        "value",
        new_field: "new_field",
        new_value: "new_value",
        code_block: nil,
        date: nil,
        feature_flag: @feature_flag
      )
    end
  end
end
