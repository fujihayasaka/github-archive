# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesSettingsSyncClientTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @user = create(:user)
    @repository = create(:repository)
    @codespace = create(:codespace, repository: @repository, owner: @user)
    @user_session = create(:user_session, user: @user)
    make_trusted_oauth_apps_owner
    @integration = create(:codespaces_integration)
  end

  context "settings sync client" do
    test "success on flushing" do
      codespace = @user.codespaces.first
      token = Codespaces::Tokens.mint_github_token(@user, codespace)

      client = Codespaces::SettingsSyncClient.new
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
      assert_nothing_raised { client.flush_user_cache(token) }
    end
  end

  test "raise proper error if insiders fails" do
    codespace = @user.codespaces.first
    token = Codespaces::Tokens.mint_github_token(@user, codespace)

    client = Codespaces::SettingsSyncClient.new
    # settings sync service always returns 200 whether it succeeds or not
    # but in case this changes in the future we should record it
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
      status: 500,
      body: "[]"
    )
    assert_raises_with_message(Codespaces::SettingsSyncClient::SettingSyncFlushError, "Fail to flush insiders settings sync") { client.flush_user_cache(token) }
  end

  test "raise proper error if stable fails" do
    codespace = @user.codespaces.first
    token = Codespaces::Tokens.mint_github_token(@user, codespace)

    client = Codespaces::SettingsSyncClient.new
    # settings sync service always returns 200 whether it succeeds or not
    # but in case this changes in the future we should record it
    stub_request(
      :post,
      Codespaces::SettingsSyncClient::STABLE_SETTINGS_SYNC_URL + "auth/reset"
    ).to_return(
      status: 500,
      body: "[]"
    )
    stub_request(
      :post,
      Codespaces::SettingsSyncClient::INSIDERS_SETTINGS_SYNC_URL + "auth/reset"
    ).to_return(
      status: 200,
      body: "[]"
    )
    assert_raises_with_message(Codespaces::SettingsSyncClient::SettingSyncFlushError, "Fail to flush stable settings sync") { client.flush_user_cache(token) }
  end
end
