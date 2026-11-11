# typed: true
# frozen_string_literal: true

class OFACDowngrade < ApplicationRecord::Collab
  validates :downgrade_on, presence: true

  scope :incomplete, -> { where(is_complete: false) }
  scope :completed, -> { where(is_complete: true) }
  scope :scheduled_for, ->(date) { where(downgrade_on: date) }

  APPEAL_BUFFER = 30.days

  validate :no_duplicate_incomplete_downgrade, on: :create

  def self.schedule_for(user)
    create(user_id: user.id, downgrade_on: GitHub::Billing.today + APPEAL_BUFFER)
  end

  def user
    @user ||= User.find_by(id: user_id)
  end

  def incomplete?
    !is_complete?
  end

  def run
    if user
      ::Billing::OFACCompliance::Downgrade.perform(user, actor: user)
    end

    update(is_complete: true)
  end

  def past_scheduled_run_date?
    (GitHub::Billing.today > T.must(downgrade_on)) && incomplete?
  end

  private

  def no_duplicate_incomplete_downgrade
    if OFACDowngrade.where(user_id: user_id, is_complete: false).exists?
      errors.add :base, "no duplicate downgrades can be created"
    end
  end
end
