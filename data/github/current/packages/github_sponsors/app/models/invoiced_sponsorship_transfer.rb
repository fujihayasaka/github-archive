# typed: true
# frozen_string_literal: true

class InvoicedSponsorshipTransfer < ApplicationRecord::Ballast
  belongs_to :sponsor, class_name: "User", required: true,
    inverse_of: :invoiced_sponsorship_transfers_as_sponsor
  belongs_to :sponsors_listing, required: true
  belongs_to :stripe_connect_account, class_name: "Billing::StripeConnect::Account", required: true
  belongs_to :actor, class_name: "User", required: true

  has_one :sponsorship
  has_one :sponsorable, through: :sponsors_listing, disable_joins: true

  has_many :reversals, class_name: "InvoicedSponsorshipTransferReversal"

  before_validation :strip_note_whitespace

  validate :sponsors_listing_must_be_approved
  validate :expires_at_is_date_in_the_future
  validate :number_of_months_is_a_positive_integer
  validates :amount_in_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :zuora_payment_id, format: { with: /\A[a-f0-9]+\z/ }
  validates :stripe_transfer_id, format: { with: /\Atr_\w+\z/ }, allow_nil: true

  scope :completed, -> { where("stripe_transfer_id IS NOT NULL") }
  scope :for_stripe_account, ->(stripe_account) { where(stripe_connect_account_id: stripe_account) }
  scope :for_sponsor, ->(sponsor_or_id) { where(sponsor_id: sponsor_or_id) }
  scope :for_sponsors_listing, ->(sponsors_listing_or_id) { where(sponsors_listing_id: sponsors_listing_or_id) }
  scope :for_sponsorable, ->(users_or_ids) do
    sponsors_listing_ids = SponsorsListing.for_sponsorable_user_or_org(Array(users_or_ids)).pluck(:id)
    for_sponsors_listing(sponsors_listing_ids)
  end
  scope :created_between, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  scope :not_fully_reversed, -> do
    reversals = InvoicedSponsorshipTransferReversal.table_name
    conditions = <<~SQL
      NOT EXISTS (
        SELECT 1
        FROM #{reversals}
        WHERE #{table_name}.id = #{reversals}.invoiced_sponsorship_transfer_id
        HAVING SUM(#{reversals}.amount_in_cents) = #{table_name}.amount_in_cents
      )
    SQL
    where(conditions)
  end

  attr_reader :sponsorable_login, :amount_in_dollars, :expires_at
  attr_accessor :privacy_level, :email_opt_in

  delegate :stripe_account_id, to: :stripe_connect_account
  delegate :sponsorable_id, to: :sponsors_listing

  # Public: Record that a Stripe transfer came in by updating relevant fields on this transfer as well as the
  # associated sponsorship, if one exists. Marks the sponsorship as paid since we only call this method once staff
  # has manually confirmed we've received payment for the invoice.
  #
  # time - DateTime that the Stripe transfer was created
  # transfer_id - String ID of a Stripe::Transfer
  #
  # Returns a Boolean indicating whether updates were successful.
  def record_stripe_transfer(time:, transfer_id:)
    transaction do
      success = update(stripe_transfer_id: transfer_id, transfer_created_at: time)
      if success && sponsorship
        success = T.must(sponsorship).update(paid_at: time)
        raise ActiveRecord::Rollback unless success
      end
      success
    end
  end

  def sponsorable_login=(login)
    @sponsorable_login = login
    sponsorable = User.find_by_login(login)
    self.sponsors_listing = sponsorable&.sponsors_listing
    self.stripe_connect_account = sponsors_listing&.stripe_transfer_account
  end

  def amount_in_dollars=(amount)
    @amount_in_dollars = amount
    self.amount_in_cents = Billing::Money.parse(amount).cents
  end

  def expires_at=(expiration)
    return if expiration.blank?
    @expires_at = expiration.to_date
  rescue ArgumentError
    # set expires_at to a date in the past so it fails validation
    @expires_at = Date.current - 1.day
  end

  def number_of_months=(num)
    @number_of_months = num.to_i
  end

  def number_of_months
    @number_of_months ||= 1
  end

  sig { returns Billing::Money }
  def to_money
    Billing::Money.new(amount_in_cents)
  end

  def monthly_amount_in_cents
    return amount_in_cents unless number_of_months > 1

    rounded_dollars = (to_money / number_of_months).dollars.round
    rounded_dollars * 100
  end

  def reversible_amount_in_cents
    return 0 unless completed?
    amount_in_cents - reversals.sum(:amount_in_cents)
  end

  def reversible?
    reversible_amount_in_cents > 0
  end

  # Public: Was another transfer made from the same sponsor, to the same maintainer, in the immediately preceding time
  # to this one? Can be used to assess if this was meant as a one-off payment or a recurring sponsorship.
  #
  # Returns a Boolean.
  def consecutive_recurrence?
    creation_time = created_at || Time.now
    start_time = creation_time - Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS.days
    end_time = creation_time - 1.second # just before this transfer but not including it
    other_transfers = InvoicedSponsorshipTransfer.for_sponsor(sponsor_id)
      .for_sponsors_listing(sponsors_listing_id)
      .created_between(start_time, end_time)
    other_transfers = other_transfers.where.not(id: id) if persisted?
    other_transfers = other_transfers.completed if completed?
    other_transfers.any?
  end

  def completed?
    !stripe_transfer_id.nil?
  end

  def new_sponsor_email_sent?
    new_sponsor_email_sent_at.present?
  end

  def new_sponsor_email_sent!
    update!(new_sponsor_email_sent_at: Time.current)
  end

  def stripe_transfer_url
    return unless completed?
    "#{GitHub.stripe_connect_dashboard_base_url}/connect/transfers/#{stripe_transfer_id}"
  end

  def truncated_stripe_transfer_id
    return unless stripe_transfer_id
    T.must(stripe_transfer_id)[-6..-1]
  end

  def zuora_payment_url
    "#{GitHub.zuora_host}/apps/NewPayment.do?method=view&id=#{zuora_payment_id}"
  end

  def truncated_zuora_payment_id
    zuora_payment_id[-6..-1]
  end

  # Public: Get all payout ledger entries for this transfer.
  #
  # Returns a Billing::PayoutsLedgerEntry ActiveRecord::Relation.
  def ledger_entries
    return Billing::PayoutsLedgerEntry.none unless completed? && stripe_connect_account

    T.must(stripe_connect_account)
      .ledger_entries
      .for_sponsors_listing(sponsors_listing_id)
      .with_primary_reference_id(stripe_transfer_id)
  end

  def sponsorship_expires_at
    sponsorship&.expires_at
  end

  def sponsors_listing_slug
    sponsors_listing&.slug
  end

  private

  def strip_note_whitespace
    self.new_sponsor_email_note = new_sponsor_email_note&.strip&.presence
  end

  def sponsors_listing_must_be_approved
    return if sponsors_listing&.approved?
    errors.add(:sponsors_listing, "must be approved")
  end

  def expires_at_is_date_in_the_future
    return if expires_at.blank?
    return if expires_at > Date.current

    errors.add(:expires_at, "must be a valid date in the future")
  end

  def number_of_months_is_a_positive_integer
    return unless @number_of_months
    return if @number_of_months > 0

    errors.add(:number_of_months, "must be an integer greater than 0")
  end
end
