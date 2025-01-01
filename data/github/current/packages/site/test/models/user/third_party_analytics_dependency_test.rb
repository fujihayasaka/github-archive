# typed: true
# frozen_string_literal: true

require "test_helper"

class UserThirdPartyAnalyticsTest < GitHub::TestCase
  context "setting analytics tracking id" do
    if GitHub.enterprise?
      test "does not set a tracking id when user is created" do
        user = create(:user)

        assert_nil user.analytics_tracking_id
      end
    else
      test "sets a 32-character tracking id when user is created" do
        user = build(:user)

        assert_nil user.analytics_tracking_id

        user.save!

        refute_nil user.analytics_tracking_id
        assert_match(/\A[a-f0-9]+\Z/, user.analytics_tracking_id)
        assert_equal User::ThirdPartyAnalyticsDependency::ANALYTICS_TRACKING_ID_LENGTH, user.analytics_tracking_id.length
      end

      test "ensures the generated tracking id is unique" do
        existing_user = create(:user)

        User.stubs(:generate_analytics_tracking_id).
          returns(existing_user.analytics_tracking_id, SecureRandom.hex).
          at_least(2)

        new_user = create(:user)

        refute_equal existing_user.analytics_tracking_id, new_user.analytics_tracking_id
        refute_nil new_user.analytics_tracking_id
      end
    end
  end

  context "#identify_to_google_analytics?" do
    if GitHub.enterprise?
      test "returns false" do
        user = create(:user)

        refute_predicate user, :identify_to_google_analytics?
      end
    else
      test "returns true if user has an analytics tracking id" do
        user = create(:user)

        refute_nil user.analytics_tracking_id

        assert_predicate user, :identify_to_google_analytics?
      end

      test "returns false if user has no tracking id" do
        user = create(:user)
        user.update!(analytics_tracking_id: nil)

        assert_nil user.analytics_tracking_id

        refute_predicate user, :identify_to_google_analytics?
      end
    end
  end
end
