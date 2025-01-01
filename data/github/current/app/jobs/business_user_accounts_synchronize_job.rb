# typed: strict
# frozen_string_literal: true

class BusinessUserAccountsSynchronizeJob < ApplicationJob
  extend T::Sig
  extend T::Helpers

  queue_as :business_user_accounts_synchronize

  MAX_CONCURRENT_JOBS = T.let(1, Integer)
  RESTRAINT_LOCK_TTL = T.let(30.minutes.to_i, Integer)
  LOCK_KEY = "business-user-accounts-synchronize:"

  MAX_RETRY_ATTEMPTS = T.let(3, Integer)
  RETRY_DELAY = T.let(5.minutes, ActiveSupport::Duration)

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  RETRYABLE_ERRORS = T.let([
    ActiveRecord::RecordNotFound,
    GitHub::Restraint::UnableToLock,
  ].freeze, T::Array[T.class_of(StandardError)])

  RETRYABLE_ERRORS.each do |error|
    retry_on error, wait: RETRY_DELAY, attempts: MAX_RETRY_ATTEMPTS do |_job, error|
      Failbot.report(error)
    end
  end

  resolve_tenant_context do |args|
    Business.find_by(id: args[:business_id])
  end

  # This job searches for BusinessUserAccounts that are missing and creates them, and searches for BusinessUserAccounts
  # that are no longer needed and deletes them.
  #
  # business_id - Required integer representing the ID of the Business for which BusinessUserAccounts will be synchronised.
  #
  # Returns nothing
  sig { params(business_id: Integer).void }
  def perform(business_id:)
    business = T.let(Business.find_by(id: business_id), T.nilable(Business))

    return unless business.present?
    return unless business.feature_enabled?(:business_synchronize_accounts_job)

    lock!(T.must(business.id)) do

      bua_account_sync = BusinessUserAccount::SynchronizeAccounts.new(business: business)

      bua_account_sync.add_missing_accounts
      bua_account_sync.remove_orphaned_accounts
    end
  end

  private

  sig { params(business_id: Integer, block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def lock!(business_id, &block)
    restraint = GitHub::Restraint.new
    lock_key = "#{LOCK_KEY}#{business_id}"

    restraint.lock!(lock_key, MAX_CONCURRENT_JOBS, RESTRAINT_LOCK_TTL) do
      yield
    end
  end
end
