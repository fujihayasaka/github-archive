# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class UnsubscribeTokenTest < GitHub::TestCase
    context "#sign" do
      test "signs a token" do
        user = mock("user").responds_like_instance_of(User)
        payload = {}

        Timecop.freeze do
          user.expects(:signed_auth_token)
            .with(scope: "Notifyd:MuteAuth", data: {}, expires: 10.years.from_now)

          UnsubscribeToken.new(:mute_auth).sign(user, payload)
        end
      end
    end

    context "#verify" do
      test "verifies a token and returns a user and a payload" do
        token = "token"
        verification = Struct.new(:user, :data).new(Object.new, Object.new)

        User
          .expects(:verify_signed_auth_token)
          .with(token: token, scope: "Notifyd:MuteAuth")
          .returns(verification)

        user, data = UnsubscribeToken.new(:mute_auth).verify(token)

        refute_nil user
        refute_nil data
      end
    end

    test "signed tokens can be verified" do
      user = create(:user)
      payload = { "hello" => "world" }

      token = Notifyd::UnsubscribeToken.new(:mute_auth).sign(user, payload)
      refute_nil token

      u, p = Notifyd::UnsubscribeToken.new(:mute_auth).verify(token)

      assert_equal user, u
      assert_equal payload, p
    end
  end
end
