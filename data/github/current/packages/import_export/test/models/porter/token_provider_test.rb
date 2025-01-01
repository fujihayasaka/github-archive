# typed: true
# frozen_string_literal: true

require "test_helper"

class PorterTokenProviderTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @porter = create :oauth_application
    GitHub.porter_app_id = @porter.id
  end

  def provider
    Porter::TokenProvider.new(application_id: @porter.id)
  end

  test "creates a token" do
    token = provider.get_token(@user)

    refute_nil token
    access = OauthAccess.with_active_token(token)
    assert_equal @user, access.user
  end

  test "finds an existing token" do
    existing_token = create(:oauth_access, user: @user, application: @porter)

    token = provider.get_token(@user)

    assert_nil token
  end

  test "uses the application's scopes by default" do
    @porter.scopes = %w[repo user workflow]
    @porter.save!

    token = provider.get_token(@user)

    access = OauthAccess.with_active_token(token)
    assert_equal %w[repo user workflow], access.scopes
  end
end
