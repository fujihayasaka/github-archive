# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/authnd_client_helpers"

class ProgrammaticAccessToken::DestroyerTest < GitHub::TestCase
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
    ::ProgrammaticAccessToken::Destroyer
  end

  def finder_class
    ::ProgrammaticAccessToken::Finder
  end

  def stub_finder(result: nil)
    credentials = [::ProgrammaticAccessToken::Credential.new(id: 1)]
    result ||= ::ProgrammaticAccessToken::Result.success(credentials)
    finder_class.stubs(:perform).returns(result)
  end

  test "returns a success result when credentials are destroyed" do
    stub_finder
    stub_authnd_programmatic_access_revoke_credentials_by_id
    result = described_class.perform @pat, :web_user

    assert_predicate result, :success?
    assert_nil result.value
    assert_nil result.error
  end

  test "returns a success when credentials are destroyed by regeneration" do
    stub_finder
    stub_authnd_programmatic_access_revoke_credentials_by_id(
      explanation: "deleted by regeneration on github.com"
    )

    result = described_class.perform @pat, :regeneration

    assert_predicate result, :success?
    assert_nil result.value
    assert_nil result.error
  end

  test "returns a success when credentials are destroyed by staff" do
    stub_finder
    stub_authnd_programmatic_access_revoke_credentials_by_id(
      explanation: "deleted by GitHub staff"
    )

    result = described_class.perform @pat, :site_admin

    assert_predicate result, :success?
    assert_nil result.value
    assert_nil result.error
  end

  test "returns a success result when credentials are not found" do
    stub_finder
    stub_authnd_programmatic_access_revoke_credentials_by_id(result: :RESULT_NOT_FOUND)
    result = described_class.perform @pat, :web_user

    assert_predicate result, :success?
    assert_nil result.value
    assert_nil result.error
  end

  test "returns a success result when credentials are already revoked" do
    stub_finder
    stub_authnd_programmatic_access_revoke_credentials_by_id(result: :RESULT_ALREADY_REVOKED)
    result = described_class.perform @pat, :web_user

    assert_predicate result, :success?
    assert_nil result.value
    assert_nil result.error
  end

  test "returns a failed result if find_credentials call fails" do
    stub_finder(result: ::ProgrammaticAccessToken::Result.failed("error"))
    ::GitHub::Authnd.expects(:credential_manager_for).never
    result = described_class.perform @pat, :web_user

    assert_predicate result, :failed?
    assert_nil result.value
    assert_equal result.error, "error"
  end

  test "returns a failed result if authnd returns a failed result for revoke" do
    stub_finder
    stub_authnd_programmatic_access_revoke_credentials_by_id(result: :RESULT_FAILED_CREDENTIAL_INVALID)
    result = described_class.perform @pat, :web_user

    assert_predicate result, :failed?
    assert_nil result.value
  end

  test "returns a failed result if an exception is raised during revoke" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    stub_finder
    stub_authnd_programmatic_access_revoke_credentials_by_id(raise_with: Faraday::ClientError.new("error"))
    result = described_class.perform @pat, :web_user

    assert_predicate result, :failed?
    assert_nil result.value
    assert_equal result.error, "error"

    key = "programmatic_access_token.destroyer"
    assert_equal 1, GitHub.dogstats.increments(key, tags: ["result:failure"]).length
  end
end
