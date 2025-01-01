# typed: false
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class FormModelTest < GitHub::TestCase
    test "defines methods for each provided attribute" do
      form_model = FormModel.new(name: "example", attributes: { foo: "bar" })

      assert_equal "bar", form_model.foo
    end

    test "defines methods when given unusual attributes" do
      form_model = FormModel.new(name: "example", attributes: { "you wouldn't expect this to work": "but it does" })

      assert_equal "but it does", form_model.public_send("you wouldn't expect this to work")
    end

    test "raises an error when attribute key matches existing method" do
      exception = assert_raises ArgumentError do
        FormModel.new(name: "example", attributes: { attributes: "very meta" })
      end

      assert_equal "Invalid attribute name: :attributes (method already exists)", exception.message
    end

    test "defines model name based on object name" do
      form_model = FormModel.new(name: "example")

      assert_equal "example", form_model.model_name.name
    end

    test "creates empty error object" do
      form_model = FormModel.new(name: "example")

      assert form_model.errors.empty?
    end

    test "accepts ActiveModel::Errors instance" do
      errors = ActiveModel::Errors.new(nil)
      form_model = FormModel.new(name: "example", errors: errors)

      assert_equal errors, form_model.errors
    end

    test "accepts hash of errors" do
      errors = {
        username: ["can't be blank", "is already taken"],
        email: ["isn't valid"],
      }
      form_model = FormModel.new(name: "example", errors: errors)

      assert_equal "Username can't be blank, Username is already taken, and Email isn't valid", form_model.errors.full_messages.to_sentence
    end
  end
end
