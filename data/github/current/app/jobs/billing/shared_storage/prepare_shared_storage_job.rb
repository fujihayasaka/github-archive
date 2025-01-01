# typed: true
# frozen_string_literal: true

module Billing
  module SharedStorage
    # *PrepareSharedStorageJob* should be called when an owner has begun using
    # storage services. E.g. when a package is published.
    #
    # This will create an entry for the given (repository, owner) combination
    # in the shared storage usage table for aggregation.
    class PrepareSharedStorageJob < ApplicationJob
      queue_as :billing_shared_storage
      retry_on_dirty_exit

      # There's a database uniqueness constraint on (repository_id, owner_id)
      # This lock avoids unnecessary `create!` attempts that will fail the uniqueness constraint
      locked_by  timeout: 10.minutes, key: ->(job) do
        args = job.arguments.first
        "#{args[:repository_id]},#{args[:owner_id]}"
      end

      discard_on(StandardError) do |_job, error|
        Failbot.report(error)
      end

      def perform(repository_id: nil, owner_id:, billable_owner_type:, billable_owner_id:, repository_visibility:)
        # Respository_id is nullable to account for shared storage at the owner level not associated with a specific repo.
        # There should be only one record per owner_id with a NULL repo_id.
        # In order to enforce a unique constraint, we are reserving the 0 id as a null value
        repository_id ||= 0

        with_write do
          Billing::SharedStorage::CurrentUsage.create!(
            repository_id: repository_id,
            owner_id: owner_id,
            billable_owner_type: billable_owner_type,
            billable_owner_id: billable_owner_id,
            repository_visibility: repository_visibility,
            effective_at: Time.current.beginning_of_hour
          )
        end
      rescue ActiveRecord::RecordNotUnique
        # This is fine, any updates to the existing usage record will be updated on aggregation
      rescue ActiveRecord::RecordInvalid
        # TODO: increment a metric and/or log this case once we fully implement the new shared storage
      end
    end
  end
end
