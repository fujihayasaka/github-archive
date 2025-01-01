# typed: true
# frozen_string_literal: true

require "test_helper"

class CreatedApplicationsLimitValidatorTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @integration = create(:integration, owner: @user)
    @oauth_app = create(:oauth_application, user: @user)
    @too_many_apps_error = CreatedApplicationsLimitValidator::USER_HAS_CREATED_TOO_MANY_APPS_MESSAGE
  end

  context Integration do
    test "does not limit github apps creation on enterprise", enterprise_only: true do
      GitHub::ApplicationsCreationLimit.stub_const(:DEFAULT_MAX_APPLICATIONS_CREATION_LIMIT, 1) do
        create(:integration, owner: @user)
      end

      assert_equal 2, @user.integrations.count
    end

    test "it respects custom user limits" do
      @user.set_custom_applications_limit(@integration, 10)

      GitHub::ApplicationsCreationLimit.stub_const(:DEFAULT_MAX_APPLICATIONS_CREATION_LIMIT, 1) do
        create(:integration, owner: @user)
      end

      assert_equal 2, @user.integrations.count
    end

    test "it restricts apps creation if above the limit", skip_enterprise: true do
      assert_predicate @user.integrations, :any?

      GitHub::ApplicationsCreationLimit.stub_const(:DEFAULT_MAX_APPLICATIONS_CREATION_LIMIT, 1) do
        integration = build(:integration, owner: @user)
        refute integration.valid?
        assert_equal [@too_many_apps_error], integration.errors[:user]
      end

      # with custom limits
      @user.set_custom_applications_limit(@integration, 1)
      integration = build(:integration, owner: @user)
      refute integration.valid?
      assert_equal [@too_many_apps_error], integration.errors[:user]
    end

    test "it allows users above the limit to update existing apps" do
      GitHub::ApplicationsCreationLimit.stub_const(:DEFAULT_MAX_APPLICATIONS_CREATION_LIMIT, 0) do
        @integration.bgcolor = "ff00ff"
        @integration.save!
      end
    end
  end

  context OauthApplication do
    if GitHub.enterprise?
      test "does not limit oauth apps creation on enterprise" do
        GitHub::ApplicationsCreationLimit.stub_const(:DEFAULT_MAX_APPLICATIONS_CREATION_LIMIT, 1) do
          create(:oauth_application, user: @user)
        end

        assert_equal 2, @user.oauth_applications.count
      end
    end

    test "it respects custom user limits" do
      @user.set_custom_applications_limit(@oauth_app, 10)

      GitHub::ApplicationsCreationLimit.stub_const(:DEFAULT_MAX_APPLICATIONS_CREATION_LIMIT, 1) do
        create(:oauth_application, user: @user)
      end

      assert_equal 2, @user.oauth_applications.count
    end

    test "it restricts apps creation if above the limit", skip_enterprise: true do
      assert_predicate @user.oauth_applications, :any?

      GitHub::ApplicationsCreationLimit.stub_const(:DEFAULT_MAX_APPLICATIONS_CREATION_LIMIT, 1) do
        app = build(:oauth_application, user: @user)
        refute app.valid?
        assert_equal [@too_many_apps_error], app.errors[:user]
      end

      # with custom limpits ...
      @user.set_custom_applications_limit(@oauth_app, 1)
      app = build(:oauth_application, user: @user)
      refute app.valid?
      assert_equal [@too_many_apps_error], app.errors[:user]
    end

    test "it allows users above the limit to update existing apps" do
      GitHub::ApplicationsCreationLimit.stub_const(:DEFAULT_MAX_APPLICATIONS_CREATION_LIMIT, 0) do
        @oauth_app.bgcolor = "ff00ff"
        @oauth_app.save!
      end
    end
  end
end
