# typed: true
# frozen_string_literal: true

require "test_helper"

class NewsletterPreferenceTest < GitHub::TestCase
  include MailchimpHelper
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @email = @user.emails.first
  end

  test "can't have a preference for both marketing and transactional email" do
    preference = build(:newsletter_preference, elected_marketing_at: Time.current, elected_transactional_at: Time.current)
    preference.valid?
    assert_equal ["can only select one preference"], preference.errors[:base]
  end

  test "must have a preference for either marketing and transactional email" do
    preference = build(:newsletter_preference, elected_marketing_at: nil, elected_transactional_at: nil)
    preference.valid?
    assert_equal ["one preference must be set"], preference.errors[:base]
  end

  context ".set_to_marketing" do
    test "creates a marketing email preference for a user if one doesn't exist" do
      assert_nil NewsletterPreference.find_by(user_id: @user.id)
      NewsletterPreference.set_to_marketing(user: @user)
      refute_nil NewsletterPreference.find_by(user_id: @user.id)
    end

    test "clears the elected_transactional_at date" do
      preference = NewsletterPreference.set_to_transactional(user: @user)
      refute_nil preference.elected_transactional_at
      assert_nil preference.elected_marketing_at

      preference = NewsletterPreference.set_to_marketing(user: @user)
      refute_nil preference.elected_marketing_at
      assert_nil preference.elected_transactional_at
    end

    test "does not update the elected_marketing_at date if it is already set" do
      preference = NewsletterPreference.set_to_marketing(user: @user)
      date = preference.elected_marketing_at.to_i
      assert_equal date, NewsletterPreference.set_to_marketing(user: @user).elected_marketing_at.to_i
    end

    test "removes the user from the suppression list" do
      SuppressionList.add_user(@user)
      assert SuppressionList.includes_user?(@user)

      perform_enqueued_jobs(only: [RemoveFromSuppressionListJob]) do
        NewsletterPreference.set_to_marketing(user: @user)
        refute SuppressionList.includes_user?(@user)
      end
    end

    test "does not need to remove the user from the suppression list on signup" do
      NewsletterPreference.set_to_marketing(user: @user, signup: true)
      assert_no_enqueued_jobs only: RemoveFromSuppressionListJob
    end
  end

  context ".set_to_transactional" do
    test "creates a transactional email preference for a user if one doesn't exist" do
      assert_nil NewsletterPreference.find_by(user_id: @user.id)
      NewsletterPreference.set_to_transactional(user: @user)
      refute_nil NewsletterPreference.find_by(user_id: @user.id)
    end

    test "sets the elected_transactional_at date to the current time if a preference exists" do
      time = Time.current

      Timecop.freeze(time) do
        preference = NewsletterPreference.set_to_transactional(user: @user)
        assert_same_time time, preference.elected_transactional_at
      end
    end

    test "does not update the elected_transactional_at date if it is already set" do
      preference = NewsletterPreference.set_to_transactional(user: @user)
      date = preference.elected_transactional_at.to_i
      assert_equal date, NewsletterPreference.set_to_transactional(user: @user).elected_transactional_at.to_i
    end

    test "deactivates any current newsletter subscriptions" do
      subscription = NewsletterSubscription.subscribe(@user, "vulnerability", "weekly")
      assert subscription.active?

      assert_nil NewsletterPreference.find_by(user_id: @user.id)
      NewsletterPreference.set_to_transactional(user: @user)

      refute subscription.reload.active?
    end

    test "adds the user to the suppression list" do
      refute @email.suppressed?

      perform_enqueued_jobs(only: [AddToSuppressionListJob]) do
        NewsletterPreference.set_to_transactional(user: @user)
        assert @email.reload.suppressed?
      end
    end
  end

  context ".marketing?" do
    test "false by default for users without a newsletter preference record" do
      assert_nil NewsletterPreference.find_by(user_id: @user.id)
      assert_equal false, NewsletterPreference.marketing?(user: @user)
    end

    test "false if an unsaved new user record user is passed" do
      user = build(:user)
      assert user.new_record?
      assert_equal false, NewsletterPreference.marketing?(user: user)
    end

    test "false if a nil user is passed" do
      assert_equal false, NewsletterPreference.marketing?(user: nil)
    end

    test "true for users that have specifically elected to receive marketing email" do
      NewsletterPreference.set_to_marketing(user: @user)
      assert_equal true, NewsletterPreference.marketing?(user: @user)
    end

    test "false if the user has chosen to only receive transactional email" do
      NewsletterPreference.set_to_transactional(user: @user)
      assert_equal false, NewsletterPreference.marketing?(user: @user)
    end
  end

  context ".marketing_preference" do
    test "returns blank by default for users without a newsletter preference record" do
      assert_nil NewsletterPreference.find_by(user_id: @user.id)
      assert_equal "blank", NewsletterPreference.marketing_preference(user: @user)
    end

    test "false if an unsaved new user record user is passed" do
      user = build(:user)
      assert user.new_record?
      assert_equal false, NewsletterPreference.marketing_preference(user: user)
    end

    test "false if a nil user is passed" do
      assert_equal false, NewsletterPreference.marketing_preference(user: nil)
    end

    test "true for users that have specifically elected to receive marketing email" do
      NewsletterPreference.set_to_marketing(user: @user)
      assert_equal true, NewsletterPreference.marketing_preference(user: @user)
    end

    test "false if the user has chosen to only receive transactional email" do
      NewsletterPreference.set_to_transactional(user: @user)
      assert_equal false, NewsletterPreference.marketing_preference(user: @user)
    end
  end

  context "instrumentation" do
    test "instruments create" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      events = subscribe "newsletter_preference.create"
      preference = NewsletterPreference.set_to_transactional(user: @user)

      expected_payload = {
        user: @user.login,
        user_id: @user.id,
        elected: "transactional",
        elected_marketing_at: nil,
        elected_transactional_at: preference.elected_transactional_at,
      }

      hydro_payload = {
        user: {
          id:           @user.id,
          login:        @user.login,
          created_at:   @user.created_at,
          billing_plan: @user.plan.name,
          spammy:       @user.spammy,
          type:         @user.class.name.upcase,
        },
        write_type: "CREATE",
        experimental_arm: "EXPERIMENTAL_ARM_UNKNOWN",
        preference_choice: "TRANSACTIONAL",
        visitor_id: "",
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload

      assert_hydro_published(hydro_payload, schema: "github.v1.NewsletterPreferenceChange")
    end

    test "instruments correct email_opt_in experimental control arm" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      GitHub.context.push(email_opt_in_experiment_arm: "control")
      GitHub.context.push(visitor_id: "1234")

      expected_hydro_payload = {
        user: {
          id:           @user.id,
          login:        @user.login,
          created_at:   @user.created_at,
          billing_plan: @user.plan.name,
          spammy:       @user.spammy,
          type:         @user.class.name.upcase,
        },
        write_type: "CREATE",
        experimental_arm: "OPT_IN_PLACEMENT_CONTROL",
        preference_choice: "TRANSACTIONAL",
        visitor_id: "1234",
      }

      NewsletterPreference.set_to_transactional(user: @user)

      assert_hydro_published(expected_hydro_payload, schema: "github.v1.NewsletterPreferenceChange")
    end

    test "instruments correct email_opt_in experimental alternative arm" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      GitHub.context.push(email_opt_in_experiment_arm: "alternative")
      GitHub.context.push(visitor_id: "1234")

      expected_hydro_payload = {
        user: {
          id:           @user.id,
          login:        @user.login,
          created_at:   @user.created_at,
          billing_plan: @user.plan.name,
          spammy:       @user.spammy,
          type:         @user.class.name.upcase,
        },
        write_type: "CREATE",
        experimental_arm: "OPT_IN_PLACEMENT_ALTERNATE",
        preference_choice: "TRANSACTIONAL",
        visitor_id: "1234",
      }

      NewsletterPreference.set_to_transactional(user: @user)

      assert_hydro_published(expected_hydro_payload, schema: "github.v1.NewsletterPreferenceChange")
    end


    test "instruments update" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      NewsletterPreference.set_to_transactional(user: @user)

      events = subscribe "newsletter_preference.update"
      preference = NewsletterPreference.set_to_marketing(user: @user)

      expected_payload = {
        user: @user.login,
        user_id: @user.id,
        elected: "marketing",
        elected_marketing_at: preference.elected_marketing_at,
        elected_transactional_at: nil,
      }

      hydro_payload = {
        user: {
          id:           @user.id,
          login:        @user.login,
          created_at:   @user.created_at,
          billing_plan: @user.plan.name,
          spammy:       @user.spammy,
          type:         @user.class.name.upcase,
        },
        preference_choice: "MARKETING",
        write_type: "UPDATE",
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload

      assert_hydro_published(hydro_payload, schema: "github.v1.NewsletterPreferenceChange")
    end
  end
end
