# typed: true
# frozen_string_literal: true

class SponsorsLowCreditBalanceWarningJob < ApplicationJob
  include GitHub::Memoizer

  ZERO_BALANCE_THRESHOLD_DAYS = 90.days
  EMAIL_COOLDOWN_DAYS = 14.days

  queue_as :billing

  locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

  # Send a warning email when a Sponsors-invoiced org's credit balance is low.
  #
  # sponsor - Sponsors-invoiced Organization whose credit balance will be checked
  # zero_balance_date - Date when the sponsor's credit balance will be zero
  #
  # Returns a Boolean where true indicates an email was sent.
  def perform(sponsor:, zero_balance_date:)
    @zero_balance_date = zero_balance_date
    return false if @zero_balance_date.nil?

    @sponsor = sponsor
    return false unless @sponsor&.sponsors_invoiced?

    return false if email_sent_recently?

    send_reminder_email
  end

  private

  def email_sent_recently?
    Sponsors::KV.store.get(cooldown_key).value { nil }.present?
  end

  def record_email_sent
    with_write do
      Sponsors::KV.store.set(cooldown_key, "1", expires: EMAIL_COOLDOWN_DAYS.from_now)
    end
  end

  def cooldown_key
    "#{self.class.name}:#{@sponsor.id}"
  end

  def send_reminder_email
    threshold_date = @zero_balance_date - ZERO_BALANCE_THRESHOLD_DAYS
    return false if GitHub::Billing.today < threshold_date

    # Get unique managed_by users across active sponsorships (limit to prevent excessive emails)
    # Sorted by most recent sponsorship to prioritize currently active managers
    managed_by_users = Sponsorship.where(sponsor: @sponsor)
      .active
      .where.not(managed_by_id: nil)
      .select(:managed_by_id)
      .distinct
      .order(created_at: :desc)
      .limit(10)
      .map(&:managed_by)

    # If no managed_by users, pass nil to trigger fallback to admins/billing
    managed_by_users = [nil] if managed_by_users.empty?

    # Send one email per unique user (or one fallback email if no managed_by users)
    managed_by_users.each do |user|
      SponsorsPrimerMailer.low_credit_balance_warning(
        sponsor: @sponsor,
        zero_balance_date: @zero_balance_date,
        managed_by: user
      ).deliver_later
    end

    record_email_sent
    true
  end
end
