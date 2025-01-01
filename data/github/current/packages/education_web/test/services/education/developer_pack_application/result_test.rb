# typed: true
# frozen_string_literal: true

require "test_helper"

class EducationDeveloperPackApplicationResultTest < GitHub::TestCase
  context "#success?" do
    context "when the subject has been persisted" do
      test "returns true" do
        subject = create(:education_developer_pack_application_metadata)

        result = Education::DeveloperPackApplication::Result.new(subject:)

        assert result.success?
      end
    end

    context "when the subject has not been persisted" do
      test "returns false" do
        subject = build(:education_developer_pack_application_metadata)

        result = Education::DeveloperPackApplication::Result.new(subject:)

        refute result.success?
      end
    end
  end
end
