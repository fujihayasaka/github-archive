# typed: true
# frozen_string_literal: true
require "test_helper"

module Codespaces
  class SettingsTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
    end

    context "validating a new Codespaces::Settings" do
      test "vscode_channel is a valid option" do
        setting = Codespaces::Settings.new(user: @user)
        setting.vscode_channel = "bvsdfsdf"
        refute setting.valid?
        assert_equal ["must be a valid channel"], setting.errors[:vscode_channel]
      end

      test "user is present" do
        assert_raises Codespaces::Settings::UserMissing do
          Codespaces::Settings.new(user: create(:repository))
        end
      end

      test "validates preferred editor" do
        settings = Codespaces::Settings.new(user: @user)
        settings.preferred_editor = "not_a_valid_editor"
        refute settings.valid?
        assert_equal ["is not a valid editor"], settings.errors[:preferred_editor]
      end

      test "validates preferred host image" do
        settings = Codespaces::Settings.new(user: @user)
        settings.preferred_host_image = "invalid_image"
        refute settings.valid?
        assert_equal ["is not a valid host image"], settings.errors[:preferred_host_image]
      end

      test "validates default location" do
        settings = Codespaces::Settings.new(user: @user)
        settings.default_location = "TheMoon"
        refute settings.valid?
        assert_equal ["must be a valid location"], settings.errors[:default_location]
      end

      test "validates default idle timeout" do
        settings = Codespaces::Settings.new(user: @user)
        settings.default_idle_timeout = "1000"
        refute settings.valid?
        assert_equal ["must be an integer between #{Codespaces::Vscs::MIN_IDLE_TIME / 1.minute} and #{Codespaces::Vscs::MAX_IDLE_TIME / 1.minute} minutes"], settings.errors[:default_idle_timeout]
      end

      test "validates telemetry level" do
        settings = Codespaces::Settings.new(user: @user)
        settings.telemetry_level = "df"
        refute settings.valid?
        assert_equal ["must be a valid telemetry level"], settings.errors[:telemetry_level]
      end
    end

    test "default settings" do
      settings = Codespaces::Settings.new(user: @user)
      assert_equal "stable", settings.vscode_channel
      assert_equal "web", settings.preferred_editor
      assert_equal "all", settings.telemetry_level
      assert_nil settings.default_location
      assert_nil settings.default_idle_timeout
    end

    context "update method" do
      test "update the vscode channel and disregards un-needed data" do
        settings = Codespaces::Settings.new(user: @user)
        settings.update({ vscode_channel: "insider", blah: "blah" })
        settings2 = Codespaces::Settings.for_user(@user)
        assert_equal "insider", settings2.vscode_channel
      end

      test "update the preferred editor setting" do
        settings = Codespaces::Settings.new(user: @user)
        settings.update({ preferred_editor: "vscode", blah: "blah" })
        settings2 = Codespaces::Settings.for_user(@user)
        assert_equal "vscode", settings2.preferred_editor
      end

      test "update the default location setting" do
        settings = Codespaces::Settings.new(user: @user)
        settings.update({ default_location: "EastUs", blah: "blah" })
        settings2 = Codespaces::Settings.for_user(@user)
        assert_equal "EastUs", settings2.default_location
      end

      test "update the default idle timeout setting" do
        settings = Codespaces::Settings.new(user: @user)
        settings.update({ default_idle_timeout: "120", blah: "blah" })
        settings2 = Codespaces::Settings.for_user(@user)
        assert_equal 120, settings2.default_idle_timeout
      end

      test "update telemetry setting" do
        settings = Codespaces::Settings.new(user: @user)
        settings.update({ telemetry_level: "crash" })
        settings2 = Codespaces::Settings.new(user: @user)
        assert_equal "crash", settings2.telemetry_level
      end

      test "changes keeps track of the changes from this write" do
        settings = Codespaces::Settings.new(user: @user)
        settings.write_attributes({ vscode_channel: "insider", preferred_editor: "vscode", default_location: "EastUs" })
        assert_equal settings.changes, {}
        settings.save
        assert_equal settings.changes, { vscode_channel: "insider", preferred_editor: "vscode", default_location: "EastUs" }
        settings.vscode_channel = "stable"
        settings.save
        assert_equal settings.changes, { vscode_channel: "stable" }
        settings.update({ preferred_editor: "web" })
        assert_equal settings.changes, { preferred_editor: "web" }
        settings.default_location = "WestUs2"
        settings.save
        assert_equal settings.changes, { default_location: "WestUs2" }
      end
    end

    context "find for user" do
      test "creates default when missing" do
        settings = Codespaces::Settings.for_user(@user)
        assert_equal "stable", settings.vscode_channel
      end

      test "finds previous settings when exists" do
        Codespaces::Settings.create(user: @user).update({ vscode_channel: "insider" })
        settings = Codespaces::Settings.for_user(@user)
        assert_equal "insider", settings.vscode_channel
      end
    end

    context "prefers non web editor" do
      test "vscode web is web editor" do
        Codespaces::Settings.create(user: @user).update({ preferred_editor: Codespaces::Settings::PREFERRED_EDITOR_VSCODE_WEB })
        settings = Codespaces::Settings.for_user(@user)
        assert settings.valid?
        refute settings.prefers_non_web_editor?
      end

      test "jupyter is web editor" do
        Codespaces::Settings.create(user: @user).update({ preferred_editor: Codespaces::Settings::PREFERRED_EDITOR_JUPYTER })
        settings = Codespaces::Settings.for_user(@user)
        assert settings.valid?
        refute settings.prefers_non_web_editor?
      end

      test "vscode is not a web editor" do
        Codespaces::Settings.create(user: @user).update({ preferred_editor: Codespaces::Settings::PREFERRED_EDITOR_VSCODE })
        settings = Codespaces::Settings.for_user(@user)
        assert settings.valid?
        assert settings.prefers_non_web_editor?
      end

      test "jetbrains is not a web editor" do
        Codespaces::Settings.create(user: @user).update({ preferred_editor: Codespaces::Settings::PREFERRED_EDITOR_JETBRAINS })
        settings = Codespaces::Settings.for_user(@user)
        assert settings.valid?
        assert settings.prefers_non_web_editor?
      end
    end

    context "#vscode_settings" do
      test "uses the enterprise auth provider in multi-tenant enterprise mode" do
        on_multi_tenant_enterprise do
          settings = Codespaces::Settings.for_user(@user)

          assert_equal "github-enterprise", settings.vscode_settings[:defaultSettings][:"github.codespaces.authProvider"]
        end
      end

      test "sets the enterprise uri in multi-tenant enterprise mode" do
        on_multi_tenant_enterprise do
          settings = Codespaces::Settings.for_user(@user)
          vscode_settings = settings.vscode_settings

          refute_nil vscode_settings[:defaultSettings][:"github-enterprise.uri"]
          assert_equal GitHub.url, vscode_settings[:defaultSettings][:"github-enterprise.uri"]
        end
      end

      test "uses display_login", skip_enterprise: true do
        emu = create(:emu)
        business = emu.enterprise_managed_business

        on_multi_tenant_enterprise(tenant: business) do
          settings = Codespaces::Settings.for_user(emu)
          vscode_settings = settings.vscode_settings[:defaultAuthSessions].each do |session|
            assert_equal session[:account][:label], emu.display_login
          end
        end
      end

      test "uses the github auth provider by default" do
        settings = Codespaces::Settings.for_user(@user)

        assert_equal "github", settings.vscode_settings[:defaultSettings][:"github.codespaces.authProvider"]
      end

      test "does not set enterprise uri by default" do
        settings = Codespaces::Settings.for_user(@user)
        vscode_settings = settings.vscode_settings

        assert_nil vscode_settings[:defaultSettings][:"github-enterprise.uri"]
      end
    end
  end
end
