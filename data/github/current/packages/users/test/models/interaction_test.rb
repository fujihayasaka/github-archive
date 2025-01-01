# typed: true
# frozen_string_literal: true

require "test_helper"

if Interaction.enabled?
  class InteractionModelTest < GitHub::TestCase
    fixtures do
      @nointeraction_user = create(:user, created_at: 1.week.ago)

      # A user with an existing interaction record
      @user = create(:user, created_at: 1.week.ago)
      @user.interaction = create :interaction

      @paying_user = create(:user, plan: "medium")
    end

    test "tracks last activity for a user without interactions" do
      assert_nil @nointeraction_user.interaction
      Interaction.track_active_session(@nointeraction_user)
      assert_equal 1, @nointeraction_user.interaction.active_sessions
      refute_nil @nointeraction_user.interaction.last_active_session_at
    end

    test "tracks last activity for a user with interaction" do
      refute_nil @user.interaction
      assert_difference "@user.interaction.active_sessions", 1 do
        Interaction.track_active_session(@user)
      end
    end

    test "only tracks mac usage once per day" do
      assert_difference "@user.interaction.mac_active_sessions", 1 do
        assert Interaction.track_mac(@user)
      end
      assert_no_difference "@user.interaction.mac_active_sessions" do
        assert_nil Interaction.track_mac(@user)
      end

      @user.interaction.last_mac_active_session = 1.day.ago - 1.minute
      @user.interaction.save

      assert_difference "@user.interaction.mac_active_sessions", 1 do
        assert Interaction.track_mac(@user)
      end
    end

    test "only tracks windows usage once per day" do
      assert_difference "@user.interaction.windows_active_sessions", 1 do
        assert Interaction.track_windows(@user)
      end
      assert_no_difference "@user.interaction.windows_active_sessions" do
        assert_nil Interaction.track_windows(@user)
      end

      @user.interaction.last_windows_active_session = 1.day.ago - 1.minute
      @user.interaction.save

      assert_difference "@user.interaction.windows_active_sessions", 1 do
        assert Interaction.track_windows(@user)
      end
    end

    test "only tracks Desktop Windows usage once per day" do
      assert_difference "@user.interaction.windows_desktop_active_sessions", 1 do
        assert Interaction.track_desktop_windows(@user)
      end
      assert_no_difference "@user.interaction.windows_desktop_active_sessions" do
        assert_nil Interaction.track_desktop_windows(@user)
      end

      @user.interaction.last_windows_desktop_active_session_at = 1.day.ago - 1.minute
      @user.interaction.save

      assert_difference "@user.interaction.windows_desktop_active_sessions", 1 do
        assert Interaction.track_desktop_windows(@user)
      end
    end

    test "only tracks Desktop Mac usage once per day" do
      assert_difference "@user.interaction.mac_desktop_active_sessions", 1 do
        assert Interaction.track_desktop_mac(@user)
      end
      assert_no_difference "@user.interaction.mac_desktop_active_sessions" do
        assert_nil Interaction.track_desktop_mac(@user)
      end

      @user.interaction.last_mac_desktop_active_session_at = 1.day.ago - 1.minute
      @user.interaction.save

      assert_difference "@user.interaction.mac_desktop_active_sessions", 1 do
        assert Interaction.track_desktop_mac(@user)
      end
    end

    test "tracks mac usage with timestamp" do
      assert_nil @user.interaction.last_mac_active_session
      assert Interaction.track_mac(@user)
      @user.reload
      assert @user.interaction.last_mac_active_session?
      assert_equal @user.interaction.last_active_at, @user.interaction.last_mac_active_session
    end

    test "tracks windows usage with timestamp" do
      assert_nil @user.interaction.last_windows_active_session
      assert Interaction.track_windows(@user)
      @user.reload
      assert @user.interaction.last_windows_active_session?
      assert_equal @user.interaction.last_active_at, @user.interaction.last_windows_active_session
    end

    test "tracks Desktop Windows usage with timestamp" do
      assert_nil @user.interaction.last_windows_desktop_active_session_at
      assert Interaction.track_desktop_windows(@user)
      @user.reload
      assert @user.interaction.last_windows_desktop_active_session_at?
      assert_equal @user.interaction.last_active_at, @user.interaction.last_windows_desktop_active_session_at
    end

    test "tracks Desktop Mac usage with timestamp" do
      assert_nil @user.interaction.last_mac_desktop_active_session_at
      assert Interaction.track_desktop_mac(@user)
      @user.reload
      assert @user.interaction.last_mac_desktop_active_session_at?
      assert_equal @user.interaction.last_active_at, @user.interaction.last_mac_desktop_active_session_at
    end

    test "does not track activity if interaction tracking is disabled" do
      Interaction.stubs(:enabled?).returns(false)
      assert_no_difference "Interaction.count" do
        Interaction.track_active_session(@nointeraction_user)
      end
      assert_nil @user.interaction.last_issue_at
      Interaction.track_issue(@user)
      assert_nil @user.interaction.reload.last_issue_at
    end

    test "identifies if interaction has been with any content areas" do
      Interaction.track_active_session(@user)
      refute @user.interaction.been_with_any_content?

      Interaction.track_pull_request(@user)
      assert @user.interaction.been_with_any_content?
    end
  end
end
