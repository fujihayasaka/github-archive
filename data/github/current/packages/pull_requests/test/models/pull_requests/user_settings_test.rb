# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  class UserSettingsTest < GitHub::TestCase
    setup do
      @user = build_stubbed(:user, id: 1)
      @repo = build_stubbed(:repository, id: 2)

      UserSettings.new(@user, @repo).clear_default_pull_requests_to_draft
    end

    context "#default_pull_requests_to_draft?" do
      test "defaults to false when not set" do
        refute settings.default_pull_requests_to_draft?
      end

      test "persists the setting" do
        settings.set_default_pull_requests_to_draft(true)
        assert settings.default_pull_requests_to_draft?

        settings.set_default_pull_requests_to_draft(false)
        refute settings.default_pull_requests_to_draft?
      end

      test "clears the setting" do
        settings.set_default_pull_requests_to_draft(true)
        assert settings.default_pull_requests_to_draft?

        settings.clear_default_pull_requests_to_draft
        refute settings.default_pull_requests_to_draft?
      end

      test "writes to the issues-pull-requests KV store" do
        new_key = "pull_requests/default_to_draft/user#{@user.id}"

        settings.set_default_pull_requests_to_draft(true)

        assert PullRequests::KV.for_repository(@repo).exists(new_key).value!

        settings.set_default_pull_requests_to_draft(false)

        refute PullRequests::KV.for_repository(@repo).exists(new_key).value!
      end
    end

    private

    sig { returns(PullRequests::UserSettings) }
    def settings = UserSettings.new(@user, @repo)
  end
end
