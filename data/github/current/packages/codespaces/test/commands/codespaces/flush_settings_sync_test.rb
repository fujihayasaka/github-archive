# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class FlushSettingsSyncTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @user_session = create(:user_session, user: @user)
      make_trusted_oauth_apps_owner
      @integration = create(:codespaces_integration)
    end

    context "flush settings sync" do
      test "do not attempt to flush if the user does not have any codespaces" do
        stub_request(
          :post,
          Codespaces::SettingsSyncClient::STABLE_SETTINGS_SYNC_URL + "auth/reset"
        ).to_return(
          status: 200,
          body: "[]"
        )
        stub_request(
          :post,
          Codespaces::SettingsSyncClient::INSIDERS_SETTINGS_SYNC_URL + "auth/reset"
        ).to_return(
          status: 200,
          body: "[]"
        )
        stub_request(
          :post,
          Codespaces::SettingsSyncClient::TEST_SETTINGS_SYNC_URL + "auth/reset"
        ).to_return(
          status: 200,
          body: "[]"
        )
        assert_nothing_raised { Codespaces::FlushSettingsSync.call(user: @user) }
        assert_not_requested :post, Codespaces::SettingsSyncClient::STABLE_SETTINGS_SYNC_URL + "auth/reset"
        assert_not_requested :post, Codespaces::SettingsSyncClient::INSIDERS_SETTINGS_SYNC_URL + "auth/reset"
        assert_not_requested :post, Codespaces::SettingsSyncClient::TEST_SETTINGS_SYNC_URL + "auth/reset"
      end

      test "do not flush from test server if FF off" do
        codespace = create(:codespace, owner: @user)

        stub_request(
          :post,
          Codespaces::SettingsSyncClient::STABLE_SETTINGS_SYNC_URL + "auth/reset"
        ).to_return(
          status: 200,
          body: "[]"
        )
        stub_request(
          :post,
          Codespaces::SettingsSyncClient::INSIDERS_SETTINGS_SYNC_URL + "auth/reset"
        ).to_return(
          status: 200,
          body: "[]"
        )
        stub_request(
          :post,
          Codespaces::SettingsSyncClient::TEST_SETTINGS_SYNC_URL + "auth/reset"
        ).to_return(
          status: 200,
          body: "[]"
        )
        assert_nothing_raised { Codespaces::FlushSettingsSync.call(user: @user) }
        assert_requested :post, Codespaces::SettingsSyncClient::STABLE_SETTINGS_SYNC_URL + "auth/reset"
        assert_requested :post, Codespaces::SettingsSyncClient::INSIDERS_SETTINGS_SYNC_URL + "auth/reset"
        assert_not_requested :post, Codespaces::SettingsSyncClient::TEST_SETTINGS_SYNC_URL + "auth/reset"
      end
    end
  end
end
