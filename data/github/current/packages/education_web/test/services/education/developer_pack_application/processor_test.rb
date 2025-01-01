# typed: true
# frozen_string_literal: true

require "test_helper"

class EducationDeveloperPackApplicationProcessorTest < GitHub::TestCase
  include Education::DeveloperPackApplicationTestHelper

  context ".call" do
    test "instantiates a new processor, calls it, and returns a result" do
      user = create(:user)

      processor_result = Education::DeveloperPackApplication::Processor.call(
        user:,
        form_values: default_form_values,
      )

      assert_equal Education::DeveloperPackApplication::Result, processor_result.class
    end
  end

  context "#call" do
    test "returns a successful result" do
      user = create(:user)
      processor = Education::DeveloperPackApplication::Processor.new(
        user:,
        form_values: default_form_values,
      )

      result = processor.call

      assert result.success?
    end

    test "creates a new developer pack application metadata record for the user" do
      user = create(:user)
      processor = Education::DeveloperPackApplication::Processor.new(
        user:,
        form_values: default_form_values,
      )

      assert_difference(-> { EducationDeveloperPackApplicationMetadata.count }, 1) do
        processor.call
      end
    end

    test "returns an unsuccessful result if the user is not eligible" do
      user = create(:user)
      create(:education_developer_pack_application_metadata, :approved, user:)
      processor = Education::DeveloperPackApplication::Processor.new(
        user:,
        form_values: default_form_values,
      )

      result = processor.call

      refute result.success?
      assert_equal(
        Education::DeveloperPackApplication::Errors::UserNotEligible::ERROR_MESSAGE,
        result.error.message,
      )
    end
  end
end
