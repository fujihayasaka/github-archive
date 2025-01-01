# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.enterprise?
  class SamlSessionTest < GitHub::TestCase

    test "active" do
      user = create(:user)
      session = SAML::Session.create!(user: user, expires_at: 5.minutes.from_now)
      active = SAML::Session.active
      assert_same_elements active, [session]
    end

    test "expired" do
      user = create(:user)
      session = SAML::Session.create!(user: user, expires_at: 5.minutes.ago)
      expired = []
      # Expired returns a BatchEnumerator object
      SAML::Session.expired.each_record { |s| expired << s }
      assert_includes expired, session
    end

    test "revokes user session when destroyed" do
      user = create(:user)
      key, hashed_key = UserSession.random_key_pair
      user_session = create(:user_session, user: user, hashed_key: hashed_key)
      session = SAML::Session.new(user: user, expires_at: Time.now)

      session.destroy
      user_session.reload
      assert user_session.revoked?
      assert_equal "saml_expired", user_session.revoked_reason
    end
  end
end
