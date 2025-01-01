# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class ScientistTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @staff = create(:user, :staff)
      @issue_comment = create(:issue_comment)
    end

    setup do
      GitHub.flipper[:publish_events_to_notifyd].enable
    end

    context ".notifyd_enabled?" do
      if GitHub.enterprise?
        test "is always false for enterprise" do
          GitHub.flipper[:notifyd_issue_comment_notify].enable

          refute Notifyd::Scientist.notifyd_enabled?
        end
      else
        test "false if publish_events_to_notifyd feature flag disabled" do
          GitHub.flipper[:publish_events_to_notifyd].disable

          refute Notifyd::Scientist.notifyd_enabled?
        end

        test "true if publish_events_to_notifyd feature flag enabled" do
          GitHub.flipper[:publish_events_to_notifyd].enable

          assert Notifyd::Scientist.notifyd_enabled?
        end
      end
    end
  end
end
