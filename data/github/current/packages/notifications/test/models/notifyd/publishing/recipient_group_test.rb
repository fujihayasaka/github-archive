# typed: false
# frozen_string_literal: true


require "test_helper"

module Notifyd::Publishing
  class RecipientGroupTest < GitHub::TestCase
    test "filters users that are not enabled for a flag" do
      feature_flag = GitHub.flipper[:some_feature_flag]
      permitted_users = create_list(:user, 2)
      denied_users = create_list(:user, 2)

      permitted_users.map { |user| feature_flag.enable(user) }

      potential_recipients = [
        { reason: "reason_1", users: permitted_users + denied_users },
        { reason: "reason_2", users: permitted_users + denied_users },
      ]

      actual_recipients = RecipientGroups
        .new(groups: potential_recipients)
        .filter_for(feature_flag: feature_flag)

      expected_recipients = [
        { reason: "reason_1", user_ids: permitted_users.map(&:id) },
        { reason: "reason_2", user_ids: permitted_users.map(&:id) },
      ]
      assert_equal expected_recipients, actual_recipients
    end
  end
end
