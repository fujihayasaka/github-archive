# typed: true
# frozen_string_literal: true

require "test_helper"

class OauthApplicationApprovalTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @app = create(:oauth_application)
  end

  setup do
    @approval = build(:oauth_application_approval, organization: @org, application: @app, state: :blocked)
  end

  context "when blocking an app" do
    test "cannot block app when org first-party OAP is disabled" do
      @org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(false)

      refute @approval.valid?
      assert @approval.errors[:application].any?

      expected_error = "Application cannot be blocked"
      assert_includes @approval.errors.full_messages, expected_error
    end

    test "cannot block a third-party app" do
      # Considered a third-party app because it is not owned by GitHub.
      @app.stubs(:github_owned?).returns(false)

      refute @approval.valid?
      assert @approval.errors[:application].any?

      expected_error = "Application cannot be blocked"
      assert_includes @approval.errors.full_messages, expected_error
    end

    test "blocks app" do
      @org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)
      @app.stubs(:blockable_client_app?).returns(true)

      assert @approval.valid?
      refute @approval.errors[:application].any?
    end
  end
end
