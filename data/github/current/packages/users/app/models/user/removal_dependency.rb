# typed: false
# frozen_string_literal: true

# User removal and destruction
#
# == How to synchronously delete a user
#
# While the preferred way to delete a user is User#async_destroy, in cases where a synchronous
# delete is needed, User#remove! should be preferred over the standard User#destroy! process.
#
#   user = User.first # or whoever
#   user.remove!
#
# Deleting a user runs many callbacks inside the destroy! transaction, and some of those callbacks
# are idempotent and don't necessarily need to be ran as part of the transaction provided you are
# okay with never coming back from the User#remove! operation. User#never_deletable? should be
# used as a preflight check prior to calling User.remove! for this very reason.
#
# User#remove! should be fully idempotent and may be called repeatedly in cases where a job fails.
# If removal fails reliably for a user in any state it's a bug and this logic must be modified to
# handle removing users in that state.

module User::RemovalDependency
  include ActiveSupport::Concern

  # Public: Indicates if this user cannot be deleted by
  # anyone, including site admins.
  def never_deletable?
    legal_hold? ||
      system_account? ||
      has_trade_restrictions? ||
      owns_organizations? ||
      owns_a_business?
  end

  # Public: Run idempotent callbacks then destroy!
  def remove!
    self.destroying = true
    destroy_user_callbacks.before_transaction(self)
    destroy!
  end

  private

  def has_trade_restrictions?
    self.trade_screening_record.delete_restricted?
  end

  def owns_organizations?
    catch(:abort) do
      return !self.verify_no_owned_organizations
    end
    true
  end

  def owns_a_business?
    catch(:abort) do
      return !self.verify_no_owned_businesses
    end
    true
  end
end
