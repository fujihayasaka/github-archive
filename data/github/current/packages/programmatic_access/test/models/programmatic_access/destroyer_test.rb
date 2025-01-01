# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/authnd_client_helpers"
require "test_helpers/abstract_interface_test_helpers"

class ProgrammaticAccess::DestroyerTest < GitHub::TestCase
  include AuthndClientTestHelpers
  include AbstractInterfaceTestHelpers

  fixtures do
    @pat = create(:user_programmatic_access)
  end

  def described_class
    ::ProgrammaticAccess::Destroyer
  end

  context "success" do
    test "returns a success result" do
      result = stub_interface(ProgrammaticAccessTokens::IResult, { success?: true, value: nil, error: nil })
      ProgrammaticAccessTokens::Domain.any_instance.expects(:destroy).once.returns(result)

      result = described_class.perform @pat, :web_user

      assert_predicate result, :success?
      assert_nil result.value
      assert_nil result.error
    end

    test "destroys the access record" do
      result = stub_interface(ProgrammaticAccessTokens::IResult, { success?: true, value: nil, error: nil })
      ProgrammaticAccessTokens::Domain.any_instance.expects(:destroy).once.returns(result)

      assert_difference -> { ProgrammaticAccess.for(@pat.owner).count }, -1 do
        described_class.perform @pat, :web_user
      end
    end

    test "leaves tracing without grant" do
      result = stub_interface(ProgrammaticAccessTokens::IResult, { success?: true, value: nil, error: nil })
      ProgrammaticAccessTokens::Domain.any_instance.expects(:destroy).once.returns(result)

      described_class.perform @pat, :web_user
      destroy_span = find_span_by(name: "ProgrammaticAccess::destroy")

      expected_attributes = {
        "gh.programmatic_access.owner.id" => @pat.user_id,
        "gh.programmatic_access.permissions.count" => 0,
        "gh.programmatic_access.destroy_explanation" => "web_user",
      }

      actual_attributes = destroy_span.attributes.slice(*expected_attributes.keys)
      assert_equal expected_attributes, actual_attributes
    end

    test "includes permission count in tracing when grant is present" do
      result = stub_interface(ProgrammaticAccessTokens::IResult, { success?: true, value: nil, error: nil })
      ProgrammaticAccessTokens::Domain.any_instance.expects(:destroy).once.returns(result)

      pat = create(:user_programmatic_access, :grants)
      pat.grant.permission_records.create!(
        subject_id: pat.user_id,
        subject_type: "User/plan",
        action: :read
      )
      described_class.perform pat, :web_user
      destroy_span = find_span_by(name: "ProgrammaticAccess::destroy")

      expected_attributes = {
        "gh.programmatic_access.owner.id" => pat.user_id,
        "gh.programmatic_access.permissions.count" => 1,
        "gh.programmatic_access.destroy_explanation" => "web_user",
      }

      actual_attributes = destroy_span.attributes.slice(*expected_attributes.keys)
      assert_equal expected_attributes, actual_attributes
    end

    test "destroys the associated grants in the background" do
      pat = create(:user_programmatic_access, :grants)
      result = stub_interface(ProgrammaticAccessTokens::IResult, { success?: true, value: nil, error: nil })
      ProgrammaticAccessTokens::Domain.any_instance.expects(:destroy).once.returns(result)

      assert_difference -> { UserProgrammaticAccessGrant.count }, -1 do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { described_class.perform pat, :web_user }
      end
    end
  end

  context "failure" do
    test "returns a failed result if the access destroy fails" do
      @pat.expects(:destroy).raises(::ActiveRecord::ActiveRecordError)
      result = described_class.perform @pat, :web_user

      assert_predicate result, :failed?
      assert_equal result.error, "ActiveRecord::ActiveRecordError"
      assert_nil result.value
    end

    test "does not call ProgrammaticAccessToken::Destroyer if the access destroy fails" do
      @pat.expects(:destroy).raises(ActiveRecord::RecordNotDestroyed)
      ProgrammaticAccessTokens::Domain.any_instance.expects(:destroy).with(@pat, :web_user).never
      described_class.perform @pat, :web_user
    end

    test "rolls back the transaction if access destroy fails" do
      pat = create(:user_programmatic_access, :grants)
      pat.expects(:destroy).raises(::ActiveRecord::ActiveRecordError)
      assert_no_difference ["ProgrammaticAccess.for(pat.owner).count", "UserProgrammaticAccessGrant.count"] do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { described_class.perform pat, :web_user }
      end
    end

    test "returns a failed result if the token destroy fails" do
      result = stub_interface(ProgrammaticAccessTokens::IResult, { failed?: true, value: nil })
      ProgrammaticAccessTokens::Domain.any_instance.expects(:destroy).once.returns(result)
      result = described_class.perform @pat, :web_user

      assert_predicate result, :failed?
      assert_nil result.value
    end
  end
end
