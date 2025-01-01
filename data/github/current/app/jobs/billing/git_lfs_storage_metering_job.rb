# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

require "github/media_blob"

module Billing

  # This is the LFS storage reconciliation job. It queries the LFS storage that
  # is actually used per repository network (according to the database) and
  # compares it to the storage use tracked by the billing system. If there is
  # a difference, then we emit a correction value.
  #
  class GitLfsStorageMeteringJob < ApplicationJob
    # Unfortunately, we need to use the write connection by default here to avoid WaitForReplication errors
    # as discussed with @arthurschreiber on Slack.
    default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

    class DuplicateBatchError < StandardError; end
    class KvReadError < StandardError; end

    DB_QUERY_BATCH_SIZE = 100
    PREVIOUS_RUN_KV_KEY = "billing.lfs.previous_run"
    PREVIOUS_NW_KV_KEY = "billing.lfs.previous_network_id"

    # TODO: Eventually, we will run the job on a longer cadence to minimize
    # DB load. Maybe we'll run it every 12h as this should be precise enough
    # for billing.  Currently, a sequence of jobs takes ~6h to run.  That
    # means an 8h cadence is the minimum cadence to avoid overlapping runs.
    # If several sequences do overlap, however, the later ones will simply
    # stop with a DuplicateBatchError when they find a higher
    # "previous_network_id" value set in the KV store by a job from the
    # earlier sequence.
    RECONCILIATION_INTERVAL = T.let(8.hours, ActiveSupport::Duration)

    schedule interval: RECONCILIATION_INTERVAL, condition: -> { GitHub.billing_enabled? && !GitHub.enterprise? }

    # Ensure only one of these jobs with the same arguments is being worked at a time.
    # It is possible that two consecutive batch jobs are running in parallel as we start the
    # next job before we emit the results to the billing platform.
    locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

    queue_as :lfs_billing

    exempt_from_tenant_context_requirement

    discard_on(StandardError) do |job, error|
      args = job.arguments.first
      args = {} if args.nil?
      current_run, previous_network_id, run_interval = args.values_at(:current_run, :previous_network_id, :run_interval)

      GitHub.dogstats.increment("billing.lfs.error", tags: ["context:git_lfs_storage_metering_job", "exception:#{error.class.name}"])
      Failbot.report(error)
      GitHub.logger.error({
        exception: error,
        "gh.job.name": job.class.name,
        "gh.billing.lfs.storage_metering_job.current_run": current_run,
        "gh.billing.lfs.storage_metering_job.previous_network_id": previous_network_id,
        "gh.billing.lfs.storage_metering_job.run_interval": run_interval,
      })
    end

    retry_on_recoverable_exceptions
    retry_on_dirty_exit

    RETRYABLE_ERRORS = T.let([
      Billing::GitLfsStorageMeteringJob::KvReadError,
      Faraday::ConnectionFailed,
      Faraday::SSLError,
      Faraday::TimeoutError,
      Freno::Error,
      GitHub::KV::MissingConnectionError,
      GitHub::Restraint::UnableToLock,
      Net::OpenTimeout,
      Net::ReadTimeout,
      WaitForReplication::DataUnavailable,
    ].freeze, T::Array[T.untyped])

    RETRYABLE_ERRORS.each do |error_class|
      retry_on error_class, wait: 5.seconds, attempts: 3 do |job, error|
        args = job.arguments.first
        args = {} if args.nil?
        current_run, previous_network_id, run_interval = args.values_at(:current_run, :previous_network_id, :run_interval)

        GitHub.dogstats.increment("billing.lfs.error", tags: ["context:git_lfs_storage_metering_job", "exception:#{error.class.name}"])
        Failbot.report(error)
        GitHub.logger.error({
          exception: error,
          "gh.job.name": job.class.name,
          "gh.billing.lfs.storage_metering_job.current_run": current_run,
          "gh.billing.lfs.storage_metering_job.previous_network_id": previous_network_id,
          "gh.billing.lfs.storage_metering_job.run_interval": run_interval,
        })
      end
    end

    sig { params(current_run: T.nilable(Time), previous_network_id: T.nilable(Integer), run_interval: T.nilable(Integer)).void }
    def perform(current_run: nil, previous_network_id: nil, run_interval: nil)
      if current_run.nil?
        # Start with the first batch of a new reconcile billing cycle for all repository networks
        current_run = Time.now.beginning_of_hour
        prev_run = previous_metering_run
        prev_run = current_run - RECONCILIATION_INTERVAL if prev_run.nil?
        run_interval = (current_run - prev_run).seconds.in_hours.to_i
        previous_network_id = nil

        # Skip the run if we already ran within the reconciliation interval
        # and this is the first time this scheduled job is being attempted.
        if run_interval < RECONCILIATION_INTERVAL.in_hours && self.executions == 1
          GitHub.logger.info("Reconcile billing cycle aborted as interval since last run is less than reconciliation interval.", {
            "gh.billing.lfs.storage_metering_job.current_run": current_run,
            "gh.billing.lfs.storage_metering_job.run_interval": run_interval,
          })
          return
        end

        # Update the last metering run _before_ we do anything (in particular before we start emitting metrics).
        # This way should never start reconcile billing cycle twice for a given period.
        start_new_metering_run(current_run)

        GitHub.logger.info("Start new reconcile billing cycle with first batch.", {
          "gh.billing.lfs.storage_metering_job.current_run": current_run,
          "gh.billing.lfs.storage_metering_job.run_interval": run_interval,
        })
      elsif previous_network_id && run_interval
        # Continue with another batch of a previously started reconcile billing cycle

        # First, check if we already processed this batch. This can happen if this job was restarted or the job of the
        # previous batch was restarted.
        if already_processed_network_id?(previous_network_id)
          raise DuplicateBatchError, "duplicate batch: current_run=#{current_run.inspect} "\
            "previous_network_id=#{previous_network_id.inspect} run_interval=#{run_interval.inspect}"
        end

        GitHub.logger.info("Reconcile billing cycle with subsequent batch.", {
          "gh.billing.lfs.storage_metering_job.current_run": current_run,
          "gh.billing.lfs.storage_metering_job.previous_network_id": previous_network_id,
          "gh.billing.lfs.storage_metering_job.run_interval": run_interval,
        })
      else
        raise ArgumentError, "invalid arguments: current_run=#{current_run.inspect} "\
          "previous_network_id=#{previous_network_id.inspect} run_interval=#{run_interval.inspect}"
      end

      # Query the DB for storage use of all LFS objects in repository networks with an ID
      # greater than `previous_network_id`. `previous_network_id` is `nil` if we are starting a new
      # reconcile billing cycle for all repository networks.
      starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      results, is_last_batch, last_nw_of_batch = GitHub.dogstats.distribution_time("billing.lfs.dist.batch_query_storage_use") do
        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::MediaBlob.query_owner_network_storage(previous_network_id, DB_QUERY_BATCH_SIZE)
        end
      end
      ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      GitHub.logger.info("Batch query completed.", {
        "gh.billing.lfs.storage_metering_job.current_run": current_run,
        "gh.billing.lfs.storage_metering_job.previous_network_id": last_nw_of_batch,
        "gh.billing.lfs.storage_metering_job.query_runtime": (ending - starting),
        "gh.billing.lfs.storage_metering_job.run_interval": run_interval,
      })

      # Update the previously processed network ID _before_ we start the next batch _and_ emitting metrics.
      # This way we don't overcharge the customer if this job is restarted after this point (because this
      # would trigger the next batch, again, and it would emit metrics, again).
      set_processed_network_id(previous_network_id) if previous_network_id

      if is_last_batch
        GitHub.logger.info("Last batch found. Reconcile billing cycle completed.", {
          "gh.billing.lfs.storage_metering_job.current_run": current_run,
          "gh.billing.lfs.storage_metering_job.run_interval": run_interval,
        })
      else
        # Enqueue the next batch of this metering run _before_ we start emitting metrics.
        # This way we don't overcharge the customer of this batch in case of a crash
        # during the emit code.
        GitHub.logger.info("Queuing next batch.", {
          "gh.billing.lfs.storage_metering_job.current_run": current_run,
          "gh.billing.lfs.storage_metering_job.last_network_id_of_batch": last_nw_of_batch,
          "gh.billing.lfs.storage_metering_job.previous_network_id": previous_network_id,
          "gh.billing.lfs.storage_metering_job.run_interval": run_interval,
        })
        GitLfsStorageMeteringJob.perform_later(
          current_run: current_run,
          previous_network_id: last_nw_of_batch,
          run_interval: run_interval)
      end

      # Emit the usage to the billing system
      GitHub.dogstats.distribution_time("billing.lfs.dist.reconcile_storage_use") do
        reconcile_storage_use(results, current_run)
      end
    end

    # Start a new reconcile billing cycle by setting the time _until_ we captured the storage use on the last
    # reconcile billing cycle.
    sig { params(timestamp: Time).void }
    def start_new_metering_run(timestamp)
      ActiveRecord::Base.connected_to(role: :writing) do
        # Clear the processed network IDs, meaning we start a new reconcile billing cycle.
        Assets::KV.store.del(PREVIOUS_NW_KV_KEY)

        # Set the time _until_ we captured the storage use on the last metering run.
        Assets::KV.store.set(PREVIOUS_RUN_KV_KEY, timestamp.to_i.to_s, expires: 2.days.from_now)
      end
    end

    # Get the time _until_ we captured the storage use on the last metering run.
    sig { returns(T.nilable(Time)) }
    def previous_metering_run
      # Connect with writing role to ensure we are not reading outdated/cached values.
      timestamp = ActiveRecord::Base.connected_to(role: :writing) do
        result = Assets::KV.store.get(PREVIOUS_RUN_KV_KEY)
        if result.ok?
          result.value!
        else
          raise KvReadError
        end
      end
      Time.at(timestamp.to_i) if timestamp
    end

    # Set the network ID _until_ we captured the storage use on the current metering run.
    # Note, we sequentially walk thorugh the network ID space and therefore this number is monotone increasing.
    sig { params(nw_id: Integer).void }
    def set_processed_network_id(nw_id)
      ActiveRecord::Base.connected_to(role: :writing) do
        Assets::KV.store.set(PREVIOUS_NW_KV_KEY, nw_id.to_s, expires: 2.days.from_now)
      end
    end

    # Return true if a batch for network IDs after the given network ID was already processed.
    sig { params(nw_id: Integer).returns(T::Boolean) }
    def already_processed_network_id?(nw_id)
      # Connect with writing role to ensure we are not reading outdated/cached values.
      prev_nw_id = ActiveRecord::Base.connected_to(role: :writing) do
        result = Assets::KV.store.get(PREVIOUS_NW_KV_KEY)
        if result.ok?
          result.value!
        else
          raise KvReadError
        end
      end
      if prev_nw_id
        prev_nw_id.to_i >= nw_id
      else
        false
      end
    end

    # Check the storage use tracked in the billing system and emit the delta
    sig { params(results: T::Array[T.untyped], timestamp: Time).void }
    def reconcile_storage_use(results, timestamp)
      client = Billing::Platform::Api::Client.new

      # Preload all necessary Customer records
      customer_ids = results.map { |entry| entry[:customer_id] }.compact.uniq
      customers = Customer.where(id: customer_ids).index_by(&:id)

      results.each do |entry|
        customer = customers[entry[:customer_id]]
        usage = client.get_watermark_level(
          usage_entity_id: entry[:customer_id],
          sku: "git_lfs_storage",
          org_id: entry[:organization_id],
          repo_id: entry[:root_id],
        )

        if usage.is_a?(Billing::Platform::Api::Error)
          GitHub.dogstats.increment("billing.lfs.error", tags: ["context:reconcile_storage_use_method", "exception:#{usage.class.name}"])
          GitHub.logger.error("Billing platform error", {
            exception: usage,
            "gh.customer.id": entry[:customer_id],
            "gh.org.id": entry[:organization_id],
            "gh.repo.id": entry[:root_id],
          })
          next
        end

        if !(usage.is_a?(Hash) && usage.has_key?(:quantity))
          GitHub.dogstats.increment("billing.lfs.error", tags: ["context:reconcile_storage_use_method", "exception:KeyError"])
          usage_keys = usage.keys.join(",") if usage.is_a?(Hash)
          GitHub.logger.error("Unexpected billing platform error", {
            exception: KeyError.new("key not found: :quantity"),
            "gh.billing.get_watermark_usage.result.type": usage.class.name,
            "gh.billing.get_watermark_usage.result.keys": usage_keys,
            "gh.customer.id": entry[:customer_id],
            "gh.org.id": entry[:organization_id],
            "gh.repo.id": entry[:root_id],
          })
          next
        end

        billed_storage = usage[:quantity]
        measured_storage = entry[:size_in_gb]
        delta = measured_storage - billed_storage

        # Only emit a correction if the delta is larger than 1MiB
        # or the repository now has no active Git LFS objects.
        if delta.abs > 0.001 || (billed_storage > 0.0 && measured_storage == 0.0)
          GlobalInstrumenter.instrument("billing_platform.metered_usage", {
            sku: "git_lfs_storage",
            quantity: delta,
            usage_at:  Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: 0),
            source_uri: "gid://git-hub/reconcile/#{entry[:root_id]}",
            entity: {
              customer_id: entry[:customer_id],
              repo_id: entry[:root_id],
              organization_id: entry[:organization_id]
            },
          })
        end
      end
    end

  end
end
