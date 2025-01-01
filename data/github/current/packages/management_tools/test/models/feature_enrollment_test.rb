# typed: true
# frozen_string_literal: true

require "test_helper"

class FeatureEnrollmentTest < GitHub::TestCase
  fixtures do
    @staff = create(:staff_admin_user)
  end

  setup do
    GitHub.context.push(actor_id: @staff.id)
  end

  test "requires an associated enrollee" do
    enrollment = build(:feature_enrollment, :enrolled, enrollee: nil)

    refute_predicate enrollment, :valid?
    assert_includes enrollment.errors, :enrollee
  end

  test "can't enroll an organization" do
    org = create(:organization)
    enrollment = build(:feature_enrollment, :enrolled, enrollee: org)

    refute_predicate enrollment, :valid?
    assert_includes_match /must be a valid User/, enrollment.errors[:enrollee]
  end

  test "can't enroll a bot" do
    bot = create(:integration).bot
    enrollment = build(:feature_enrollment, :enrolled, enrollee: bot)

    refute_predicate enrollment, :valid?
    assert_includes_match /must be a valid User/, enrollment.errors[:enrollee]
  end

  test "requires an associated feature" do
    enrollment = build(:feature_enrollment, :enrolled, feature: nil)

    refute_predicate enrollment, :valid?
    assert_includes enrollment.errors, :feature
  end

  test "multiple enrollees can be enrolled in a feature" do
    enrollment_1 = create(:feature_enrollment, :enrolled)
    enrollment_2 = create(:feature_enrollment, :enrolled, feature: enrollment_1.feature)

    assert_predicate enrollment_2, :valid?
  end

  test "a user can be enrolled in multiple features" do
    enrollment_1 = create(:feature_enrollment, :enrolled)
    enrollment_2 = create(:feature_enrollment, :enrolled, enrollee: enrollment_1.enrollee)

    assert_predicate enrollment_2, :valid?
  end

  test "sets the last actor on create" do
    user = create(:user)
    GitHub.context.push(actor_id: user.id)

    enrollment = create(:feature_enrollment, enrollee: user)
    assert_equal user, enrollment.last_actor
  end

  test "sets the last actor on update" do
    user = create(:user)
    enrollment = create(:feature_enrollment, enrollee: user)
    GitHub.context.push(actor_id: user.id)

    enrollment.unenroll
    assert_equal user, enrollment.reload.last_actor
  end

  context "#enroll" do
    test "sets enrolled on a new record" do
      enrollment = build(:feature_enrollment, :for_opt_in_feature, enrolled: false)
      refute_predicate enrollment, :enrolled?

      assert enrollment.enroll
      assert_predicate enrollment, :enrolled?
    end

    test "sets enrolled on an existing unenrolled record" do
      enrollment = create(:feature_enrollment, :for_opt_in_feature, enrolled: false)
      refute_predicate enrollment, :enrolled?

      assert enrollment.enroll
      assert_predicate enrollment, :enrolled?
    end

    test "is a no-op for already enrolled users" do
      enrollment = Timecop.travel(1.week.ago) do
        create(:feature_enrollment, enrolled: true)
      end

      assert_no_difference "enrollment.updated_at" do
        enrollment.enroll
      end
    end
  end

  context "#unenrolled?" do
    test "is false when enrolled is true" do
      enrollment = build(:feature_enrollment, enrolled: true)
      refute_predicate enrollment, :unenrolled?
    end

    test "is true when enrolled is false" do
      enrollment = build(:feature_enrollment, :for_opt_in_feature, enrolled: false)
      assert_predicate enrollment, :unenrolled?
    end
  end

  context "instrumentation" do
    test "instruments enrollment on create" do
      events = subscribe "feature_enrollment.enrolled"
      enrollment = create(:feature_enrollment, :enrolled)

      assert event = events.pop, "an event was expected"
      assert_equal "feature_enrollment.enrolled", event.name
      assert_equal expected_payload(enrollment: enrollment), event.payload
    end

    test "instruments unenrollment on create" do
      events = subscribe "feature_enrollment.unenrolled"
      enrollment = create(:feature_enrollment, :unenrolled)

      assert event = events.pop, "an event was expected"
      assert_equal "feature_enrollment.unenrolled", event.name
      assert_equal expected_payload(enrollment: enrollment), event.payload
    end

    test "instruments enrollment on update" do
      enrollment = create(:feature_enrollment, :unenrolled)
      events = subscribe "feature_enrollment.enrolled"

      enrollment.enroll

      assert event = events.pop, "an event was expected"
      assert_equal "feature_enrollment.enrolled", event.name
      assert_equal expected_payload(enrollment: enrollment), event.payload
    end

    test "instruments unenrollment on update" do
      enrollment = create(:feature_enrollment, :enrolled)
      events = subscribe "feature_enrollment.unenrolled"

      enrollment.unenroll

      assert event = events.pop, "an event was expected"
      assert_equal "feature_enrollment.unenrolled", event.name
      assert_equal expected_payload(enrollment: enrollment), event.payload
    end

    test "payload actor_id is nil if actor was missing from the GitHub.context" do
      GitHub.context.push(actor_id: nil)
      events = subscribe "feature_enrollment.enrolled"
      enrollment = create(:feature_enrollment, :enrolled)

      assert event = events.pop, "an event was expected"
      assert_equal "feature_enrollment.enrolled", event.name
      assert_nil event.payload[:actor_id]
    end
  end

  def expected_payload(enrollment:)
    {
      toggleable_feature: enrollment.feature.public_name,
      toggleable_feature_id: enrollment.feature.id,
      feature_enrollment_id: enrollment.id,
      enrollee_id: enrollment.enrollee_id,
      enrollee_type: enrollment.enrollee_type,
      actor: @staff.to_s,
      actor_id: @staff.id,
      enrolled: enrollment.enrolled,
    }
  end
end
