# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationAvatarTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner

    @user = create(:user)
    @other_user = create(:user)
    @member = create(:user)
    @org = create(:organization)
    @admin = @org.admins.first
    @org.add_member(@member)

    @user_integration = create(:integration, owner: @user, public: false)
    @org_integration = create(:integration, owner: @org, public: false)
    @other_integration = create(:integration)
  end

  context "Integration#avatar_editable_by?" do
    test "is editable as the owner of the integration" do
      assert @user_integration.avatar_editable_by?(@user), "owner should be able to edit the avatar"
    end

    test "is not editable as a random user" do
      refute @user_integration.avatar_editable_by?(@other_user), "random user should not be able to edit the avatar"
    end

    test "is editable as an admin of the owning organization" do
      assert @org_integration.avatar_editable_by?(@admin), "org admin should be able to edit the avatar"
    end

    test "is not editable as a member of the owning organization" do
      refute @org_integration.avatar_editable_by?(@member), "org member should not be able to edit the avatar"
    end

    test "is editable as a Apps manager of _all_ apps belonging to the owning organization" do
      manager = create(:user)
      @org.add_member(manager)

      assert_predicate ::Permissions::Granter.grant(
        action: :manage_all_apps,
        actor_id: manager.id,
        subject_id: @org.id,
        entry_point: :test_case
      ), :success?

      assert @org_integration.avatar_editable_by?(manager), "all Apps manager should be able to edit the avatar"
    end

    test "is editable as an Apps manager of the integration" do
      manager = create(:user)
      @org.add_member(manager)

      assert_predicate ::Permissions::Granter.grant(
        action: :manage_app,
        actor_id: manager.id,
        subject_id: @org_integration.id,
        entry_point: :test_case
      ), :success?

      assert @org_integration.avatar_editable_by?(manager), "App manager should be able to edit the avatar"
    end
  end

  context "#preferred_bgcolor" do
    test "returns bgcolor from Marketplace listing if it exists and is approved" do
      app = create(:integration, bgcolor: "ff00ff")
      listing = create(:marketplace_listing, :verified, listable: app, bgcolor: "faeef0")
      assert_equal listing.bgcolor, app.preferred_bgcolor
    end

    test "returns bgcolor from integration when no Marketplace listing but has custom avatar" do
      app = create(:integration, bgcolor: "ff00ff")
      org_admin = app.owner.admins.first
      PrimaryAvatar.set(create(:avatar, owner: app, uploader: org_admin), org_admin)

      # Refetch Integration to dump memoized primary_avatar_path
      app = Integration.find(app.id)

      assert_equal app.bgcolor, app.preferred_bgcolor
    end

    test "returns background color from identicon when no custom avatar" do
      assert_equal @other_integration.identicon.background_color,
        @other_integration.preferred_bgcolor
    end

    if TestEnv.test_in_multitenancy_mode?
      test "returns background color from the app when synchronized" do
        app = create(:integration, bgcolor: "ff00ff") # #ff00ff will never appear as an Identicon background color
        create(:proxima_app_synchronization, local_app: app)

        assert_equal "ff00ff", app.preferred_bgcolor
      end
    end
  end

  context "#primary_avatar_path" do
    context "integration has a primary avatar" do
      test "is under the /in/ directory" do
        integration_owner = @user_integration.owner.admins.first

        avatar = create(:avatar, owner: @user_integration, uploader: integration_owner)

        assert_equal @user_integration, avatar.owner
        PrimaryAvatar.set(avatar, integration_owner)

        assert_equal "/in/#{@user_integration.id}", @user_integration.primary_avatar_path
      end

      test "intruments updating the primary avatar" do
        events = subscribe "profile_picture.update"
        integration_owner = @user_integration.owner.admins.first
        avatar = create(:avatar, owner: @user_integration, uploader: integration_owner)
        PrimaryAvatar.set(avatar, integration_owner)

        expected_payload = {
          integration: @user_integration.name,
          integration_id: @user_integration.id,
          owner: @user_integration.name,
          owner_id: avatar.owner.id,
          actor: integration_owner.name,
          actor_id: integration_owner.id,
          type: "Integration",
        }

        assert event = events.pop, "an event was expected"
        assert_equal "profile_picture.update", event.name
        assert_equal expected_payload, event.payload
      end
    end

    context "integration does not have a primary avatar" do
      test "has the same primary_avatar_path as the owner" do
        assert_equal @user_integration.owner.primary_avatar_path, @user_integration.primary_avatar_path
      end
    end
  end

  context "#preferred_avatar_url" do
    if TestEnv.test_in_multitenancy_mode?
      test "returns canonical avatar URL when the app is synchronized" do
        app = create(:integration)
        create(:proxima_app_synchronization, local_app: app, canonical_avatar_url: "https://example.com/some-avatar")

        assert_equal "https://example.com/some-avatar", app.preferred_avatar_url
      end
    else
      # Ensure there's no way synchronized avatars can ever be used on Dotcom
      test "returns the primary avatar URL when the app is synchronized" do
        app = create(:integration, owner: @user)
        create(:proxima_app_synchronization, local_app: app, canonical_avatar_url: "https://example.com/some-avatar")
        PrimaryAvatar.set(create(:avatar, owner: app, uploader: @user), @user)

        uri = URI.parse(app.preferred_avatar_url)
        assert_match /\/avatars\/in\/#{app.id}$/,  uri.path
        refute_match /some-avatar/, uri.path
      end
    end
  end

end
