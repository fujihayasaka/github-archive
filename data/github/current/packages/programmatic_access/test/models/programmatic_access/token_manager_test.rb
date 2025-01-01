# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/authnd_client_helpers"
require "test_helpers/abstract_interface_test_helpers"

class ProgrammaticAccess::TokenManagerTest < GitHub::TestCase
  include AuthndClientTestHelpers
  include AbstractInterfaceTestHelpers

  fixtures do
    @pat = create(:user_programmatic_access)
  end

  def described_class
    ::ProgrammaticAccess::TokenManager
  end

  context "regenerate" do
    test "notifies owner on success" do
      @pat.expects(:notify_owner).with(about: :regenerated).once
      expiration_time = 3.days.from_now
      stub = stub_interface(ProgrammaticAccessTokens::IResult, { success?: true, value: "gh1_newtoken", error: nil })

      ProgrammaticAccessTokens::Domain.any_instance.expects(:regenerate).once
        .with(@pat.user_id, @pat.id, { expires_at: expiration_time, business: nil }).returns(stub)
      result = described_class.regenerate(@pat, expiration_time)

      assert_predicate result, :success?
      assert_equal result.value, "gh1_newtoken"
    end
  end
end
