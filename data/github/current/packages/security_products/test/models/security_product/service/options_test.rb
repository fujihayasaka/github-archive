# typed: false
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::Service::OptionsTest < GitHub::TestCase
  class AnOption < SecurityProduct::Service::Options
    option :truthy, default: true
    validates :truthy, inclusion: [true, false]
  end

  class SomeOptions < SecurityProduct::Service::Options
    option :truthy, default: true
    validates :truthy, inclusion: [true, false]

    option :picky, default: "blue"
    validates :picky, inclusion: { in: %w[red green blue], message: "must be one of red, green or blue" }
  end

  class ExtraValidation < SecurityProduct::Service::Options
    option :runner_label
    validates :runner_label, presence: true, length: { minimum: 5 }
  end

  context "with a base class" do
    test "it has empty attributes" do
      assert_equal SecurityProduct::Service::Options.new.attributes, {}
    end

    test "it is empty as json" do
      assert_equal SecurityProduct::Service::Options.new.as_json, {}
    end

    test "it is valid" do
      assert SecurityProduct::Service::Options.new.valid?
    end

    context "before_validation" do
      test "it always returns an empty array" do
        opts = {
          truthy: false,
          picky: "red",
        }

        assert_equal SecurityProduct::Service::Options.before_validation(opts), {}
      end
    end
  end

  context "with a child class that defines options" do
    test "a new options object has the correct default values" do
      opts = AnOption.new

      assert opts.truthy

      opts = SomeOptions.new

      assert opts.truthy
      assert_equal opts.picky, "blue"
    end

    test "options objects correctly return their attributes" do
      assert_equal AnOption.new.attributes, { "truthy" => true }
      assert_equal SomeOptions.new(picky: "green").attributes, { "truthy" => true, "picky" => "green" }
    end

    test "it is not valid if an option has a non-permitted value" do
      opts = SomeOptions.new

      opts.picky = "yellow"

      refute opts.valid?
      assert_equal "must be one of red, green or blue", opts.errors[:picky].first
    end

    context "before_validation" do
      test "it returns populated defaults with given nil" do
        assert_equal SomeOptions.before_validation(nil), { "truthy" => true, "picky" => "blue" }
      end

      test "it returns populated defaults with given an empty hash" do
        assert_equal SomeOptions.before_validation({}), { "truthy" => true, "picky" => "blue" }
      end

      test "it filters out spurious keys" do
        opts = {
          truthy: false,
          picky: "green",
          selective: %[apples, oranges]
        }

        assert_equal SomeOptions.before_validation(opts), { "truthy" => false, "picky" => "green" }
      end

      test "it tolerates hashes with string keys" do
        opts = {
          "truthy" => false,
          "picky" => "red",
        }

        assert_equal SomeOptions.before_validation(opts), { "truthy" => false, "picky" => "red" }
      end
    end
  end

  context "with a child class that uses ActiveModel::Validations" do
    test "it enforces presence checks" do
      opts = ExtraValidation.new

      refute opts.valid?
      assert_equal "can't be blank", opts.errors[:runner_label].first
    end

    test "it enforces length checks" do
      opts = ExtraValidation.new(runner_label: "foo")

      refute opts.valid?
      assert_equal "is too short (minimum is 5 characters)", opts.errors[:runner_label].first
    end
  end
end
