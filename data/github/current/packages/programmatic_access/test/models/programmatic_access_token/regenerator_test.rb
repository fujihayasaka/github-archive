# typed: true
# frozen_string_literal: true

require "test_helper"

class ProgrammaticAccessToken::RegeneratorTest < GitHub::TestCase
  include AuthndClientTestHelpers

  fixtures do
    @pat = create(:user_programmatic_access)
  end

  def described_class
    ::ProgrammaticAccessToken::Regenerator
  end

  test "returns a failure without acccess" do
    result = described_class.perform(nil)

    assert_predicate result, :failed?
    assert_equal result.error, "PAT is required"
  end

  test "returns a failure when destroyer fails" do
    @pat.expects(:notify_owner).never
    failure = ProgrammaticAccessToken::Result.failed(:destroy_failed)
    create_count = 0

    ProgrammaticAccessToken::Destroyer
      .stubs(:perform)
      .with(@pat, :regeneration)
      .returns(failure)

    ProgrammaticAccessToken::Creator
      .stubs(:perform)
      .with { create_count += 1 }

    result = described_class.perform(@pat)

    assert_predicate result, :failed?
    assert_equal result, failure
    assert_equal 0, create_count
  end

  test "returns a failure when creator fails" do
    @pat.expects(:notify_owner).never

    failure = ProgrammaticAccessToken::Result.failed(:creation_failed)

    ProgrammaticAccessToken::Destroyer
      .stubs(:perform)
      .with(@pat, :regeneration)
      .returns(ProgrammaticAccessToken::Result.success)

    ProgrammaticAccessToken::Creator
      .stubs(:perform)
      .with(@pat, {})
      .returns(failure)

    result = described_class.perform(@pat)

    assert_predicate result, :failed?
    assert_equal result, failure
  end

  test "returns the new token on successful regeneration" do
    @pat.expects(:notify_owner).with(about: :regenerated).once
    creation_success = ProgrammaticAccessToken::Result.success("gh1_newtoken")
    expiration_time = 3.days.from_now

    ProgrammaticAccessToken::Destroyer
      .stubs(:perform)
      .with(@pat, :regeneration)
      .returns(ProgrammaticAccessToken::Result.success)

    ProgrammaticAccessToken::Creator
      .stubs(:perform)
      .with(@pat, equals(expires_at: expiration_time))
      .returns(creation_success)

    result = described_class.perform(@pat, expires_at: expiration_time)

    assert_predicate result, :success?
    assert_equal result, creation_success
  end

end
