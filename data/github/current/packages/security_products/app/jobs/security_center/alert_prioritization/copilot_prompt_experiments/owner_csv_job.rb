# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module AlertPrioritization
    module CopilotPromptExperiments
      # Generates and emails a CSV of Copilot's responses to prompts about each repo in an owner.
      class OwnerCsvJob < TimedJob
        include ::GitHub::SecurityCenter::LoggingHelper
        include ::CopilotChatHelper

        COPILOT_INTEGRATION_ID = "ghas-experimental-dev"
        CSV_FEATURE = "alert_prioritization_copilot_prompt_experiment"
        DEFAULT_CSV_EXPIRY = T.let(1.month, ActiveSupport::Duration)
        DEFAULT_COPILOT_API_MAX_RETRIES = 3
        DEFAULT_COPILOT_API_SLEEP_SEC = 2
        DEFAULT_ALWAYS_SEND_EMAIL = T.let(false, T::Boolean)
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
        RECENT_DEPLOYMENTS_WINDOW = T.let(6.months, ActiveSupport::Duration)

        class CopilotChatResponse < T::Struct
          const :answer, T.nilable(String)
          const :confidence, T.nilable(Integer)
          const :reasoning, T.nilable(String)
        end

        class CsvRow < T::Struct
          const :repo_id, T.nilable(Integer)
          const :repo_nwo, String
          const :repo_is_archived, T::Boolean
          const :repo_is_public, T::Boolean

          const :deployed_to_prod_known_answer, T.nilable(T::Boolean)
          const :deployed_to_prod_copilot_prompt, T.nilable(String)
          const :deployed_to_prod_copilot_answer, T.nilable(T::Boolean)
          const :deployed_to_prod_copilot_confidence, T.nilable(Integer)
          const :deployed_to_prod_copilot_reasoning, T.nilable(String)

          const :handles_pii_known_answer, T.nilable(T::Boolean)
          const :handles_pii_copilot_prompt, T.nilable(String)
          const :handles_pii_copilot_answer, T.nilable(T::Boolean)
          const :handles_pii_copilot_confidence, T.nilable(Integer)
          const :handles_pii_copilot_reasoning, T.nilable(String)

          const :business_critical_known_answer, T.nilable(T::Boolean)
          const :business_critical_copilot_prompt, T.nilable(String)
          const :business_critical_copilot_answer, T.nilable(T::Boolean)
          const :business_critical_copilot_confidence, T.nilable(Integer)
          const :business_critical_copilot_reasoning, T.nilable(String)

          const :internet_accessible_known_answer, T.nilable(T::Boolean)
          const :internet_accessible_copilot_prompt, T.nilable(String)
          const :internet_accessible_copilot_answer, T.nilable(T::Boolean)
          const :internet_accessible_copilot_confidence, T.nilable(Integer)
          const :internet_accessible_copilot_reasoning, T.nilable(String)
        end

        queue_as :alert_prioritization_copilot_prompt_experiments

        retry_on_dirty_exit
        retry_on_recoverable_exceptions

        locked_by timeout: ApplicationJob::DEFAULT_TIMEOUT, key: ->(job) do
          DEFAULT_LOCK_STRINGIFY_PROC.call([job.owner.id])
        end

        before_enqueue do |job|
          job.upsert_job_status
        end

        before_perform do |job|
          if !job.actor.most_recent_session.try(:active?)
            raise AlertPrioritizationHelper::UserMissingActiveSessionError
          end

          job.create_csv_file if !job.is_job_disabled_on_first_job?
        end

        around_perform do |job, block|
          job_status = job.upsert_job_status(throttle: true)

          if job.is_job_disabled_on_first_job?
            job_status.success!
          else
            job_status.started!
            block.call
          end
        end

        # KV key for the job status.
        sig { params(owner: ::User).returns(String) }
        def self.job_id(owner)
          "security_center.alert_prioritization.copilot_prompt_experiments.owner_csv_job.#{owner.id}"
        end

        # The job status.
        sig { params(owner: ::User).returns(T.nilable(JobStatus)) }
        def self.status(owner)
          ActiveRecord::Base.connected_to(role: :writing) do
            JobStatus.find(job_id(owner))
          end
        end

        sig { returns(T::Hash[Integer, Integer]) }
        attr_accessor :deployments

        sig { override.params(args: T.untyped, kwargs: T.untyped).void }
        def initialize(*args, **kwargs)
          @deployments = T.let({}, T::Hash[Integer, Integer])

          # Create an initial value for blob_storage_key that TimedJob will forward to subsequent jobs in the sequence.
          if kwargs[:blob_storage_key].blank?
            kwargs[:blob_storage_key] = SecureRandom.uuid
          end

          super(*T.unsafe(args), **kwargs)
        end

        sig do
          override.params(
            actor: ::User,
            owner: T.any(::Organization, ::User),
            blob_storage_key: T.nilable(String), # A unique value to use as the ID of the Azure file. If nil, one will be created.
            csv_expiry: ActiveSupport::Duration,
            copilot_api_max_retries: Integer,
            copilot_api_sleep_sec: Integer,
            prompt_deployed_to_prod: T.nilable(String), # If nil, this prompt will be skipped.
            prompt_handles_pii: T.nilable(String), # If nil, this prompt will be skipped.
            prompt_business_critical: T.nilable(String), # If nil, this prompt will be skipped.
            prompt_internet_accessible: T.nilable(String), # If nil, this prompt will be skipped.

            # For debugging purposes only!
            # If true, the CSV will be emailed even if feature flag "disable_alert_prioritization_owner_csv_job" is enabled mid-sequence.
            # This is useful for the case when the owner has many repos to process and we want to end processing early
            # but still see the Copilot responses for the repos that were processed.
            always_send_email: T::Boolean,

            kwargs: T.untyped
          ).void
        end
        def perform(
          actor:,
          owner:,
          blob_storage_key: nil,
          csv_expiry: DEFAULT_CSV_EXPIRY,
          copilot_api_max_retries: DEFAULT_COPILOT_API_MAX_RETRIES,
          copilot_api_sleep_sec: DEFAULT_COPILOT_API_SLEEP_SEC,
          prompt_deployed_to_prod: DEFAULT_PROMPT_DEPLOYED_TO_PROD,
          prompt_handles_pii: DEFAULT_PROMPT_HANDLES_PII,
          prompt_business_critical: DEFAULT_PROMPT_BUSINESS_CRITICAL,
          prompt_internet_accessible: DEFAULT_PROMPT_INTERNET_ACCESSIBLE,
          always_send_email: DEFAULT_ALWAYS_SEND_EMAIL,
          **kwargs
        )
          super(
            actor:,
            owner:,
            blob_storage_key:,
            csv_expiry:,
            copilot_api_max_retries:,
            copilot_api_sleep_sec:,
            prompt_deployed_to_prod:,
            prompt_handles_pii:,
            prompt_business_critical:,
            prompt_internet_accessible:,
            always_send_email:,
            **kwargs
          )
        end

        sig do
          override.params(
            args: T.untyped,
            offset_id: Integer,
            kwargs: T.untyped
          ).returns(T.all(T::Enumerable[T.untyped], Object))
        end
        def fetch_batch(*args, offset_id:, **kwargs)
          return [] if !job_enabled?

          log_timing(step: __method__) do
            repos = base_batch_query
              .where(::Repository.arel_table[:id].gt(offset_id))
              .order(:id)
              .limit(1_000)

            # NOTE: Since TimedJob does not expose the batch outside of this method,
            # we're using the batch here to get recent deployments.
            @deployments = GitHub.dogstats.distribution_time("#{T.must(self.class.name).underscore}.fetch_deployments.dist", tags: all_stats_tags) do
              ::Deployment
                .where("created_at > ?", RECENT_DEPLOYMENTS_WINDOW.ago)
                .where(latest_environment: "production", repository_id: repos.pluck(:id))
                .group(:repository_id)
                .size
            end

            repos
          end
        end

        sig do
          override.params(
            args: T.untyped,
            item: T.untyped,
            kwargs: T.untyped
          ).void
        end
        def process_item(*args, item:, **kwargs)
          return if !job_enabled?

          repo = item

          GitHub.logger.with_named_tags("gh.repo.id" => repo.id, "gh.repo.name_with_owner" => repo.name_with_display_owner) do
            log_timing(step: __method__) do
              GitHub.dogstats.distribution_time("#{T.must(self.class.name).underscore}.process_item.dist", tags: all_stats_tags) do
                begin
                  is_repo_indexed_for_semantic_search = AlertPrioritizationHelper.is_repo_indexed_for_semantic_search(repo:, user: actor)
                  next unless is_repo_indexed_for_semantic_search

                  copilot_answer_deployed_to_prod = prompt_deployed_to_prod ? ask_copilot(prompt: T.must(prompt_deployed_to_prod), repo:) : empty_copilot_chat_response
                  copilot_answer_handles_pii = prompt_handles_pii ? ask_copilot(prompt: T.must(prompt_handles_pii), repo:) : empty_copilot_chat_response
                  copilot_answer_business_critical = prompt_business_critical ? ask_copilot(prompt: T.must(prompt_business_critical), repo:) : empty_copilot_chat_response
                  copilot_answer_internet_accessible = prompt_internet_accessible ? ask_copilot(prompt: T.must(prompt_internet_accessible), repo:) : empty_copilot_chat_response

                  # If a production deployment is present, then we know the repo is deployed to production.
                  # However, if a production deployment is not present, that doesn't mean the repo is not deployed to production -
                  # it just means we don't have enough information to say for sure.
                  deployed_to_prod_known_answer = deployments[repo.id].to_i.positive? ? true : nil

                  write_csv_row(csv_row: CsvRow.new(
                    repo_id: repo.id,
                    repo_nwo: repo.name_with_display_owner,
                    repo_is_archived: repo.archived?,
                    repo_is_public: repo.public?,

                    deployed_to_prod_known_answer:,
                    deployed_to_prod_copilot_prompt: prompt_deployed_to_prod,
                    deployed_to_prod_copilot_answer: ActiveRecord::Type::Boolean.new.cast(copilot_answer_deployed_to_prod.answer),
                    deployed_to_prod_copilot_confidence: copilot_answer_deployed_to_prod.confidence,
                    deployed_to_prod_copilot_reasoning: copilot_answer_deployed_to_prod.reasoning,

                    handles_pii_known_answer: nil,
                    handles_pii_copilot_prompt: prompt_handles_pii,
                    handles_pii_copilot_answer: ActiveRecord::Type::Boolean.new.cast(copilot_answer_handles_pii.answer),
                    handles_pii_copilot_confidence: copilot_answer_handles_pii.confidence,
                    handles_pii_copilot_reasoning: copilot_answer_handles_pii.reasoning,

                    business_critical_known_answer: nil,
                    business_critical_copilot_prompt: prompt_business_critical,
                    business_critical_copilot_answer: ActiveRecord::Type::Boolean.new.cast(copilot_answer_business_critical.answer),
                    business_critical_copilot_confidence: copilot_answer_business_critical.confidence,
                    business_critical_copilot_reasoning: copilot_answer_business_critical.reasoning,

                    internet_accessible_known_answer: nil,
                    internet_accessible_copilot_prompt: prompt_internet_accessible,
                    internet_accessible_copilot_answer: ActiveRecord::Type::Boolean.new.cast(copilot_answer_internet_accessible.answer),
                    internet_accessible_copilot_confidence: copilot_answer_internet_accessible.confidence,
                    internet_accessible_copilot_reasoning: copilot_answer_internet_accessible.reasoning
                  ))
                rescue => err # rubocop:disable Lint/GenericRescue
                  Failbot.report(err)
                  log_warn(err.message)
                end
              end
            end
          end
        end

        sig { override.params(args: T.untyped, kwargs: T.untyped).void }
        def finalize_sequence(*args, **kwargs)
          upsert_job_status.success!
          return if !job_enabled? && !always_send_email?

          log_timing(step: __method__) do
            ::SecurityCenterMailer
              .alert_prioritization_copilot_prompt_experiment_csv_ready(
                actor:,
                users_to_email: [actor],
                owner:,
                file_url: generate_csv_url,
                file_expiration_time: Time.current + csv_expiry
              ).deliver_later
          end
        end

        sig { override.returns(Float) }
        def timeout_sec
          # Each repository takes approximately 30 seconds to process.
          # With default timeout, this only leaves 30 seconds between 1 minute and 90 seconds configured in
          # github/security_center/job-latency monitor, so we often start processing repo e.g. on 59th second, and end on 90+ second.
          # Setting this to 30 seconds makes sure we have full minute to process the last repo (most likely we will only process 2 repos per job).
          30.seconds.to_f
        end

        sig { override.returns(T.nilable(::User)) }
        def current_user
          actor
        end

        sig { override.returns(T.nilable(Copilot::User)) }
        def current_copilot_user
        end

        # Sends a request to Copilot.
        sig { params(prompt: String, repo: ::Repository).returns(CopilotChatResponse) }
        def ask_copilot(prompt:, repo:)
          sleep(copilot_api_sleep_sec)
          num_json_parser_error_retries = 1

          adjusted_prompt = %{
            Repo name: "#{repo.name_with_display_owner}".
            #{prompt}
            Fill in this JSON and return it as the entirety of your response: {
              "answer": Your answer,
              "confidence": 0 - 100,
              "reasoning": "Your reasoning here."
            }.
            Do not respond in markdown syntax.
          }.squish

          copilot_parsed_res = T.let({}.with_indifferent_access, ActiveSupport::HashWithIndifferentAccess)
          begin
            GitHub.logger.with_named_tags("gh.security_center.alert_prioritization.copilot_prompt": adjusted_prompt) do
              AlertPrioritizationHelper.with_retry(
                block_description: __method__.to_s,
                max_retries: copilot_api_max_retries,
                raise_on_retry_exhaustion: false,
                retry_wait_sec: copilot_api_sleep_sec
              ) do
                log_timing(step: __method__) do
                  GitHub.dogstats.distribution_time("#{T.must(self.class.name).underscore}.#{__method__}.dist", tags: all_stats_tags) do
                    copilot_raw_res = copilot_api_client.send_platform_agent_chat_message(prompt: adjusted_prompt)
                    log_info("Copilot raw response", "gh.job.raw_response" => copilot_raw_res)
                    copilot_parsed_res = JSON.parse(copilot_raw_res).with_indifferent_access
                    log_info("Copilot parsed response", "gh.job.parsed_response" => copilot_parsed_res)
                  end
                end
              end
            end
          rescue => err # rubocop:disable Lint/GenericRescue
            num_json_parser_error_retries += 1

            if num_json_parser_error_retries < copilot_api_max_retries && err.cause.class == JSON::ParserError
              retry
            end
          end

          CopilotChatResponse.new(
            answer: copilot_parsed_res["answer"].to_s,
            confidence: copilot_parsed_res["confidence"].blank? ? nil : copilot_parsed_res["confidence"].to_i,
            reasoning: copilot_parsed_res["reasoning"].to_s
          )
        end

        sig { returns(T::Hash[String, Symbol]) }
        memoize def csv_headers_to_struct_fields
          hsh = {}
          hsh["Repo ID"] = :repo_id if show_repo_id_in_csv?
          hsh = hsh.merge({
            "Repo NWO" => :repo_nwo,
            "Repo is archived?" => :repo_is_archived,
            "Repo is public?" => :repo_is_public
          })

          if prompt_deployed_to_prod
            hsh = hsh.merge({
              "Is repo deployed to production? - Known answer" => :deployed_to_prod_known_answer,
              "Is repo deployed to production? - Copilot prompt" => :deployed_to_prod_copilot_prompt,
              "Is repo deployed to production? - Copilot's answer" => :deployed_to_prod_copilot_answer,
              "Is repo deployed to production? - Copilot's confidence" => :deployed_to_prod_copilot_confidence,
              "Is repo deployed to production? - Copilot's reasoning" => :deployed_to_prod_copilot_reasoning
            })
          end

          if prompt_handles_pii
            hsh = hsh.merge({
              "Does repo handle PII? - Known answer" => :handles_pii_known_answer,
              "Does repo handle PII? - Copilot prompt" => :handles_pii_copilot_prompt,
              "Does repo handle PII? - Copilot's answer" => :handles_pii_copilot_answer,
              "Does repo handle PII? - Copilot's confidence" => :handles_pii_copilot_confidence,
              "Does repo handle PII? - Copilot's reasoning" => :handles_pii_copilot_reasoning
            })
          end

          if prompt_business_critical
            hsh = hsh.merge({
              "Is repo business critical? - Known answer" => :business_critical_known_answer,
              "Is repo business critical? - Copilot prompt" => :business_critical_copilot_prompt,
              "Is repo business critical? - Copilot's answer" => :business_critical_copilot_answer,
              "Is repo business critical? - Copilot's confidence" => :business_critical_copilot_confidence,
              "Is repo business critical? - Copilot's reasoning" => :business_critical_copilot_reasoning
            })
          end

          if prompt_internet_accessible
            hsh = hsh.merge({
              "Is repo internet accessible? - Known answer" => :internet_accessible_known_answer,
              "Is repo internet accessible? - Copilot prompt" => :internet_accessible_copilot_prompt,
              "Is repo internet accessible? - Copilot's answer" => :internet_accessible_copilot_answer,
              "Is repo internet accessible? - Copilot's confidence" => :internet_accessible_copilot_confidence,
              "Is repo internet accessible? - Copilot's reasoning" => :internet_accessible_copilot_reasoning
            })
          end

          hsh
        end

        sig { void }
        def create_csv_file
          csv_headers = CSV.generate(write_headers: true, headers: csv_headers_to_struct_fields.keys) {}

          AlertPrioritizationHelper.with_retry(block_description: __method__.to_s) do
            log_timing(step: __method__) do
              blob_storage_service.create(blob_storage_key, true)
              blob_storage_service.store(blob_storage_key, csv_headers, CSV_FEATURE, true)
            end
          end
        end

        sig { params(csv_row: CsvRow).void }
        def write_csv_row(csv_row:)
          row_content = CSV.generate do |csv|
            csv << csv_headers_to_struct_fields.values.map { |struct_field| csv_row.send(struct_field) } # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          end

          AlertPrioritizationHelper.with_retry(block_description: __method__.to_s) do
            log_timing(step: __method__) do
              blob_storage_service.store(blob_storage_key, row_content, CSV_FEATURE, true)
            end
          end
        end

        sig { returns(String) }
        def generate_csv_url
          res, err = AlertPrioritizationHelper.with_retry(block_description: __method__.to_s) do
            log_timing(step: __method__) do
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

        sig { returns(::SecurityCenter::AlertPrioritization::CopilotApiClient) }
        memoize def copilot_api_client
          ::SecurityCenter::AlertPrioritization::CopilotApiClient.new(
            hmac_secret:,
            integration_id: COPILOT_INTEGRATION_ID,
            token: copilot_mint_token(T.must(actor.most_recent_session)),
            user: actor
          )
        end

        sig { returns(::SecurityCenter::Export::BlobStorageService) }
        memoize def blob_storage_service
          ::SecurityCenter::Export::BlobStorageService.get(actor)
        end

        sig { returns(CopilotChatResponse) }
        memoize def empty_copilot_chat_response
          CopilotChatResponse.new(answer: nil, confidence: nil, reasoning: nil)
        end

        sig { returns(String) }
        def hmac_secret
          GitHub.environment.fetch("HMAC_SECRET_CAPI_INTEGRATION_ADVANCED_SECURITY_DEV", "hmac_secret_capi_integration_advanced_security_dev")
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

        sig { returns(Integer) }
        def copilot_api_max_retries
          job_arguments.fetch(:copilot_api_max_retries, DEFAULT_COPILOT_API_MAX_RETRIES)
        end

        sig { returns(Integer) }
        def copilot_api_sleep_sec
          job_arguments.fetch(:copilot_api_sleep_sec, DEFAULT_COPILOT_API_SLEEP_SEC)
        end

        sig { returns(T::Boolean) }
        def always_send_email?
          job_arguments.fetch(:always_send_email, DEFAULT_ALWAYS_SEND_EMAIL)
        end

        sig { returns(T::Boolean) }
        def is_job_disabled_on_first_job?
          !job_enabled? && T.cast(job_arguments.fetch(:num_in_sequence, 1) == 1, T::Boolean)
        end

        sig { returns(T::Boolean) }
        memoize def show_repo_id_in_csv?
          ::SecurityCenter::FeatureFlagHelper.show_repo_id_in_alert_prioritization_experiment_csv?(owner)
        end

        sig { returns(T::Boolean) }
        def job_enabled?
          !::SecurityCenter::FeatureFlagHelper.disable_alert_prioritization_owner_csv_job?(owner)
        end

        sig { returns(T::Array[Integer]) }
        memoize def accessible_repo_ids
          actor.associated_repository_ids(min_action: :read, organization: owner) # rubocop:disable GitHub/DontCallAssociatedRepositoryIdsUnbounded
        end

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
            ApplicationRecord::Domain::KeyValues.throttle_writes_with_retry { update_job_status.call }
          else
            update_job_status.call
          end

          T.must(job_status)
        end

        sig { returns(ActiveRecord::Relation) }
        def base_batch_query
          owner.repositories.where(id: accessible_repo_ids)
        end

        sig { returns(Integer) }
        memoize def num_total_applicable_items
          base_batch_query.size
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
            "gh.job.params.copilot_api_sleep_sec": copilot_api_sleep_sec,
            "gh.job.num_applicable_items": num_total_applicable_items
          })
        end

        sig { override.returns(T::Hash[T.any(String, Symbol), T.untyped]) }
        def failbot_context
          super.merge({ app: "github-security-center" }).merge(logging_context)
        end
      end
    end
  end
end
