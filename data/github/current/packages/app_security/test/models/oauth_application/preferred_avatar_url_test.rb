# typed: true
# frozen_string_literal: true

require "test_helper"

class PreferredAvatarUrlTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "#preferred_avatar_url" do
    if TestEnv.test_in_multitenancy_mode?
      test "contains auth token in Proxima" do
        app = create :oauth_application, user: @user
        PrimaryAvatar.set(create(:avatar, owner: app, uploader: app.user), app.user)

        uri = URI.parse(app.preferred_avatar_url)
        assert_match /\/avatars\/oa\/#{app.id}$/,  uri.path
        assert_match /token=#{multi_tenant_avatar_token}/, uri.query
      end

      test "returns canonical avatar URL when the app is synchronized" do
        app = create(:oauth_application)
        create(:proxima_app_synchronization, local_app: app, canonical_avatar_url: "https://example.com/some-avatar")

        assert_equal "https://example.com/some-avatar", app.preferred_avatar_url
      end
    else
      test "does not contain auth token in Dotcom/GHES" do
        app = create :oauth_application, user: @user
        PrimaryAvatar.set(create(:avatar, owner: app, uploader: app.user), app.user)

        uri = URI.parse(app.preferred_avatar_url)
        assert_match /\/avatars\/oa\/#{app.id}$/,  uri.path
        refute_match /token=/, uri.query
      end

      # Ensure there's no way synchronized avatars can ever be used on Dotcom
      test "returns the primary avatar URL when the app is synchronized" do
        app = create(:oauth_application, user: @user)
        create(:proxima_app_synchronization, local_app: app, canonical_avatar_url: "https://example.com/some-avatar")
        PrimaryAvatar.set(create(:avatar, owner: app, uploader: app.user), app.user)

        uri = URI.parse(app.preferred_avatar_url)
        assert_match /\/avatars\/oa\/#{app.id}$/,  uri.path
        refute_match /some-avatar/, uri.path
      end
    end
  end
end
