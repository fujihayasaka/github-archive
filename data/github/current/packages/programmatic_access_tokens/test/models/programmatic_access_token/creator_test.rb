# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/authnd_client_helpers"

class ProgrammaticAccessToken::CreatorTest < GitHub::TestCase
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
    ::ProgrammaticAccessToken::Creator
  end

  test "returns a success result when a token has been minted" do
    stub_authnd_programmatic_access_issue_token
    result = described_class.perform(@pat.user_id, @pat.id, {})

    assert_predicate result, :success?
    assert_kind_of String, result.value
    assert_nil result.error
  end

  test "returns a failed result if the authnd returns a failed result" do
    stub_authnd_programmatic_access_issue_token(result: :RESULT_INVALID_ATTRIBUTES, error: "attribute 'actor.id' is required")
    result = described_class.perform(@pat.user_id, @pat.id, {})

    assert_predicate result, :failed?
    assert_equal result.error, "attribute 'actor.id' is required"
    assert_nil result.value
  end

  test "returns a failed result if an exception is raised during the process" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    stub_authnd_programmatic_access_issue_token(raise_with: Faraday::ClientError.new("error"))
    result = described_class.perform(@pat.user_id, @pat.id, {})

    assert_predicate result, :failed?
    assert_equal result.error, "error"
    assert_nil result.value

    key = "programmatic_access_token.creator"
    assert_equal 1, GitHub.dogstats.increments(key, tags: ["result:failure"]).length
  end
end
