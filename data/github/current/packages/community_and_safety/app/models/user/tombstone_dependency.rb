# typed: false
# frozen_string_literal: true

module User::TombstoneDependency
  extend ActiveSupport::Concern

  included do
    after_destroy_commit :destroy_user_create_tombstone_after_commit
  end

  private

  def destroy_user_create_tombstone_after_commit
    # Bot logins cannot be tombstoned
    return if bot?

    # A soft deleted org shouldn't be tombstoned since the login isn't available for use while the
    # org is in the soft deleted state. This is because soft deletion doesn't delete the org's
    # record. Considering the standard soft deletion period is 90 days, which is similar to the
    # tombstoning period, tombstoning is bypassed here to ensure a similar experience on login
    # reservation.
    return if organization? && soft_deleted_organization

    ReservedLogin.tombstone!(login)
  rescue ActiveRecord::RecordInvalid => error
    Failbot.report(error)
  end
end
