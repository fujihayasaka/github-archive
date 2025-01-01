# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/authnd_client_helpers"

class ProgrammaticAccess::DestroyerTest < GitHub::TestCase
  include AuthndClientTestHelpers

  fixtures do
    @pat = create(:user_programmatic_access)
  end

  setup do
    setup_authnd_stub
  end

  teardown do
    remove_authnd_stub
  end

  def described_class
    ::ProgrammaticAccess::Destroyer
  end

  def stub_finder
    credentials = [::ProgrammaticAccessToken::Credential.new(id: 1)]
    result = ::ProgrammaticAccessToken::Result.success(credentials)
    ::ProgrammaticAccessToken::Finder.stubs(:perform).returns(result)
  end

  context "success" do
    test "returns a success result" do
      stub_finder
      stub_authnd_programmatic_access_revoke_credentials_by_id

      result = described_class.perform @pat, :web_user

      assert_predicate result, :success?
      assert_nil result.value
      assert_nil result.error
    end

    test "destroys the access record" do
      stub_finder
      stub_authnd_programmatic_access_revoke_credentials_by_id

      assert_difference -> { ProgrammaticAccess.for(@pat.owner).count }, -1 do
        described_class.perform @pat, :web_user
      end
    end

    test "leaves tracing without grant" do
      stub_finder
      stub_authnd_programmatic_access_revoke_credentials_by_id

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
      stub_finder
      stub_authnd_programmatic_access_revoke_credentials_by_id

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
      stub_finder
      stub_authnd_programmatic_access_revoke_credentials_by_id

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
      ProgrammaticAccessToken::Destroyer.expects(:perform).with(@pat, :web_user).never
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
      stub_finder
      stub_authnd_programmatic_access_revoke_credentials_by_id(result: :RESULT_FAILED_CREDENTIAL_INVALID)
      result = described_class.perform @pat, :web_user

      assert_predicate result, :failed?
      assert_nil result.value
    end
  end
end
