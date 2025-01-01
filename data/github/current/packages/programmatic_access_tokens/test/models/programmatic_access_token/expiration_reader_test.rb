# typed: true
# frozen_string_literal: true

require "test_helper"

class ProgrammaticAccessToken::ExpirationReaderTest < GitHub::TestCase
  fixtures do
    @pat = create(:user_programmatic_access)
  end

  def described_class
    ::ProgrammaticAccessToken::ExpirationReader
  end

  test "bubbles dependencies failures" do
    finder_failure = ProgrammaticAccessToken::Result.failed(:client_failure)

    ProgrammaticAccessToken::Finder
      .stubs(:perform)
      .with(@pat.user_id, @pat.id, {})
      .returns(finder_failure)

    result = described_class.perform(@pat.user_id, @pat.id)

    assert_predicate result, :failed?
    assert_equal result.error, :client_failure
  end

  test "succeeds with expiration when found in the credential" do
    expiration_time = 4.days.from_now.utc
    credential = ProgrammaticAccessToken::Credential.new(
      id: 42,
      expires_at: expiration_time
    )

    stub_finder_success(credential)
    result = described_class.perform(@pat.user_id, @pat.id)

    assert_predicate result, :success?
    assert_equal result.value, expiration_time
  end

  test "succeeds with longest expiration when found multiple credentials" do
    expiration_time = 4.days.from_now.utc
    non_expiring_credential = ProgrammaticAccessToken::Credential.new(id: 42)

    expiring_credential = ProgrammaticAccessToken::Credential.new(
      id: 42,
      expires_at: expiration_time
    )

    stub_finder_success([non_expiring_credential, expiring_credential])
    result = described_class.perform(@pat.user_id, @pat.id)

    assert_predicate result, :success?
    assert_nil result.value
  end

  test "return empty success when credential has no expiration" do
    credential = ProgrammaticAccessToken::Credential.new(id: 42)

    stub_finder_success(credential)
    result = described_class.perform(@pat.user_id, @pat.id)

    assert_predicate result, :success?
    assert_nil result.value
  end

  test "succeeds with :expired when credential is empty" do
    stub_finder_success([])
    result = described_class.perform(@pat.user_id, @pat.id)

    assert_predicate result, :success?
    assert_equal :expired, result.value
  end

  def stub_finder_success(credential)
    finder_success = ProgrammaticAccessToken::Result.success(
      Array(credential)
    )

    ProgrammaticAccessToken::Finder
      .stubs(:perform)
      .with(@pat.user_id, @pat.id, {})
      .returns(finder_success)
  end
end
