# typed: strict
# frozen_string_literal: true

class CouponBatch < ApplicationRecord::Domain::Billing
  include GitHub::IssueReferenceParser
  include GitHub::IssueReferenceResolution

  COUPON_KEYS = %w(discount duration expires_at group note staff_actor_only).freeze
  PRODUCT_KEYS = %w(product_type product_key).freeze
  QUANTITY_LIMIT = BillingCouponGeneratorJob::BATCH_LIMIT

  belongs_to :actor, class_name: "User"
  has_many :coupons, dependent: :nullify

  enum :status, {
    pending: 0,
    success: 1,
    failed: 2,
    retrying: 3
  }, default: :pending

  validates_presence_of :actor
  validates_presence_of :quantity
  validates_numericality_of :quantity, greater_than: 0, less_than_or_equal_to: QUANTITY_LIMIT, only_integer: true
  validates_presence_of :generation_params
  validates_presence_of :tracking_issue
  validates :prefix, length: { maximum: 64 }
  validates_format_of :prefix, allow_blank: true, with: /\A[#{Coupon::FORMAT_CHARACTERS}]+\z/i
  validate :validate_generation_params
  validate :validate_tracking_issue_exists

  after_create_commit :enqueue_coupon_generator_job

  serialize :generation_params, coder: JSON

  sig { returns(T::Hash[String, T.untyped]) }
  def generation_params
    self[:generation_params] || {}
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def coupon_params
    default_coupon_params.merge(generation_params.slice(*COUPON_KEYS).symbolize_keys)
  end

  sig { returns(T::Hash[Symbol, T.nilable(String)]) }
  def product_params
    generation_params.slice(*PRODUCT_KEYS).symbolize_keys
  end

  sig { returns(String) }
  def generate_unique_code
    [prefix.presence, SecureRandom.hex(4)[0, 7]].compact.join("-")
  end

  sig { returns(T.nilable(Billing::Public::Product::ProductIdentifier)) }
  def product_target
    return unless product_params[:product_type].present? && product_params[:product_key].present?
    Billing::Public::Product::ProductIdentifier.new(**T.unsafe(product_params))
  end

  private

  sig { returns(T::Hash[Symbol, String]) }
  def default_coupon_params
    {
      note: "Bulk generated coupon",
      group: "si-bulk",
    }
  end

  sig { void }
  def enqueue_coupon_generator_job
    BillingCouponGeneratorJob.perform_later(self)
  end

  sig { void }
  def validate_generation_params
    return if errors[:generation_params].any?

    # Build a temporary coupon to validate the params (only with allowed keys)
    allowed_params = generation_params.slice(*COUPON_KEYS)
    validation_coupon = Coupon.new(allowed_params)

    return if validation_coupon.valid?

    # Add each validation error to this record
    validation_coupon.errors.each do |error|
      errors.add(error.attribute, error.message)
    end
  end

  sig { void }
  def validate_tracking_issue_exists
    return if errors[:tracking_issue].any?
    return if tracking_issue.blank?

    # Parse the issue reference (supports formats like "owner/repo#123" or full URLs)
    issue = resolve_issue_reference(tracking_issue, nil)

    unless issue
      errors.add(:tracking_issue, "must reference an existing issue")
    end
  end
end
