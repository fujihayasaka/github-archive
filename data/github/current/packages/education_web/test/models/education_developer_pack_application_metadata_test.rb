# typed: true
# frozen_string_literal: true

require "test_helper"

class EducationDeveloperPackApplicationMetadataTest < GitHub::TestCase
  context "validations" do
    test "factory creates a valid one by default" do
      assert_predicate build(:education_developer_pack_application_metadata), :valid?
    end

    test "requires a present user association" do
      record = build(:education_developer_pack_application_metadata, user: nil)

      refute_predicate record, :valid?
    end

    test "requires a present application_type" do
      record = build(:education_developer_pack_application_metadata, application_type: nil)

      refute_predicate record, :valid?
    end

    test "requires user to not have an existing pending application" do
      user = create(:user)
      create(:education_developer_pack_application_metadata, :student, user:)

      record = build(:education_developer_pack_application_metadata, :student, user:)

      refute_predicate record, :valid?
    end
  end

  context "scopes" do
    context ".pending" do
      test "returns records that have not been approved or denied" do
        approved_application = create(:education_developer_pack_application_metadata, :approved)
        denied_application = create(:education_developer_pack_application_metadata, :denied)
        pending_application = create(:education_developer_pack_application_metadata)

        pending_results = EducationDeveloperPackApplicationMetadata.pending

        assert_includes pending_results, pending_application
        refute_includes pending_results, approved_application
        refute_includes pending_results, denied_application
      end
    end

    context ".approved" do
      test "returns records that have been approved" do
        approved_application = create(:education_developer_pack_application_metadata, :approved)
        denied_application = create(:education_developer_pack_application_metadata, :denied)
        pending_application = create(:education_developer_pack_application_metadata)

        approved_results = EducationDeveloperPackApplicationMetadata.approved

        assert_includes approved_results, approved_application
        refute_includes approved_results, denied_application
        refute_includes approved_results, pending_application
      end
    end

    context ".expires_in_the_future" do
      test "returns records that have not expired" do
        expired_application = create(:education_developer_pack_application_metadata, :expired)
        pending_application = create(:education_developer_pack_application_metadata)
        approved_application = create(:education_developer_pack_application_metadata, :approved)

        results = EducationDeveloperPackApplicationMetadata.expires_in_the_future

        assert_includes results, approved_application
        refute_includes results, pending_application
        refute_includes results, expired_application
      end
    end
  end

  context "#pending?" do
    test "returns true if the application is pending" do
      record = build(:education_developer_pack_application_metadata)

      assert_predicate record, :pending?
    end

    test "returns false if the application is not pending" do
      record = build(:education_developer_pack_application_metadata, :approved)

      refute_predicate record, :pending?
    end
  end

  context "#expired?" do
    test "returns true if the application has expired" do
      record = build(:education_developer_pack_application_metadata, :expired)

      assert_predicate record, :expired?
    end

    test "returns false if the application has not expired" do
      record = build(:education_developer_pack_application_metadata)

      refute_predicate record, :expired?
    end
  end

  context "#approved?" do
    test "returns true if the application has been approved" do
      record = build(:education_developer_pack_application_metadata, :approved)

      assert_predicate record, :approved?
    end

    test "returns false if the application has not been approved" do
      record = build(:education_developer_pack_application_metadata)

      refute_predicate record, :approved?
    end
  end

  context "#denied?" do
    test "returns true if the application has been denied" do
      record = build(:education_developer_pack_application_metadata, :denied)

      assert_predicate record, :denied?
    end

    test "returns false if the application has not been denied" do
      record = build(:education_developer_pack_application_metadata)

      refute_predicate record, :denied?
    end
  end
end
