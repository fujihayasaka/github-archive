# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsLowCreditBalanceWarningJobTest < GitHub::TestCase
  include ActionMailer::TestHelper

  fixtures do
    @sponsorship = create(:sponsorship, :sponsors_invoiced, monthly_price_in_cents: 10_00, expires_at: nil)
    @sponsor = @sponsorship.sponsor
  end

  setup do
    disable_feature_flag(:sponsors_disable_low_credit_balance_warning_email)
  end

  test "sends email if the credit balance does not meet the threshold" do
    stub_credit_balance(@sponsor)

    day_after_threshold = threshold_date(@sponsor) + 1.day
    zero_balance_date = calculate_zero_balance_date(@sponsor)

    travel_to(day_after_threshold) do
      assert_emails 1 do
        assert SponsorsLowCreditBalanceWarningJob.perform_now(
          sponsor: @sponsor,
          zero_balance_date: zero_balance_date
        )
      end
    end
  end

  test "does not send email if user is not Sponsors-invoiced" do
    user = create(:user)

    refute_predicate user, :sponsors_invoiced?, "User should not be sponsors-invoiced"

    threshold_days = SponsorsLowCreditBalanceWarningJob::ZERO_BALANCE_THRESHOLD_DAYS
    day_after_threshold = GitHub::Billing.today - threshold_days + 1.day

    assert_emails 0 do
      refute SponsorsLowCreditBalanceWarningJob.perform_now(
        sponsor: user,
        zero_balance_date: day_after_threshold,
      )
    end
  end

  test "does not send email if the credit balance meets the threshold" do
    stub_credit_balance(@sponsor)

    day_before_threshold = threshold_date(@sponsor) - 1.day
    zero_balance_date = calculate_zero_balance_date(@sponsor)

    travel_to(day_before_threshold) do
      assert_emails 0 do
        refute SponsorsLowCreditBalanceWarningJob.perform_now(
          sponsor: @sponsor,
          zero_balance_date: zero_balance_date,
        )
      end
    end
  end

  test "does not send email if a reminder has been sent recently" do
    stub_credit_balance(@sponsor)

    day_after_threshold = threshold_date(@sponsor) + 1.day
    before_cooldown_expired_days = cooldown_expires_days - 1.day
    zero_balance_date = calculate_zero_balance_date(@sponsor)

    travel_to(day_after_threshold) do
      assert_emails 1 do
        assert SponsorsLowCreditBalanceWarningJob.perform_now(
          sponsor: @sponsor,
          zero_balance_date: zero_balance_date,
        )
      end
    end

    travel_to(day_after_threshold + before_cooldown_expired_days) do
      assert_emails 0 do
        refute SponsorsLowCreditBalanceWarningJob.perform_now(sponsor: @sponsor, zero_balance_date: zero_balance_date)
      end
    end
  end

  # https://github.com/github/sponsors/issues/4430
  test "does not send email if no date is given" do
    assert_emails 0 do
      refute SponsorsLowCreditBalanceWarningJob.perform_now(sponsor: @sponsor, zero_balance_date: nil)
    end
  end

  test "send additional email if a reminder has not been sent recently" do
    stub_credit_balance(@sponsor)

    day_after_threshold = threshold_date(@sponsor) + 1.day
    after_cooldown_expired_days = cooldown_expires_days + 1.day
    zero_balance_date = calculate_zero_balance_date(@sponsor)

    travel_to(day_after_threshold) do
      assert_emails 1 do
        assert SponsorsLowCreditBalanceWarningJob.perform_now(
          sponsor: @sponsor,
          zero_balance_date: zero_balance_date,
        )
      end
    end

    travel_to(day_after_threshold + after_cooldown_expired_days) do
      assert_emails 1 do
        assert SponsorsLowCreditBalanceWarningJob.perform_now(
          sponsor: @sponsor,
          zero_balance_date: zero_balance_date,
        )
      end
    end
  end

  test "preventing duplicate emails is sponsor-specific" do
    other_sponsorship = create(:sponsorship, :sponsors_invoiced, monthly_price_in_cents: 10_00, expires_at: nil)
    other_sponsor = other_sponsorship.sponsor

    stub_credit_balance(@sponsor)
    stub_credit_balance(other_sponsor)

    day_after_threshold = threshold_date(@sponsor) + 1.day
    zero_balance_date = calculate_zero_balance_date(@sponsor)
    other_zero_balance_date = calculate_zero_balance_date(other_sponsor)

    assert_equal zero_balance_date, other_zero_balance_date, "users should have the same zero balance date"

    travel_to(day_after_threshold) do
      assert_emails 2 do
        assert SponsorsLowCreditBalanceWarningJob.perform_now(
          sponsor: @sponsor,
          zero_balance_date: zero_balance_date,
        )
        assert SponsorsLowCreditBalanceWarningJob.perform_now(
          sponsor: other_sponsor,
          zero_balance_date: other_zero_balance_date,
        )
      end
    end
  end

  def stub_credit_balance(user)
    user.sponsors_customer.stubs(:credit_balance).returns(Billing::Money.new(100_00))
  end

  def calculate_zero_balance_date(user)
    sponsorships = user.active_sponsorships_as_sponsor_relation
    sponsors_customer = user.sponsors_customer
    current_balance = sponsors_customer.credit_balance

    low_balance_calculator = Sponsors::ZeroBalanceDateCalculator.new(
      sponsorships: sponsorships,
      current_balance: current_balance,
      customer: sponsors_customer,
    )
    low_balance_calculator.zero_balance_date
  end

  def threshold_date(sponsor)
    calculate_zero_balance_date(sponsor) - SponsorsLowCreditBalanceWarningJob::ZERO_BALANCE_THRESHOLD_DAYS
  end

  def cooldown_expires_days
    SponsorsLowCreditBalanceWarningJob::EMAIL_COOLDOWN_DAYS
  end
end if GitHub.sponsors_enabled?
