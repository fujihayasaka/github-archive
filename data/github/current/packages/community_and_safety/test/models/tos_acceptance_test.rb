# typed: true
# frozen_string_literal: true

require "test_helper"

class TosAcceptanceTest < GitHub::TestCase
  test "TosAcceptance: fails gracefully if no ToS file exists" do
    tos_acceptance = TosAcceptance.new
    tos_acceptance.stubs(:get_tos_sha).returns(nil)
    assert_equal GitHub::NULL_OID, TosAcceptance.current_sha
  end

  test "ToSAcceptance: fails gracefully on prod if no ToS file exists" do
    GitHub::AppEnvironment.stubs(:production?).returns(true)
    assert_equal GitHub::NULL_OID, TosAcceptance.current_sha
  end

  test "Automatically set acceptance sha when saving" do
    tos_acceptance = TosAcceptance.new
    tos_acceptance.user_id = 1

    tos_acceptance.save!
    assert_equal TosAcceptance.current_sha, tos_acceptance.sha
  end
end
