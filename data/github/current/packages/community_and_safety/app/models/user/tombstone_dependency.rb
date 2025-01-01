# typed: true
# frozen_string_literal: true

module User::TombstoneDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  private

  def tombstone_user_login
    # Determine if there was a change in login during the save that triggered the callbacks to run
    return if !destroyed? && saved_change_to_login? && !GitHub.flipper[:user_update_tombstone].enabled?

    # Bot logins cannot be tombstoned
    return if bot?

    # A soft deleted org shouldn't be tombstoned since the login isn't available for use while the
    # org is in the soft deleted state. This is because soft deletion doesn't delete the org's
    # record. Considering the standard soft deletion period is 90 days, which is similar to the
    # tombstoning period, tombstoning is bypassed here to ensure a similar experience on login
    # reservation.
    return if organization? && soft_deleted_organization

    # EMUs do not need to be tombstoned because the Enterprise has full control
    # over their users, so there isn't an abuse vector here.
    return if is_enterprise_managed?

    login_to_tombstone = destroyed? ? login : login_before_last_save
    ReservedLogin.tombstone!(login_to_tombstone)
  rescue ActiveRecord::RecordInvalid => error
    Failbot.report(error)
  end
end
