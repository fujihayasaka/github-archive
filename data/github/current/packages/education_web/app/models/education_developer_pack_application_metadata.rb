# typed: strict
# frozen_string_literal: true

class EducationDeveloperPackApplicationMetadata < ApplicationRecord::Domain::Users
  belongs_to :user

  enum :application_type, { student: 0, faculty: 1 }

  validates :user, presence: true
  validates :application_type, presence: true
  validates :external_discount_request_id, numericality: { other_than: 0, allow_nil: true, message: "cannot be zero" }

  validate :user_does_not_have_disqualifying_application, on: :create

  scope :pending, -> { where(approved_at: nil, denied_at: nil) }
  scope :approved, -> { where.not(approved_at: nil) }

  # Override the database column to return calculated expiration date if null
  # @return [Time, nil] The expiration date of the developer pack application
  sig { returns(T.nilable(Time)) }
  def expires_at
    db_value = read_attribute(:expires_at)
    return db_value if db_value.present?
    return nil unless applied_at.present?

    applied_at + 2.years
  end

  sig { returns(T::Boolean) }
  def pending?
    !approved? && !denied?
  end

  sig { returns(T::Boolean) }
  def expired?
    exp = expires_at
    if exp.nil?
      false
    else
      exp < Time.now
    end
  end

  sig { returns(T::Boolean) }
  def approved?
    approved_at.present?
  end

  sig { returns(T::Boolean) }
  def coupon_applied?
    approved? && (
      T.must(user).student_developer_pack_coupon? || T.must(user).faculty_developer_pack_coupon?
    )
  end

  sig { returns(T::Boolean) }
  def revoked?
    approved? && !expired? && denied?
  end

  sig { returns(T::Boolean) }
  def denied?
    denied_at.present?
  end

  sig { returns(Symbol) }
  def status
    if approved?
      if expired?
        :expired
      elsif denied?
        :revoked
      elsif coupon_applied?
        :coupon_applied
      else
        :approved
      end
    elsif denied?
      :denied
    else
      :pending
    end
  end

  sig { returns(String) }
  def status_label
    if status == :coupon_applied
      "Coupon applied"
    else
      status.to_s.capitalize
    end
  end

  private

  sig { void }
  def user_does_not_have_disqualifying_application
    # Help Sorbet figure out that the user is non-nil for the rest of the method
    u = self.user
    return unless u

    disqualifying_applications = u.developer_pack_application_metadata.pending
    if disqualifying_applications.exists?
      errors.add(:user, "has an existing pending or approved application")
    end
  end
end
