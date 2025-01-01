# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module AlertPrioritization
    module CopilotPromptExperiments
      # Generates CSV file header
      # Starts parallel execution of OwnerRepoClassificationSliceJob jobs.
      # Watches for the completion of OwnerRepoClassificationSliceJob jobs and sends an email with the CSV file when all jobs are done.
      class OwnerRepoClassificationControlJob < ApplicationJob
        include ::GitHub::SecurityCenter::LoggingHelper
        include ::CopilotChatHelper
        include GitHub::Memoizer


        CSV_FEATURE = "alert_prioritization_copilot_prompt_experiment"

        DEFAULT_CSV_EXPIRY = T.let(1.month, ActiveSupport::Duration)
        DEFAULT_COPILOT_API_MAX_RETRIES = 3
        DEFAULT_PROMPT_DEPLOYED_TO_PROD = T.let(%{
          Only use code search.
          Is this repository part of an application that is deployed to production?
          Answer with true or false.
        }.squish, String)
        DEFAULT_PROMPT_HANDLES_PII = T.let(%{
          Only use code search.
          Does this repository handle PII?
          Check for handling of email, phone, city, firstname, lastname and other personal information.
          Answer with true or false.
        }.squish, String)
        DEFAULT_PROMPT_BUSINESS_CRITICAL = T.let(%{
          Only use code search.
          Is this repository part of an application that is business critical?
          Check things like code, configurations, documentation, etc. that imply whether or not the repository is business critical.
          Answer with true or false.
        }.squish, String)
        DEFAULT_PROMPT_INTERNET_ACCESSIBLE = T.let(%{
          Ignore the repository's visibility.
          Only use code search. Is this repository part of an application that is internet accessible?
          Answer with true or false.
        }.squish, String)

        # Using separate queue for control vs. slice jobs to allow for different throttling settings.
        queue_as :alert_prioritization_copilot_prompt_experiments_control

        retry_on_dirty_exit
        retry_on_recoverable_exceptions

        locked_by timeout: ApplicationJob::DEFAULT_TIMEOUT, key: ->(job) do
          DEFAULT_LOCK_STRINGIFY_PROC.call([job.owner.id])
        end

        before_perform do |job|
          if !job.actor.most_recent_session.try(:active?)
            raise AlertPrioritizationHelper::UserMissingActiveSessionError
          end
        end

        # KV key for the job status.
        sig { params(owner: ::User).returns(String) }
        def self.job_id(owner)
          "security_center.alert_prioritization.copilot_prompt_experiments.owner_repo_classification_control_job.#{owner.id}"
        end

        sig { returns(T::Boolean) }
        def first_run?
          T.cast(job_arguments.fetch(:first_run, true), T::Boolean)
        end

        # The job status.
        sig { params(owner: ::User).returns(T.nilable(JobStatus)) }
        def self.status(owner)
          # Using write connection to prevent any kind of replication lag affecting getting this status between runs of the job.
          ActiveRecord::Base.connected_to(role: :writing) do
            JobStatus.find(job_id(owner))
          end
        end

        sig { override.params(args: T.untyped, kwargs: T.untyped).void }
        def initialize(*args, **kwargs)
          # Create an initial value for blob_storage_key that TimedJob will forward to subsequent jobs in the sequence.
          if kwargs[:blob_storage_key].blank?
            kwargs[:blob_storage_key] = SecureRandom.uuid
          end

          super(*T.unsafe(args), **kwargs)
        end

        around_perform do |job, block|
          job_status = job.upsert_job_status(throttle: true)

          if job.job_enabled?
            job_status.started! if job.first_run?
            block.call
          else
            job_status.success!
          end
        end

        sig do
          override.params(
            actor: ::User,
            owner: T.any(::Organization, ::User),
            first_run: T::Boolean,
            blob_storage_key: T.nilable(String), # A unique value to use as the ID of the Azure file. If nil, one will be created.
            csv_expiry: ActiveSupport::Duration,
            copilot_api_max_retries: Integer,
            prompt_deployed_to_prod: T.nilable(String), # If nil, this prompt will be skipped.
            prompt_handles_pii: T.nilable(String), # If nil, this prompt will be skipped.
            prompt_business_critical: T.nilable(String), # If nil, this prompt will be skipped.
            prompt_internet_accessible: T.nilable(String), # If nil, this prompt will be skipped.
            prompt_experimental: T.nilable(String), # If nil, this prompt will be skipped.
            kwargs: T.untyped
          ).void
        end
        def perform(
          actor:,
          owner:,
          first_run: true,
          blob_storage_key: nil,
          csv_expiry: DEFAULT_CSV_EXPIRY,
          copilot_api_max_retries: DEFAULT_COPILOT_API_MAX_RETRIES,
          prompt_deployed_to_prod: DEFAULT_PROMPT_DEPLOYED_TO_PROD,
          prompt_handles_pii: DEFAULT_PROMPT_HANDLES_PII,
          prompt_business_critical: DEFAULT_PROMPT_BUSINESS_CRITICAL,
          prompt_internet_accessible: DEFAULT_PROMPT_INTERNET_ACCESSIBLE,
          prompt_experimental: nil,
          **kwargs
        )
          return if !job_enabled?

          job_status_0 = OwnerRepoClassificationSliceJob.status(owner, 0)
          job_status_1 = OwnerRepoClassificationSliceJob.status(owner, 1)
          jobs_running = job_status_0&.started? || job_status_1&.started?

          if first_run?
            if !jobs_running
              create_csv_file

              # Kick off slice jobs
              OwnerRepoClassificationSliceJob.perform_later(actor:, owner:, slice_id: 0, blob_storage_key:, copilot_api_max_retries:, prompt_deployed_to_prod:, prompt_handles_pii:, prompt_business_critical:, prompt_internet_accessible:, prompt_experimental:)
              OwnerRepoClassificationSliceJob.perform_later(actor:, owner:, slice_id: 1, blob_storage_key:, copilot_api_max_retries:, prompt_deployed_to_prod:, prompt_handles_pii:, prompt_business_critical:, prompt_internet_accessible:, prompt_experimental:)

              # Check back later.
              OwnerRepoClassificationControlJob.set(wait: 5.minutes).perform_later(
                actor:,
                owner:,
                first_run: false,
                blob_storage_key:,
                csv_expiry:,
                copilot_api_max_retries:,
                prompt_deployed_to_prod:,
                prompt_handles_pii:,
                prompt_business_critical:,
                prompt_internet_accessible:,
                prompt_experimental:,
              )
            else
              log_warn("Jobs are still running. Skipping CSV file creation.")
            end
          else
            if !jobs_running
              upsert_job_status.success!

              log_timing(step: "send csv ready email") do
                ::SecurityCenterMailer
                  .alert_prioritization_copilot_prompt_experiment_csv_ready(
                    actor:,
                    users_to_email: [actor],
                    owner:,
                    file_url: generate_csv_url,
                    file_expiration_time: Time.current + csv_expiry
                  ).deliver_later
              end
            else
              # At least one job is still running. Check back later.
              OwnerRepoClassificationControlJob.set(wait: 5.minutes).perform_later(
                actor:,
                owner:,
                first_run: false,
                blob_storage_key:,
                csv_expiry:,
                copilot_api_max_retries:,
                prompt_deployed_to_prod:,
                prompt_handles_pii:,
                prompt_business_critical:,
                prompt_internet_accessible:,
                prompt_experimental:,
              )
            end
          end
        end

        sig { override.returns(T.nilable(::User)) }
        def current_user
          actor
        end

        sig { void }
        def create_csv_file
          csv_headers = CSV.generate(write_headers: true, headers:
            OwnerRepoClassificationSliceJob.csv_headers_to_struct_fields(
              prompt_deployed_to_prod:,
              prompt_handles_pii:,
              prompt_business_critical:,
              prompt_internet_accessible:,
              prompt_experimental:
            ).keys) {}

          AlertPrioritizationHelper.with_retry(block_description: __method__.to_s) do
            log_timing(step: "create csv blob") do
              blob_storage_service.create(blob_storage_key)
              blob_storage_service.store(blob_storage_key, csv_headers, CSV_FEATURE)
            end
          end
        end

        sig { returns(String) }
        def generate_csv_url
          res, err = AlertPrioritizationHelper.with_retry(block_description: __method__.to_s) do
            log_timing(step: "fetch csv download url") do
              current_time_str = Time.current.strftime("%Y-%m-%dT%H-%M-%S")
              blob_url = T.let(
                blob_storage_service.retrieve(
                  blob_storage_key,
                  CSV_FEATURE,
                  "#{owner.display_login}.#{current_time_str}.#{T.must(self.class.name).demodulize}.csv",
                  csv_expiry
                ).try(:blob_url),
                T.nilable(String)
              )

              raise "Failed to retrieve the blob URL" if blob_url.blank?

              blob_url
            end
          end

          res
        end

        # Allows custom control of job status so it's maintained between calls
        sig { params(throttle: T::Boolean).returns(JobStatus) }
        def upsert_job_status(throttle: false)
          ttl = 10.minutes
          job_id = self.class.job_id(owner)
          existing_job_status = self.class.status(owner)
          job_status_in_progress = existing_job_status && T.let(!existing_job_status.finished?, T::Boolean)
          job_status = job_status_in_progress ? existing_job_status : nil

          update_job_status = -> do
            if job_status.present?
              # Reset the job status' TTL.
              job_status.ttl = ttl
              job_status.save
            else
              job_status = T.cast(JobStatus.create({ id: job_id, ttl: }), JobStatus)
            end
          end

          if throttle
            # When run from around_perform, throttle writes to KV.
            ApplicationRecord::Domain::KeyValues.throttle_writes_with_retry { update_job_status.call }
          else
            # When kicking off job initially, don't throttle writes to KV.
            update_job_status.call
          end

          T.must(job_status)
        end

        sig { returns(::SecurityCenter::Export::BlobStorageService) }
        memoize def blob_storage_service
          ::SecurityCenter::Export::BlobStorageService.get
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def job_arguments
          arguments[0] || {}
        end

        sig { returns(::User) }
        def actor
          job_arguments.fetch(:actor)
        end

        sig { returns(T.any(::Organization, ::User)) }
        def owner
          job_arguments.fetch(:owner)
        end

        sig { returns(String) }
        def blob_storage_key
          job_arguments.fetch(:blob_storage_key)
        end

        sig { returns(ActiveSupport::Duration) }
        def csv_expiry
          job_arguments.fetch(:csv_expiry, DEFAULT_CSV_EXPIRY)
        end

        sig { returns(T.nilable(String)) }
        def prompt_deployed_to_prod
          job_arguments.fetch(:prompt_deployed_to_prod, DEFAULT_PROMPT_DEPLOYED_TO_PROD)
        end

        sig { returns(T.nilable(String)) }
        def prompt_handles_pii
          job_arguments.fetch(:prompt_handles_pii, DEFAULT_PROMPT_HANDLES_PII)
        end

        sig { returns(T.nilable(String)) }
        def prompt_business_critical
          job_arguments.fetch(:prompt_business_critical, DEFAULT_PROMPT_BUSINESS_CRITICAL)
        end

        sig { returns(T.nilable(String)) }
        def prompt_internet_accessible
          job_arguments.fetch(:prompt_internet_accessible, DEFAULT_PROMPT_INTERNET_ACCESSIBLE)
        end

        sig { returns(T.nilable(String)) }
        def prompt_experimental
          job_arguments.fetch(:prompt_experimental, nil)
        end

        sig { returns(Integer) }
        def copilot_api_max_retries
          job_arguments.fetch(:copilot_api_max_retries, DEFAULT_COPILOT_API_MAX_RETRIES)
        end

        sig { returns(T::Boolean) }
        def job_enabled?
          !::SecurityCenter::FeatureFlagHelper.disable_alert_prioritization_owner_csv_job?(owner)
        end

        sig { override.returns(T::Hash[Symbol, T.untyped]) }
        def logging_context
          super.merge({
            "gh.actor.id": actor.id,
            "gh.actor.name": actor.display_login,
            "gh.actor.type": actor.class.name,
            "gh.owner.id": owner.id,
            "gh.owner.login": owner.display_login,
            "gh.owner.type": owner.class.name,
            "gh.job.params.blob_storage_key": blob_storage_key,
            "gh.job.params.copilot_api_max_retries": copilot_api_max_retries,
          })
        end

        sig { override.returns(T::Hash[T.any(String, Symbol), T.untyped]) }
        def failbot_context
          super.merge({ app: "github-security-center" }).merge(logging_context)
        end

        sig { override.returns(T.nilable(Copilot::User)) }
        def current_copilot_user_v2
        end
      end
    end
  end
end
