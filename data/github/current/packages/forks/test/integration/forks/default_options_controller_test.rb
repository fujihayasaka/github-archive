# typed: true
# frozen_string_literal: true

require "test_helper"

class Forks::DefaultOptionsControllerHttpTest < GitHub::IntegrationTestCase

  fixtures do
    @user = create(:user, login: "testuser")
    @repo = create(:repository, owner: @user)
  end

  def save_options_payload(**overrides)
    {
      sort_by: "stargazer_counts",
      include: "active,archived,inactive",
      period: "5y",
    }.merge(overrides)
  end

  def assert_user_default_options_equal(**overrides)
    expected = save_options_payload(**overrides)
    assert_equal expected, parsed_user_settings
  end

  def refute_user_default_options_equal(**overrides)
    expected = save_options_payload(**overrides)
    refute_equal expected, parsed_user_settings
  end

  def save_options_path
    "/#{@repo.name_with_display_owner}/forks/default-options"
  end

  def parsed_user_settings
    JSON::parse(@user.reload.user_settings_record.get(:forks_view_default_options)).symbolize_keys
  end

  def post_save_default_options(**options)
    post save_options_path, params: save_options_payload(**options), headers: { accept: "application/json" }
  end

  context "#update" do
    context "when no user is logged in" do
      test "it returns 404" do
        post_save_default_options

        assert_response_not_found
      end
    end

    context "when a user is logged in" do
      context "and the user has no pre-existing settings" do
        test "the settings are created and saved" do
          refute UserSettings.where(user_id: @user.id).exists?

          as @user
          post_save_default_options

          assert_response_success
          assert UserSettings.where(user_id: @user.id).reload.exists?
          assert_user_default_options_equal
        end
      end

      context "and the user has pre-existing settings" do
        test "the settings are overwritten" do
          settings = T.cast(UserSettings.create_or_find_by(user_id: @user.id), T.untyped)
          settings.set!(:forks_view_default_options, "{\"thing\": \"other_thing\"}")
          refute_user_default_options_equal

          as @user
          post_save_default_options

          assert_response_success
          assert_user_default_options_equal
        end
      end

      context "and the user provides a junk payload" do
        test "only default and correct options are saved" do
          as @user
          post_save_default_options(sort_by: "smileys", include: "; DROP TABLE USERS,active")

          assert_response_success
          assert_user_default_options_equal(
            include: "active",
            sort_by: "stargazer_counts",
            period: "5y",
          )
        end
      end
    end
  end
end
