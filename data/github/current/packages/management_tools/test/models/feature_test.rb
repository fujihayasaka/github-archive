# typed: true
# frozen_string_literal: true

require "test_helper"

class FeatureTest < GitHub::TestCase
  fixtures do
    @opt_in = create(:feature, :opt_in)
    @opt_out = create(:feature, :opt_out)
    @prerelease = create(:feature_with_flipper)
    @user = create(:user)
  end

  test "requires a unique public name" do
    feature = create(:feature, public_name: "Related Issues")
    dup = Feature.new(public_name: "Related Issues")

    refute_predicate dup, :valid?
    assert dup.errors.include?(:public_name)
  end

  test "rejects a public name containing emoji" do
    feature = build(:feature, public_name: "🐹")

    refute_predicate feature, :valid?
    assert feature.errors.include?(:public_name)
  end

  test "requires a unique slug" do
    feature = create(:feature, slug: "related-issues")
    dup = Feature.new(slug: "related-issues")

    refute_predicate dup, :valid?
    assert dup.errors.include?(:slug)
  end

  test "rejects a slug containing emoji" do
    feature = build(:feature, slug: "🐹")

    refute_predicate feature, :valid?
    assert feature.errors.include?(:slug)
  end

  test "requires a valid slug" do
    ["audit log", "auditlog!", "auditlog?"].each do |slug|
      feature = build(:feature, slug: slug)
      refute feature.valid?, "#{slug} should be an invalid slug"
      assert_equal ["is invalid"], feature.errors[:slug]
    end

    %w[auditlog audit-log audit_log].each do |slug|
      feature = build(:feature, slug: slug)
      assert feature.valid?, "#{slug} should be a valid slug"
    end
  end

  test "returns UTF-8 encoded description" do
    invalid = "This is a bad\u2028\u2028description".b
    assert invalid.encoding == ::Encoding::ASCII_8BIT
    feature = build(:feature, description: invalid)
    assert feature.description.encoding == ::Encoding::UTF_8
    assert_equal feature.description, invalid.dup.force_encoding(::Encoding::UTF_8).scrub!
  end

  test "only one Feature per FlipperFeature" do
    dup = Feature.new(flipper_feature: @prerelease.flipper_feature)

    refute_predicate dup, :valid?
    assert dup.errors.include?(:flipper_feature)
  end

  test "FlipperFeature is optional" do
    feature = create(:feature)
    assert_nil feature.flipper_feature

    assert_predicate feature, :valid?
  end

  test "enrollments are removed when a feature is destroyed" do
    feature = create(:feature)
    feature.enroll create(:user)

    perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
      assert_difference -> { FeatureEnrollment.count }, -1 do
        feature.destroy
      end
    end
  end

  context ".flipper_feature_ids" do
    test "returns the database IDs of the flipper features associated with prerelease features" do
      assert_includes Feature.flipper_feature_ids, @prerelease.flipper_feature_id
      refute_includes Feature.flipper_feature_ids, nil # non-prerelease features have a nil flipper_feature_id
    end

    test "caches the results" do
      Feature.flipper_feature_ids # warm the cache
      assert_predicate FeatureManagement::Kv.store.exists(Feature::FLIPPER_CACHE_KEY), :value!
    end
  end

  context "flipper feature cache busting" do
    test "clears the cache when a new feature is created" do
      Feature.flipper_feature_ids # warm the cache

      assert_predicate FeatureManagement::Kv.store.exists(Feature::FLIPPER_CACHE_KEY), :value!
      create(:feature_with_flipper)
      refute_predicate FeatureManagement::Kv.store.exists(Feature::FLIPPER_CACHE_KEY), :value!
    end

    test "clears the cache when a feature is deleted" do
      Feature.flipper_feature_ids # warm the cache

      assert_predicate FeatureManagement::Kv.store.exists(Feature::FLIPPER_CACHE_KEY), :value!
      @prerelease.destroy
      refute_predicate FeatureManagement::Kv.store.exists(Feature::FLIPPER_CACHE_KEY), :value!
    end

    test "clears the cache when a feature's flipper_feature_id changes" do
      Feature.flipper_feature_ids # warm the cache

      assert_predicate FeatureManagement::Kv.store.exists(Feature::FLIPPER_CACHE_KEY), :value!
      @prerelease.update(flipper_feature: create(:flipper_feature))
      refute_predicate FeatureManagement::Kv.store.exists(Feature::FLIPPER_CACHE_KEY), :value!
    end

    test "doesn't clear the cache when non-prerelease features change" do
      Feature.flipper_feature_ids # warm the cache
      assert_predicate FeatureManagement::Kv.store.exists(Feature::FLIPPER_CACHE_KEY), :value!

      @opt_in.destroy!
      assert_predicate FeatureManagement::Kv.store.exists(Feature::FLIPPER_CACHE_KEY), :value!

      @opt_out.update(public_name: "Something new")
      assert_predicate FeatureManagement::Kv.store.exists(Feature::FLIPPER_CACHE_KEY), :value!

      create(:feature)
      assert_predicate FeatureManagement::Kv.store.exists(Feature::FLIPPER_CACHE_KEY), :value!
    end
  end

  context ".flipper_enabled_for (scope)" do
    test "includes features where flipper is enabled for 100% of actors" do
      @prerelease.flipper_feature.enable_percentage_of_actors(100)
      assert_includes Feature.flipper_enabled_for(@user), @prerelease
    end

    test "includes features where flipper is enabled for < 100% of actors if that user is part of the % it's enabled for" do
      @prerelease.flipper_feature.enable_percentage_of_actors(50)
      FlipperFeature.any_instance.expects(:always_enabled?).with(@user).returns(true)

      assert_includes Feature.flipper_enabled_for(@user), @prerelease
    end

    test "includes features where flipper is enabled for 100% of requests" do
      @prerelease.flipper_feature.enable_percentage_of_time(100)
      assert_includes Feature.flipper_enabled_for(@user), @prerelease
    end

    test "includes features where flipper is enabled for a specific user" do
      @prerelease.flipper_feature.enable(@user)
      assert_includes Feature.flipper_enabled_for(@user), @prerelease
    end

    test "includes features where flipper is fully enabled" do
      @prerelease.flipper_feature.enable
      assert_includes Feature.flipper_enabled_for(@user), @prerelease
    end

    test "excludes features where flipper is fully disabled" do
      @prerelease.flipper_feature.disable
      refute_includes Feature.flipper_enabled_for(@user), @prerelease
    end

    test "excludes features where flipper is not enabled for a user" do
      refute @prerelease.flipper_feature.enabled?(@user)
      refute_includes Feature.flipper_enabled_for(@user), @prerelease
    end

    test "excludes features where flipper is enabled for < 100% of requests" do
      @prerelease.flipper_feature.enable_percentage_of_time(90)
      refute_includes Feature.flipper_enabled_for(@user), @prerelease
    end
  end

  context ".prerelease (scope)" do
    test "includes features that have an associated flipper feature" do
      prerelease_feature = create(:feature_with_flipper)
      assert_includes Feature.prerelease, prerelease_feature
    end

    test "excludes features that don't have an associated flipper feature" do
      ga_feature = create(:feature, :ga)
      refute_includes Feature.prerelease, ga_feature
    end
  end

  context ".unseen_by (scope)" do
    test "only returns features not seen by the user" do
      user = create(:user)
      first_feature = create(:feature_with_flipper)
      second_feature = create(:feature_with_flipper)

      first_feature.user_seen_features.create(user: user)
      unseen_features = Feature.unseen_by(user)

      refute_includes unseen_features, first_feature
      assert_includes unseen_features, second_feature
    end
  end

  context "#enroll" do
    test "works when no flipper feature is associated" do
      feature = create(:feature)
      user = create(:user)
      feature.unenroll(user)

      refute feature.enrolled?(user)
      feature.enroll(user)
      assert feature.enrolled?(user)
    end

    test "works when a user is enabled in flipper" do
      feature = create(:feature_with_flipper, :opt_in)
      user = create(:user)

      feature.flipper_feature.enable(user)
      feature.unenroll(user)

      refute feature.enrolled?(user)
      feature.enroll(user)
      assert feature.enrolled?(user)
    end

    test "fails when a user is not enabled in flipper" do
      feature = create(:feature_with_flipper, :opt_in)
      user = create(:user)

      refute feature.enroll(user)
    end
  end

  context "#unenroll" do
    test "works when no flipper feature is associated" do
      feature = create(:feature, :opt_out)
      user = create(:user)

      assert feature.enrolled?(user)
      feature.unenroll(user)
      refute feature.enrolled?(user)
    end

    test "works when a user is enabled in flipper" do
      feature = create(:feature_with_flipper, :opt_out)
      user = create(:user)

      feature.flipper_feature.enable(user)

      assert feature.enrolled?(user)
      feature.unenroll(user)
      refute feature.enrolled?(user)
    end

    test "no-op when a user is not enabled in flipper" do
      feature = create(:feature_with_flipper, :opt_out)
      user = create(:user)

      assert_no_difference -> { FeatureEnrollment.unenrolled.for_enrollee(user).count } do
        refute feature.unenroll(user)
      end
    end
  end

  context "#enrolled?" do
    test "anonymous users are enrolled in opt-out features that aren't pre-release" do
      refute @opt_out.prerelease?
      assert @opt_out.enrolled?(nil)
    end

    unless TestEnv.test_all_features?
      test "anonymous users are not enrolled in opt-in features that aren't pre-release" do
        refute @opt_in.prerelease?
        refute @opt_in.enrolled?(nil)
      end
    end

    test "anonymous users are enrolled in opt-out prerelease features" do
      @opt_out.update(flipper_feature: create(:flipper_feature, name: @opt_out.slug))
      refute @opt_out.enrolled?(nil)

      # Fully enable the feature
      @opt_out.flipper_feature.enable
      assert @opt_out.enrolled?(nil)
    end

    unless TestEnv.test_all_features?
      test "anonymous users are not enrolled in opt-in prerelease features" do
        @opt_in.update(flipper_feature: create(:flipper_feature, name: @opt_in.slug))
        refute @opt_in.enrolled?(nil)

        # Fully enable the feature
        @opt_in.flipper_feature.enable
        refute @opt_in.enrolled?(nil)
      end
    end

    test "is true for opt out features when no FeatureEnrollment exists" do
      feature = create(:feature, :opt_out)
      user = create(:user)

      assert feature.enrolled?(user)
    end

    unless TestEnv.test_all_features?
      test "is false for opt in features when no FeatureEnrollment exists" do
        feature = create(:feature, :opt_in)
        user = create(:user)

        refute feature.enrolled?(user)
      end
    end

    test "is false when an opted-out FeatureEnrollment exists" do
      feature = create(:feature, :opt_out)
      user = create(:user)
      create(:feature_enrollment, :unenrolled, enrollee: user, feature: feature)

      refute feature.enrolled?(user)
    end

    test "can't opt in if not enabled via flipper" do
      flipper_feature = create(:flipper_feature)
      late_adopter = create(:user)
      early_adopter = create(:user)

      feature = create(:feature, :opt_out, flipper_feature: flipper_feature)
      enrollment = create(:feature_enrollment, :enrolled, feature: feature, enrollee: early_adopter)

      refute feature.enrolled?(late_adopter)
      refute feature.enrolled?(early_adopter)

      flipper_feature.enable(early_adopter)

      refute feature.enrolled?(late_adopter)
      assert feature.enrolled?(early_adopter)
    end

    test "user can opt out even if enabled in flipper" do
      flipper_feature = create(:flipper_feature)
      flipper_feature.enable_percentage_of_actors(100)

      late_adopter = create(:user)
      feature = create(:feature, :opt_out, flipper_feature: flipper_feature)
      enrollment = create(:feature_enrollment, :unenrolled, feature: feature, enrollee: late_adopter)

      refute feature.enrolled?(late_adopter)
    end

    test "is false when no longer enabled in flipper" do
      flipper_feature = create(:flipper_feature)
      flipper_feature.enable_percentage_of_actors(100)

      user = create(:user)
      feature = create(:feature, :opt_out, flipper_feature: flipper_feature)
      feature.enroll(user)

      assert feature.enrolled?(user)
      flipper_feature.enable_percentage_of_actors(0)
      refute feature.enrolled?(user)
    end

    test "for opt-out features, users are opted in by default" do
      flipper_feature = create(:flipper_feature)
      flipper_feature.enable_percentage_of_actors(100)

      user = create(:user)
      feature = create(:feature, :opt_out, flipper_feature: flipper_feature)

      refute_predicate feature.enrollments.where(enrollee: user), :exists?
      assert feature.enrolled?(user)
    end

    unless TestEnv.test_all_features?
      test "for opt-in features, users are opted out by default" do
        flipper_feature = create(:flipper_feature)
        flipper_feature.enable_percentage_of_actors(100)

        user = create(:user)
        feature = create(:feature, :opt_in, flipper_feature: flipper_feature)

        refute_predicate feature.enrollments.where(enrollee: user), :exists?
        refute feature.enrolled?(user)
      end
    end
  end

  context ".default_feedback_link" do
    test "returns a link to the HelpHub support form" do
      assert_equal Feature.default_feedback_link, "https://support.github.com/contact/feedback?contact%5Bsubject%5D=Product+feedback"
    end
  end

  context "#viewer_can_read?" do
    test "returns true if no feature flag set" do
      feature = build(:feature, flipper_feature: nil)
      assert feature.viewer_can_read?(User.new)
    end

    test "returns true if the feature flag is enabled" do
      @prerelease.flipper_feature.enable(@user)
      assert @prerelease.viewer_can_read?(@user)
    end

    test "when #flipper_feature_name is set, we don't query #flipper_feature" do
      flipper_feature = create(:flipper_feature, name: "test-feature")
      flipper_feature.enable(@user)
      # We're setting the ID directly to avoid caching the Feature#flipper_feature in memory to force Rails to have to load it.
      feature = create(:feature, flipper_feature_id: flipper_feature.id)

      assert_equal feature.flipper_feature_name, "test-feature"
      assert_queries_matching(/^SELECT `flipper_features`.*/, 0) do
        assert feature.viewer_can_read?(@user)
      end
    end

    test "when #flipper_feature_name is not set, fallback to old behavior" do
      flipper_feature = create(:flipper_feature, name: "test-feature")
      flipper_feature.enable(@user)
      # We're setting the ID directly to avoid caching the Feature#flipper_feature in memory to force Rails to have to load it
      feature = build(:feature, flipper_feature_id: flipper_feature.id)

      assert_nil feature.flipper_feature_name
      assert_queries_matching(/^SELECT `flipper_features`.*/, 1) do
        assert feature.viewer_can_read?(@user)
      end
    end

    test "returns false if the feature flag is not enabled" do
      refute @prerelease.viewer_can_read?(@user)
    end
  end

  context "caching FlipperFeature#name on save" do
    test "caches FlipperFeature#name when a FlipperFeature is attached" do
      flipper_feature = create(:flipper_feature, name: "test-feature")
      feature = create(:feature, flipper_feature: flipper_feature)

      assert_equal feature.flipper_feature_name, "test-feature"
    end

    test "#flipper_feature_name returns nil when there is no FlipperFeature" do
      feature = create(:feature, flipper_feature: nil)

      assert_nil feature.flipper_feature_name
    end
  end
end
