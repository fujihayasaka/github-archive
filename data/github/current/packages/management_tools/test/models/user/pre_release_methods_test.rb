# typed: true
# frozen_string_literal: true

require "test_helper"

class UserPreReleaseMethodsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "#new_prerelease_features?" do
    if GitHub.enterprise?
      test "returns false if Enterprise" do
        feature = create(:feature_with_flipper, published_at: 3.days.ago)
        feature.flipper_feature.enable(@user)
        refute @user.new_prerelease_features?
      end
    end

    test "returns false if all features are already seen" do
      feature = create(:feature_with_flipper, published_at: 3.days.ago)
      feature.flipper_feature.enable(@user)
      feature.user_seen_features.create_or_find_by(user: @user)

      refute @user.new_prerelease_features?
    end

    test "returns false if the unseen feature is unpublished" do
      feature = create(:feature_with_flipper, published_at: nil)
      feature.flipper_feature.enable(@user)

      refute @user.new_prerelease_features?
    end

    test "returns false if the unseen feature is not enabled for user" do
      create(:feature_with_flipper, published_at: 3.days.ago)

      refute @user.new_prerelease_features?
    end

    unless GitHub.enterprise?
      test "returns true if the unseen feature is published" do
        feature = create(:feature_with_flipper, published_at: 3.days.ago)
        feature.flipper_feature.enable(@user)

        assert @user.new_prerelease_features?
      end
    end
  end

  context "#unseen_prerelease_features" do
    if GitHub.enterprise?
      test "returns an empty array if Enterprise" do
        feature_one = create(:feature_with_flipper)
        feature_one.flipper_feature.enable(@user)

        feature_two = create(:feature_with_flipper)
        feature_two.flipper_feature.enable(@user)
        feature_two.user_seen_features.create(user: @user)

        assert_equal [], @user.unseen_prerelease_features
      end
    end

    unless GitHub.enterprise?
      test "returns visible features the user has not seen" do
        feature_one = create(:feature_with_flipper)
        feature_one.flipper_feature.enable(@user)

        feature_two = create(:feature_with_flipper)
        feature_two.flipper_feature.enable(@user)
        feature_two.user_seen_features.create(user: @user)

        assert_equal [feature_one], @user.unseen_prerelease_features
      end
    end

    test "doesn't return features that are not visible to the user" do
      feature_one = create(:feature_with_flipper)

      feature_two = create(:feature_with_flipper)
      feature_two.flipper_feature.enable(@user)
      feature_two.user_seen_features.create(user: @user)

      assert_equal [], @user.unseen_prerelease_features
    end
  end

  context "#prerelease_feature_enrollments" do
    unless TestEnv.test_all_features?
      test "returns a users feature enrollment statues" do
        feature_one = create(:feature_with_flipper)
        feature_one.flipper_feature.enable(@user)
        feature_one.enroll(@user)

        feature_two = create(:feature_with_flipper)
        feature_two.flipper_feature.enable(@user)
        feature_two.unenroll(@user)

        feature_three = create(:feature_with_flipper, :opt_in)
        feature_three.flipper_feature.enable(@user)

        assert_equal @user.prerelease_feature_enrollments, {
          feature_one.id => {
            enabled: true,
            opted_out: false,
          },
          feature_two.id => {
            enabled: false,
            opted_out: true,
          },
          feature_three.id => {
            enabled: false,
          },
        }
      end
    end

    test "handles a user with an enrollment that is not currently visible" do
      feature_one = create(:feature_with_flipper)
      feature_one.flipper_feature.enable(@user)
      feature_one.enroll(@user)
      feature_one.flipper_feature.disable

      feature_two = create(:feature_with_flipper)
      feature_two.flipper_feature.enable(@user)
      feature_two.unenroll(@user)

      assert_equal @user.prerelease_feature_enrollments, {
        feature_two.id => {
          enabled: false,
          opted_out: true,
        },
      }
    end
  end
end
