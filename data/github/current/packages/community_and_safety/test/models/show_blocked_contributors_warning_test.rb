# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class ShowBlockedContributorsWarningTest < GitHub::TestCase
    test "defaults to true if no interaction setting relation exists" do
      user = create(:user)
      assert user.show_blocked_contributors_warning?
    end

    test "returns the value on the related interaction setting object" do
      user = create(:user)
      InteractionSetting.create!(user_id: user.id, show_blocked_contributors_warning: false)
      refute user.show_blocked_contributors_warning?
    end

    test "returns false for an organization" do
      org = create(:organization)
      refute org.show_blocked_contributors_warning?
    end
  end
end
