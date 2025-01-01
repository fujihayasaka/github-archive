# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotFreeUserTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper
  include HydroTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  fixtures do
    @user = create(:user)
    @free_user = create(:copilot_free_user, user: @user, subscribed: true)
    @public_repo = create(:public_repository, name: "public-repo-1", created_at: 2.months.ago, pushed_at: 2.years.ago, owner: @user)
    @other_public_repo = create(:public_repository, name: "public-repo-2", created_at: 2.months.ago, pushed_at: 2.years.ago, owner: @user)

    @partner_education_coupon = create(:coupon, code: "student-partner")
    @old_educational_coupon = create(:coupon, code: "students-#{DateTime.now.year - 1}")
    @educational_coupon = create(:coupon, code: "students-#{DateTime.now.year}")
    @faculty_coupon = create(:coupon, code: "faculty-#{DateTime.now.year}")
    @workshop_coupon = create(:coupon, code: "cfp-#{DateTime.now.year}")
    @mvp_coupon = create(:coupon, code: "MVP-07a2132")
    @non_educational_coupon = create(:coupon, group: "internal")
  end

  context "scope not_subscribed" do
    test "returns only free users that are not subscribed" do
      free_user = create(:copilot_free_user, user: create(:user), subscribed: false, created_at: Time.now.utc - 2.years)
      assert_equal free_user, Copilot::FreeUser.not_subscribed.first
    end

    test "returns no free users that are subscribed" do
      create(:copilot_free_user, user: create(:user), subscribed: true)
      assert_equal 0, Copilot::FreeUser.not_subscribed.count
    end
  end

  context "scope needs update" do
    test "all of them at once" do
      Copilot::FreeUser.delete_all
      assert_equal 0, Copilot::FreeUser.count

      # unlimited free access
      free_user = create(
        :copilot_free_user,
        :complimentary,
        user: create(:user),
        last_checked_date: Date.new(9999, 12, 31),
        subscribed: true,
        subscribed_at: Date.today,
      )

      refute free_user.should_update?

      # unsubscribed educational
      free_user = create(
        :copilot_free_user,
        :educational,
        user: create(:user),
        last_checked_date: Date.yesterday,
        subscribed: false,
        subscribed_at: nil,
      )

      refute free_user.should_update?
      assert_equal Copilot::FreeUser.needs_updating.count, 0

      free_user = create(
        :copilot_free_user,
        :educational_redeemed,
        user: create(:user),
        last_checked_date: Date.yesterday,
        subscribed: true,
        subscribed_at: Date.today,
      )
      free_user.reload
      assert_equal free_user.user.coupon_redemption.expires_at.to_date, free_user.last_checked_date
      refute free_user.should_update?

      assert_equal Copilot::FreeUser.needs_updating.count, 0

      user = create(:user)
      code = "student-partner"
      educational_coupon = Coupon.find_by(code: code) || create(:coupon, code: "student-partner")
      educational_coupon.update(limit: 9999)
      user.redeem_coupon(educational_coupon)
      user.reload
      user.coupon_redemption.update(expires_at: Date.today - 1.day)
      free_user = create(
        :copilot_free_user,
        user: user,
        last_checked_date: user.coupon_redemption.expires_at.to_date,
        subscribed: true,
        subscribed_at: Date.today,
      )
      assert_equal free_user.user.coupon_redemption.expires_at.to_date, free_user.last_checked_date
      assert free_user.should_update?

      assert_equal Copilot::FreeUser.needs_updating.count, 1
    end
  end

  context ".type" do
    Copilot::FreeUser::FREE_USER_TYPES.each do |type|
      test "returns the correct type for #{type.name}" do
        assert_equal type, Copilot::FreeUser.type(type.name)
      end
    end

    test "raises for invalid type" do
      assert_raises ArgumentError, /invalid/i do
        Copilot::FreeUser.type("invalid")
      end
    end
  end

  context "should_update" do
    test "false unless 60 days TECHNICAL_PREVIEW_EXTENSION" do
      user = create(:user)
      free_user = create(
        :copilot_free_user,
        :technical_preview_extension,
        user: user,
        last_checked_date: Date.today + 60.days,
        subscribed: true,
      )
      refute free_user.should_update?

      travel_to Date.today + 65.days do
        assert free_user.should_update?
        assert free_user.last_checked_date < Date.current
      end
    end

    test "COMPLIMENTARY_ACCESS (unlimited) will never need updating" do
      Copilot::FreeUser.delete_all
      assert_equal 0, Copilot::FreeUser.count

      user = create(:user)
      free_user = create(
        :copilot_free_user,
        :complimentary,
        user: user,
        last_checked_date: Date.new(9999, 12, 31),
      )
      refute free_user.should_update?
      assert_equal Copilot::FreeUser.needs_updating.count, 0

      travel_to Date.today + 1000.years do
        refute free_user.should_update?
        assert_equal Copilot::FreeUser.needs_updating.count, 0
      end
    end

    test "returns a long time from now for COMPLIMENTARY_ACCESS (specified)" do
      user = create(:user)
      free_user = create(
        :copilot_free_user,
        :complimentary,
        user: user,
        last_checked_date: Date.today + 15.days,
        subscribed: true,
      )
      refute free_user.should_update?
      assert_equal Copilot::FreeUser.needs_updating.count, 0

      travel_to Date.today + 20.days do
        assert free_user.should_update?
        assert_equal Copilot::FreeUser.needs_updating.count, 1
      end
    end

    test "returns a month from now for EDUCATIONAL" do
      user = create(:user)
      free_user = create(
        :copilot_free_user,
        :educational,
        user: user,
        last_checked_date: Date.today + 15.days,
        subscribed: true,
      )
      refute free_user.should_update?
      assert_equal Copilot::FreeUser.needs_updating.count, 0

      travel_to Date.today + 45.days do
        assert free_user.should_update?
        assert_equal Copilot::FreeUser.needs_updating.count, 1
      end
    end
  end

  context "validation" do
    test "validates" do
      copilot_free_user = Copilot::FreeUser.new

      refute copilot_free_user.valid?
      refute_nil copilot_free_user.errors[:user]
      refute_nil copilot_free_user.errors[:free_user_type]

      copilot_free_user.user = @user
      copilot_free_user.free_user_type = "spaghetti"
      refute copilot_free_user.valid?
      refute_nil copilot_free_user.errors[:user]
      refute_nil copilot_free_user.errors[:free_user_type]
    end

    test "validates free_user_type" do
      Copilot::FreeUser::FREE_USER_TYPES.each do |type|
        free_user = Copilot::FreeUser.new(user: @user, free_user_type: type.name)

        assert free_user.valid?,
          type.name
      end

      free_user = Copilot::FreeUser.new(user: @user, free_user_type: "spaghetti")
      refute free_user.valid?
    end
  end

  context "#type" do
    test "returns the type for the free_user_type" do
      Copilot::FreeUser::FREE_USER_TYPES.each do |type|
        free_user = Copilot::FreeUser.new(free_user_type: type.name)

        assert_equal type, free_user.type
      end
    end
  end

  context "#warn_and_queue_cancel!" do
    test "logs with the correct tags" do
      last_checked_date = @free_user.last_checked_date

      logs = capture_logs do
        @free_user.warn_and_queue_cancel!
      end

      assert_includes logs, "Warning free user"
      assert_log_matches logs,
        "code.function": "warn_and_queue_cancel!",
        "gh.copilot.free_user.free_user_type": @free_user.free_user_type,
        "gh.copilot.free_user.last_checked_date": last_checked_date,
        "gh.copilot.free_user.subscribed": @free_user.subscribed,
        "gh.user.id": @user.id
    end

    test "instruments the warning" do
      free_user = create(
        :copilot_free_user,
        :educational,
        user: create(:user),
        last_checked_date: Date.today - 13.months,
      )

      copilot_user = Copilot::User.new(free_user.user)

      free_user.warn_and_queue_cancel!

      assert_equal 1,
        GitHub.dogstats.increments("copilot.free_user.user_warned").length

      assert_hydro_published(
        {
          user: Hydro::EntitySerializer.user(free_user.user),
          copilot_user_details: copilot_user.copilot_user_details,
          event_type: :WARNED,
        },
        schema: "github.copilot.v1.CopilotFreeUserEvent",
      )
    end

    test "updates last_checked_date to now" do
      free_user = create(
        :copilot_free_user,
        :educational,
        user: create(:user),
        last_checked_date: Date.today - 13.months,
      )

      free_user.warn_and_queue_cancel!

      assert_equal Date.today + T.cast(Copilot::FreeUser::EXPIRATION_WARNING_DURATION, Integer) + 1.day,
        free_user.reload.last_checked_date
    end

    test "sends an email to the user when the feature flag is enabled" do
      GitHub.flipper[:copilot_free_user_warn_email].enable

      free_user = create(:copilot_free_user)

      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotFreeUserMailer
        .expects(:expiration_warning)
        .with(free_user.user, instance_of(ActiveSupport::TimeWithZone))
        .returns(mailer)
        .once

      free_user.warn_and_queue_cancel!
    end

    test "does not send an email to the user when the feature flag is disabled" do
      free_user = create(:copilot_free_user)

      CopilotFreeUserMailer
        .expects(:expiration_warning)
        .never

      free_user.warn_and_queue_cancel!
    end

    test "queues a worker to cancel!" do
      free_user = create(:copilot_free_user)

      free_user.warn_and_queue_cancel!

      assert_enqueued_with(
        job: Copilot::FreeUserCancellationJob,
        args: [free_user.id],
      )
    end
  end

  context "#cancel!" do
    test "logs with the correct tags" do
      logs = capture_logs do
        @free_user.cancel!
      end

      assert_includes logs, "Cancelling free user"
      assert_log_matches logs,
        "code.function": "cancel!",
        "gh.copilot.free_user.free_user_type": @free_user.free_user_type,
        "gh.copilot.free_user.last_checked_date": @free_user.last_checked_date,
        "gh.copilot.free_user.subscribed": @free_user.subscribed,
        "gh.user.id": @user.id
    end

    test "instruments cancellation" do
      free_user = create(
        :copilot_free_user,
        :educational,
        user: create(:user),
        last_checked_date: Date.today - 13.months,
      )

      copilot_user = Copilot::User.new(free_user.user)

      free_user.cancel!

      assert_equal 1,
        GitHub.dogstats.increments("copilot.free_user.user_cancelled").length

      assert_hydro_published(
        {
          user: Hydro::EntitySerializer.user(free_user.user),
          copilot_user_details: copilot_user.copilot_user_details,
          event_type: :CANCELLED
        },
        schema: "github.copilot.v1.CopilotFreeUserEvent",
      )
    end

    test "deletes the record" do
      free_user = create(
        :copilot_free_user,
        :educational,
        user: create(:user),
        last_checked_date: Date.today - 13.months,
      )

      assert_changes -> { Copilot::FreeUser.count }, -1 do
        free_user.cancel!
      end
    end

    test "sends an email to the user when the feature flag is enabled" do
      GitHub.flipper[:copilot_free_user_expired_email].enable

      free_user = create(:copilot_free_user)

      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotFreeUserMailer
        .expects(:expired)
        .with(free_user.user)
        .returns(mailer)
        .once

      free_user.cancel!
    end

    test "does not send an email to the user when the feature flag is disabled" do
      free_user = create(:copilot_free_user)

      CopilotFreeUserMailer
        .expects(:expired)
        .never

      free_user.cancel!
    end
  end

  context "#refresh!" do
    test "logs with the correct tags" do
      logs = capture_logs do
        @free_user.refresh!
      end

      assert_includes logs, "Refreshing free user"
      assert_log_matches logs,
        "code.function": "refresh!",
        "gh.copilot.free_user.free_user_type": @free_user.free_user_type,
        "gh.copilot.free_user.last_checked_date": @free_user.last_checked_date,
        "gh.copilot.free_user.subscribed": @free_user.subscribed,
        "gh.user.id": @user.id
    end

    test "instruments the refresh" do
      free_user = create(
        :copilot_free_user,
        :engaged_oss,
        user: create(:user),
        last_checked_date: Date.yesterday,
      )

      copilot_user = Copilot::User.new(free_user.user)

      free_user.refresh!

      assert_equal GitHub.dogstats.increments(
        "copilot.free_user.user_refreshed"
      ).map(&:options), [
        { tags: ["free_user_type:EngagedOSS"] },
      ]

      assert_hydro_published(
        {
          user: Hydro::EntitySerializer.user(free_user.user),
          copilot_user_details: copilot_user.copilot_user_details,
          event_type: :REFRESHED
        },
        schema: "github.copilot.v1.CopilotFreeUserEvent",
      )
    end

    {
      "complimentary" => {
        trait: :complimentary,
        expected_next_check_at_from_now: 30.days,
      },
      "educational with a coupon that expires far out" => {
        trait: :educational,
        coupon_expires_at_from_now: 1.year,
        expected_next_check_at_from_now: 1.year + 1.day,
      },
      "educational with a coupon that expires soon" => {
        trait: :educational,
        coupon_expires_at_from_now: 5.days,
        expected_next_check_at_from_now: 6.days,
      },
      "educational with expired coupon" => {
        trait: :educational,
        coupon_expires_at_from_now: -1.day,
      },
      "educational with no coupon" => {
        trait: :educational,
      },
      "engaged OSS" => {
        trait: :engaged_oss,
        expected_next_check_at_from_now: 30.days,
      },
      "faculty with a coupon that expires far out" => {
        trait: :faculty,
        coupon_expires_at_from_now: 1.year,
        expected_next_check_at_from_now: 1.year + 1.day,
      },
      "faculty with a coupon that expires soon" => {
        trait: :faculty,
        coupon_expires_at_from_now: 5.days,
        expected_next_check_at_from_now: 6.days,
      },
      "faculty with expired coupon" => {
        trait: :faculty,
        coupon_expires_at_from_now: -1.day,
      },
      "faculty with no coupon" => {
        trait: :faculty,
      },
      "GitHub star" => {
        trait: :github_star,
        expected_next_check_at_from_now: 30.days,
      },
      "MS MVP with a coupon that expires far out" => {
        trait: :ms_mvp,
        coupon_expires_at_from_now: 1.year,
        expected_next_check_at_from_now: 1.year + 1.day,
      },
      "MS MVP with a coupon that expires soon" => {
        trait: :ms_mvp,
        coupon_expires_at_from_now: 5.days,
        expected_next_check_at_from_now: 6.days,
      },
      "MS MVP with expired coupon" => {
        trait: :ms_mvp,
        coupon_expires_at_from_now: -1.day,
      },
      "MS MVP with no coupon" => {
        trait: :ms_mvp,
      },
    }.each do |name, testcase|
      test name do
        freeze_time do
          coupon_expires_at_from_now = testcase[:coupon_expires_at_from_now]
          expected_next_check_at_from_now = testcase[:expected_next_check_at_from_now]

          user = create(:user)
          free_user = create(
            :copilot_free_user,
            testcase[:trait],
            user: user,
            next_check_at: Date.current,
          )

          if coupon_expires_at_from_now
            coupon = create(:coupon)

            create(
              :coupon_redemption,
              coupon: coupon,
              billable_entity: user,
              expires_at: coupon_expires_at_from_now.from_now,
            )
          end

          free_user.refresh!

          if expected_next_check_at_from_now
            assert_equal expected_next_check_at_from_now.from_now.to_date,
              free_user.next_check_at.to_date,
              "updates next_check_at"
          else
            refute Copilot::FreeUser.exists?(free_user.id),
              "deletes the free user"
          end
        end
      end
    end

    test "sends an email to the user when the feature flag is enabled" do
      GitHub.flipper[:copilot_free_user_refresh_email].enable

      free_user = create(:copilot_free_user, :github_star)

      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotFreeUserMailer
        .expects(:refreshed)
        .with(free_user.user, instance_of(Date), nil)
        .returns(mailer)
        .once

      free_user.refresh!
    end

    test "does not send an email to the user when the feature flag is disabled" do
      free_user = create(:copilot_free_user, :github_star)

      CopilotFreeUserMailer
        .expects(:refreshed)
        .never

      free_user.refresh!
    end
  end

  context "#is_educational_user?" do
    test "is true when they have an educational coupon" do
      @user.redeem_coupon(@educational_coupon)
      assert Copilot::FreeUser.is_educational_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_educational_user")
    end

    test "is true when they have an older educational coupon" do
      @user.redeem_coupon(@old_educational_coupon)
      assert Copilot::FreeUser.is_educational_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_educational_user")
    end

    test "is true when they have student partner coupon" do
      @user.redeem_coupon(@partner_education_coupon)
      assert Copilot::FreeUser.is_educational_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_educational_user")
    end

    test "is false when they have a non-educational coupon" do
      @user.redeem_coupon(@non_educational_coupon)
      refute Copilot::FreeUser.is_educational_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_educational_user")
    end

    test "is false when they have no coupon" do
      refute Copilot::FreeUser.is_educational_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_educational_user")
    end
  end

  context "#is_engaged_oss_user?" do
    test "is true when the user has a repository in the engaged oss list" do
      create(:copilot_engaged_oss_user, user: @user)

      # assert Copilot::FreeUser.is_engaged_oss_user?(Copilot::User.new(@user))
      # assert find_span_by(name: "copilot.free_user.is_engaged_oss_user")
    end

    test "is false when the user has a no repository in the engaged oss list" do

      refute Copilot::FreeUser.is_engaged_oss_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_engaged_oss_user")
    end
  end

  context "#is_faculty_user?" do
    test "is true when they have faculty coupon AND the flag is enabled" do
      @user.redeem_coupon(@faculty_coupon)
      assert Copilot::FreeUser.is_faculty_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_faculty_user")
    end

    test "is false when they have a non-faculty coupon" do
      @user.redeem_coupon(@non_educational_coupon)
      refute Copilot::FreeUser.is_faculty_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_faculty_user")
    end

    test "is false when they have no coupon" do
      refute Copilot::FreeUser.is_faculty_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_faculty_user")
    end
  end

  context "#is_github_star_user?" do
    test "is true when they are a star" do
      User.any_instance.stubs(:github_star?).returns(true)
      Copilot::User.any_instance.stubs(:github_star?).returns(true)
      assert Copilot::FreeUser.is_github_star_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_github_star_user")
    end

    test "is false when they are not a star" do
      refute Copilot::FreeUser.is_github_star_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_github_star_user")
    end
  end

  context "#is_ms_mvp_user?" do
    test "is true when they have mvp coupon" do
      @user.redeem_coupon(@mvp_coupon)
      assert Copilot::FreeUser.is_ms_mvp_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_ms_mvp_user")
    end

    test "is false when they have a non-mvp coupon" do
      @user.redeem_coupon(@non_educational_coupon)
      refute Copilot::FreeUser.is_ms_mvp_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_ms_mvp_user")
    end

    test "is false when they have no coupon" do
      refute Copilot::FreeUser.is_ms_mvp_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_ms_mvp_user")
    end
  end

  context "#is_workshop_user?" do
    test "is true when they have mvp coupon" do
      @user.redeem_coupon(@workshop_coupon)
      assert Copilot::FreeUser.is_workshop_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_workshop_user")
    end

    test "is false when they have a non-mvp coupon" do
      @user.redeem_coupon(@non_educational_coupon)
      refute Copilot::FreeUser.is_workshop_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_workshop_user")
    end

    test "is false when they have no coupon" do
      refute Copilot::FreeUser.is_workshop_user?(Copilot::User.new(@user))
      assert find_span_by(name: "copilot.free_user.is_workshop_user")
    end
  end

  context ".find_for_copilot_user" do
    test "unqualified people get sad" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      free_user = Copilot::FreeUser.find_for_copilot_user(copilot_user)
      assert_nil free_user
    end

    test "github star check" do
      freeze_time do
        User.any_instance.stubs(:github_star?).returns(true)
        Copilot::User.any_instance.stubs(:github_star?).returns(true)
        free_user = Copilot::FreeUser.find_for_copilot_user(Copilot::User.new(create(:user)))
        assert_equal Copilot::FreeUser::GITHUB_STAR,
          T.must(free_user).type
        assert_equal 1.year.from_now.to_date,
          T.must(free_user).last_checked_date
      end
    end

    test "creates free user record and returns it and converts for metric" do
      freeze_time do
        user = create(:user)

        future = 10.years.from_now
        redemption = user.redeem_coupon(@educational_coupon)
        redemption.update(expires_at: future)

        copilot_user = Copilot::User.new(user)
        free_user = Copilot::FreeUser.find_for_copilot_user(copilot_user)
        assert_equal Copilot::FreeUser::EDUCATIONAL,
          T.must(free_user).type
        assert_in_delta T.must(free_user).last_checked_date, future.to_date, 1
        assert find_span_by(name: "copilot.free_user.find_for_copilot_user")
      end
    end

    test "returns record if it exists" do
      user = create(:user)
      free_user = create(:copilot_free_user, user: user, subscribed: true)
      copilot_user = Copilot::User.new(user)
      assert_equal free_user, Copilot::FreeUser.find_for_copilot_user(copilot_user)
      assert find_span_by(name: "copilot.free_user.find_for_copilot_user")
    end

    test "returns free user record if one exists even if we pass a Copilot::User" do
      user = create(:user)
      free_user = create(:copilot_free_user, user: user, subscribed: true)
      assert_equal free_user, Copilot::FreeUser.find_for_copilot_user(Copilot::User.new(user))
      assert find_span_by(name: "copilot.free_user.find_for_copilot_user")
    end
  end
end if GitHub.copilot_enabled?
