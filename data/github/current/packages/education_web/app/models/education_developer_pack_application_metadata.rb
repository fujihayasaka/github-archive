# typed: strict
# frozen_string_literal: true

class EducationDeveloperPackApplicationMetadata < ApplicationRecord::Domain::Users
  belongs_to :user

  enum :application_type, { student: 0, faculty: 1 }

  validates :user, presence: true
  validates :application_type, presence: true

  validate :user_does_not_have_disqualifying_application, on: :create

  scope :pending, -> { where(approved_at: nil, denied_at: nil) }
  scope :approved, -> { where.not(approved_at: nil) }
  scope :expires_in_the_future, -> { where("expires_at > ?", Time.now) }

  sig { returns(T::Boolean) }
  def pending?
    !approved? && !denied?
  end

  sig { returns(T::Boolean) }
  def expired?
    expires_at.present? && expires_at < Time.now
  end

  sig { returns(T::Boolean) }
  def approved?
    approved_at.present?
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
      else
        :approved
      end
    elsif denied?
      :denied
    else
      :pending
    end
  end

  private

  sig { void }
  def user_does_not_have_disqualifying_application
    # Help Sorbet figure out that the user is non-nil for the rest of the method
    u = self.user
    return unless u

    disqualifying_applications = u.developer_pack_application_metadata.pending.or(
      u.developer_pack_application_metadata.approved.expires_in_the_future,
    )

    if disqualifying_applications.exists?
      errors.add(:user, "has an existing pending or approved application")
    end
  end
end
