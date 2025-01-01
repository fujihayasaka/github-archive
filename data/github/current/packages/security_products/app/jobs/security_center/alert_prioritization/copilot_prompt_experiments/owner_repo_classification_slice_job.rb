# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module AlertPrioritization
    module CopilotPromptExperiments
      # Generates and KV and CSV rows of Copilot's responses to prompts about each repo in an owner.
      # Runs for a slice of repositories.
      class OwnerRepoClassificationSliceJob < TimedJob
        include ::GitHub::SecurityCenter::LoggingHelper
        include ::CopilotChatHelper

        PARALLEL_SLICES = 4
        COPILOT_INTEGRATION_ID = "ghas-experimental-dev"
        DEV_HMAC = "copilot_platform_api_hmac_very_secret"
        RECENT_DEPLOYMENTS_WINDOW = T.let(6.months, ActiveSupport::Duration)
        KV_PREFIX = "security_center.alert_prioritization.owner_repo_classification."

        class CodeSearchError < StandardError; end

        class CopilotChatResponse < T::Struct
          const :answer, T.nilable(String)
          const :confidence, T.nilable(Integer)
          const :reasoning, T.nilable(String)
        end

        class RepositoryEvaluationResults < T::Struct
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

          const :experimental_known_answer, T.nilable(T::Boolean)
          const :experimental_copilot_prompt, T.nilable(String)
          const :experimental_copilot_answer, T.nilable(T::Boolean)
          const :experimental_copilot_confidence, T.nilable(Integer)
          const :experimental_copilot_reasoning, T.nilable(String)
        end

        class RepositoryEvaluationPromptResult < T::Struct
          const :prompt_id, String
          const :copilot_prompt, T.nilable(String)
          const :copilot_answer, T.nilable(T::Boolean)
          const :known_answer, T.nilable(T::Boolean)
          const :copilot_confidence, T.nilable(Integer)
          const :copilot_reasoning, T.nilable(String)
        end

        # Using separate queue for control vs. slice jobs to allow for different throttling settings.
        queue_as :alert_prioritization_copilot_prompt_experiments_slice

        retry_on_dirty_exit
        retry_on_recoverable_exceptions

        # The backoff here is informed by rules defined in https://github.com/github/blackbird-mw/blob/main/internal/quota/quota.go
        # specifically the long term half-life of 4 hours
        # Retrying every 30 minutes should allow us to get some additional quota and process a batch of repos
        T.unsafe(self).retry_on CodeSearchError, wait: 30.minutes, attempts: 20

        locked_by timeout: ApplicationJob::DEFAULT_TIMEOUT, key: ->(job) do
          DEFAULT_LOCK_STRINGIFY_PROC.call([job.owner.id, job.slice_id])
        end

        before_enqueue do |job|
          job.upsert_job_status
        end

        before_perform do |job|
          if !job.actor.most_recent_session.try(:active?)
            raise AlertPrioritizationHelper::UserMissingActiveSessionError
          end
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
        sig { params(owner: ::User, slice_id: Integer).returns(String) }
        def self.job_id(owner, slice_id)
          "security_center.alert_prioritization.copilot_prompt_experiments.owner_repo_classification_slice_job.#{owner.id}.#{slice_id}"
        end

        # The job status.
        sig { params(owner: ::User, slice_id: Integer).returns(T.nilable(JobStatus)) }
        def self.status(owner, slice_id)
          # Using write connection to prevent any kind of replication lag affecting getting this status between runs of the job.
          ActiveRecord::Base.connected_to(role: :writing) do
            JobStatus.find(job_id(owner, slice_id))
          end
        end

        sig { returns(T::Hash[Integer, Integer]) }
        attr_accessor :deployments

        sig { override.params(args: T.untyped, kwargs: T.untyped).void }
        def initialize(*args, **kwargs)
          @deployments = T.let({}, T::Hash[Integer, Integer])

          super(*T.unsafe(args), **kwargs)
        end

        sig do
          override.params(
            actor: ::User,
            owner: T.any(::Organization, ::User),
            slice_id: Integer,
            blob_storage_key: T.nilable(String), # A unique value to use as the ID of the Azure file. If nil, CSV will not be written.
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
          slice_id:,
          blob_storage_key:,
          copilot_api_max_retries: OwnerRepoClassificationControlJob::DEFAULT_COPILOT_API_MAX_RETRIES,
          prompt_deployed_to_prod: OwnerRepoClassificationControlJob::DEFAULT_PROMPT_DEPLOYED_TO_PROD,
          prompt_handles_pii: OwnerRepoClassificationControlJob::DEFAULT_PROMPT_HANDLES_PII,
          prompt_business_critical: OwnerRepoClassificationControlJob::DEFAULT_PROMPT_BUSINESS_CRITICAL,
          prompt_internet_accessible: OwnerRepoClassificationControlJob::DEFAULT_PROMPT_INTERNET_ACCESSIBLE,
          prompt_experimental: nil,
          **kwargs
        )
          super(
            actor:,
            owner:,
            slice_id:,
            blob_storage_key:,
            copilot_api_max_retries:,
            prompt_deployed_to_prod:,
            prompt_handles_pii:,
            prompt_business_critical:,
            prompt_internet_accessible:,
            prompt_experimental:,
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

          log_timing(step: "fetch repository batch") do
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
            log_timing(step: "process item") do
              GitHub.dogstats.distribution_time("#{T.must(self.class.name).underscore}.process_item.dist", tags: all_stats_tags) do
                begin
                  is_repo_indexed_for_semantic_search = AlertPrioritizationHelper.is_repo_indexed_for_semantic_search(repo:, user: actor)
                  next unless is_repo_indexed_for_semantic_search

                  # Only runs experimental prompt it is specified
                  if prompt_experimental.present?
                    copilot_answer_experimental_promise = ask_copilot(prompt: T.must(prompt_experimental), repo:)
                    copilot_answer_experimental_promise.then do |copilot_answer_experimental|
                      csv_result = RepositoryEvaluationResults.new(
                        repo_id: repo.id,
                        repo_nwo: repo.name_with_display_owner,
                        repo_is_archived: repo.archived?,
                        repo_is_public: repo.public?,

                        experimental_known_answer: nil,
                        experimental_copilot_prompt: prompt_experimental,
                        experimental_copilot_answer: ActiveRecord::Type::Boolean.new.cast(copilot_answer_experimental.answer&.downcase),
                        experimental_copilot_confidence: copilot_answer_experimental.confidence,
                        experimental_copilot_reasoning: copilot_answer_experimental.reasoning
                      )
                      write_csv_row(result: csv_result)

                      results = T.let([
                        RepositoryEvaluationPromptResult.new(
                          prompt_id: "experimental",
                          known_answer: nil,
                          copilot_prompt: prompt_experimental,
                          copilot_answer: ActiveModel::Type::Boolean.new.cast(copilot_answer_experimental.answer&.downcase),
                          copilot_confidence: copilot_answer_experimental.confidence,
                          copilot_reasoning: copilot_answer_experimental.reasoning
                        ),
                      ], T::Array[RepositoryEvaluationPromptResult])
                      write_kv(repo.id, results:, is_experimental: true)

                    rescue => err # rubocop:disable Lint/GenericRescue
                      # Code search errors get bubbled to retry the job
                      raise if err.is_a?(CodeSearchError)
                      # Here we are handling cases where we got responses from all promises
                      # but are failing to grab/parse the responses or write to the CSV
                      Failbot.report(err)
                      log_warn(err.message)
                    end.sync
                  else
                    existing_key = ::SecurityCenter::KV.store.exists(self.class.repo_results_kv_key(repo.id, is_experimental: false)).value { false }
                    next if existing_key.present?

                    copilot_answer_deployed_to_prod_promise = prompt_deployed_to_prod ? ask_copilot(prompt: T.must(prompt_deployed_to_prod), repo:) : empty_copilot_chat_response_promise
                    copilot_answer_handles_pii_promise = prompt_handles_pii ? ask_copilot(prompt: T.must(prompt_handles_pii), repo:) : empty_copilot_chat_response_promise
                    copilot_answer_business_critical_promise = prompt_business_critical ? ask_copilot(prompt: T.must(prompt_business_critical), repo:) : empty_copilot_chat_response_promise
                    copilot_answer_internet_accessible_promise = prompt_internet_accessible ? ask_copilot(prompt: T.must(prompt_internet_accessible), repo:) : empty_copilot_chat_response_promise

                    # If a production deployment is present, then we know the repo is deployed to production.
                    # However, if a production deployment is not present, that doesn't mean the repo is not deployed to production -
                    # it just means we don't have enough information to say for sure.
                    deployed_to_prod_known_answer = deployments[repo.id].to_i.positive? ? true : nil

                    Promise.all([copilot_answer_deployed_to_prod_promise, copilot_answer_handles_pii_promise, copilot_answer_business_critical_promise, copilot_answer_internet_accessible_promise]).then do
                      |copilot_answer_deployed_to_prod, copilot_answer_handles_pii, copilot_answer_business_critical, copilot_answer_internet_accessible|

                      csv_result = RepositoryEvaluationResults.new(
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
                      )
                      write_csv_row(result: csv_result)

                      # TODO: we should move property definition and its CRUD into a model class instead
                      results = T.let([
                        RepositoryEvaluationPromptResult.new(
                          prompt_id: "deployed_to_prod",
                          known_answer: deployed_to_prod_known_answer,
                          copilot_prompt: prompt_deployed_to_prod,
                          copilot_answer: ActiveModel::Type::Boolean.new.cast(copilot_answer_deployed_to_prod.answer),
                          copilot_confidence: copilot_answer_deployed_to_prod.confidence,
                          copilot_reasoning: copilot_answer_deployed_to_prod.reasoning
                        ),
                        RepositoryEvaluationPromptResult.new(
                          prompt_id: "handles_pii",
                          known_answer: nil,
                          copilot_prompt: prompt_handles_pii,
                          copilot_answer: ActiveModel::Type::Boolean.new.cast(copilot_answer_handles_pii.answer),
                          copilot_confidence: copilot_answer_handles_pii.confidence,
                          copilot_reasoning: copilot_answer_handles_pii.reasoning
                        ),
                        RepositoryEvaluationPromptResult.new(
                          prompt_id: "business_critical",
                          known_answer: nil,
                          copilot_prompt: prompt_business_critical,
                          copilot_answer: ActiveModel::Type::Boolean.new.cast(copilot_answer_business_critical.answer),
                          copilot_confidence: copilot_answer_business_critical.confidence,
                          copilot_reasoning: copilot_answer_business_critical.reasoning
                        ),
                        RepositoryEvaluationPromptResult.new(
                          prompt_id: "internet_accessible",
                          known_answer: nil,
                          copilot_prompt: prompt_internet_accessible,
                          copilot_answer: ActiveModel::Type::Boolean.new.cast(copilot_answer_internet_accessible.answer),
                          copilot_confidence: copilot_answer_internet_accessible.confidence,
                          copilot_reasoning: copilot_answer_internet_accessible.reasoning
                        ),
                      ], T::Array[RepositoryEvaluationPromptResult])
                      write_kv(repo.id, results:)

                    rescue => err # rubocop:disable Lint/GenericRescue
                      # Code search errors get bubbled to retry the job
                      raise if err.is_a?(CodeSearchError)
                      # Here we are handling cases where we got responses from all promises
                      # but are failing to grab/parse the responses or write to the CSV
                      Failbot.report(err)
                      log_warn(err.message)
                    end
                    # Wait for all 4 promises to complete before moving on to the next repo.
                    .sync
                  end
                rescue => err # rubocop:disable Lint/GenericRescue
                  # Code search errors get bubbled to retry the job
                  raise if err.is_a?(CodeSearchError)

                  # Here we are handling cases one of promises got rejected
                  # or is_repo_indexed_for_semantic_search failed

                  # Note that we should never get failed promise, since we are handling these in the ask_copilot method
                  # by returning empty answers with the idea that even if one of them failed, another one might have succeeded
                  # so we still want to record partial data
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

        sig { override.returns(T.nilable(T.any(Copilot::User, Copilot::Public::User))) }
        def current_copilot_user_v2
        end

        # Sends a request to Copilot.
        # Note that retries are attempted for both json and network errors, and have common counter
        sig { params(prompt: String, repo: ::Repository, retries: Integer).returns(Promise[CopilotChatResponse]) }
        def ask_copilot(prompt:, repo:, retries: copilot_api_max_retries)
          adjusted_prompt = %{
            Repo name: "#{repo.name_with_display_owner}".
            #{prompt}


            Fill in this JSON and return it as the entirety of your response:
            {
              "answer": Your answer,
              "confidence": 0 - 100,
              "reasoning": "Your reasoning here.",
              "code_search_success": true/false
            }

            code_search_success should be set to false only if code search failed. if no results are found, code_search_success should be true.

            Do not respond in markdown syntax.
          }.squish

          copilot_parsed_res = T.let({}.with_indifferent_access, ActiveSupport::HashWithIndifferentAccess)
          begin
            GitHub.logger.with_named_tags("gh.security_center.alert_prioritization.copilot_prompt": adjusted_prompt) do
              log_timing(step: "handle copilot request and response") do
                GitHub.dogstats.distribution_time("#{T.must(self.class.name).underscore}.#{__method__}.dist", tags: all_stats_tags) do
                  return copilot_api_client.async_send_platform_agent_chat_message(prompt: adjusted_prompt).then do |copilot_raw_res|
                    begin
                      log_info("Copilot raw response", "gh.job.raw_response" => copilot_raw_res)
                      copilot_parsed_res = JSON.parse(copilot_raw_res).with_indifferent_access
                      log_info("Copilot parsed response", "gh.job.parsed_response" => copilot_parsed_res)

                      raise CodeSearchError.new(copilot_raw_res) if !copilot_parsed_res["code_search_success"]

                      CopilotChatResponse.new(
                        answer: copilot_parsed_res["answer"].to_s,
                        confidence: copilot_parsed_res["confidence"].blank? ? nil : copilot_parsed_res["confidence"].to_i,
                        reasoning: copilot_parsed_res["reasoning"].to_s
                      )
                    # This rescues response parsing we do above inside this .then block, not request errors.
                    # Retry errors are handled in client, while all other errors cause promise to fail and get handled in the process_item.
                    rescue => err # rubocop:disable Lint/GenericRescue
                      # Don't rescue if code search errored, as we need to handle this in caller
                      raise if err.is_a?(CodeSearchError)

                      if retries > 0 && err.cause.class == JSON::ParserError
                        # If copilot doesn't return json, retry a few times to see if it responds with proper expected json
                        # Note that there's no delay here, we try right away and the underlying
                        # client handles throttling if we are hitting rate limits
                        ask_copilot(prompt:, repo:, retries: retries - 1)
                      else
                        # If we failed to get json response from copilot after a few retries,
                        # return empty response so that job continues
                        # This allows us to store responses from other prompts in the CSV, if they succeeded
                        log_info("Copilot terminal failure for repository", "error.exception" => err)
                        CopilotChatResponse.new(
                          answer: "",
                          confidence: 0,
                          reasoning: ""
                        )
                      end
                    end
                  end
                  # This is the _promise_ rescue method, handling rejected promises instead of synchronous errors
                  # For example when copilot api fails, or we run out of retry attempts
                  .rescue do |err|
                    # Don't rescue if code search errored, as we need to handle this in caller
                    raise if err.is_a?(CodeSearchError)

                    # If copilot client threw some other error (e.g. any kind of network error)
                    # let's retry a few times to see if it succeeds.
                    # Retry errors should be correctly handled by the client, so we should not see them here
                    # until client runs out of allowed retries
                    # Note that there's no delay here, we try right away and the underlying
                    # client handles throttling if we are hitting rate limits
                    if !err.is_a?(CopilotAPI::RateLimitError) && retries > 0
                      ask_copilot(prompt:, repo:, retries: retries - 1)
                    else
                      # If we failed to get any response from copilot after a few retries,
                      # return empty response so that job continues
                      # This allows us to store responses from other prompts in the CSV, if they succeeded
                      log_info("Copilot terminal failure for repository", "error.exception" => err)
                      CopilotChatResponse.new(
                        answer: "",
                        confidence: 0,
                        reasoning: "",
                      )
                    end
                  end
                end
              end
            end
          end
        end

        sig do
          params(
            prompt_deployed_to_prod: T.nilable(String),
            prompt_handles_pii: T.nilable(String),
            prompt_business_critical: T.nilable(String),
            prompt_internet_accessible: T.nilable(String),
            prompt_experimental: T.nilable(String)
          ).returns(T::Hash[String, Symbol])
        end
        def self.csv_headers_to_struct_fields(
          prompt_deployed_to_prod:,
          prompt_handles_pii:,
          prompt_business_critical:,
          prompt_internet_accessible:,
          prompt_experimental:
        )
          hsh = {}
          hsh = hsh.merge({
            "Repo ID" => :repo_id,
            "Repo NWO" => :repo_nwo,
            "Repo is archived?" => :repo_is_archived,
            "Repo is public?" => :repo_is_public
          })

          # Only outputs experimental prompt when it is specified
          if prompt_experimental
            hsh = hsh.merge({
              "Experimental - Known answer" => :experimental_known_answer,
              "Experimental - Copilot prompt" => :experimental_copilot_prompt,
              "Experimental - Copilot's answer" => :experimental_copilot_answer,
              "Experimental - Copilot's confidence" => :experimental_copilot_confidence,
              "Experimental - Copilot's reasoning" => :experimental_copilot_reasoning
            })
            return hsh
          end

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

        sig { params(result: RepositoryEvaluationResults).void }
        def write_csv_row(result:)
          return if blob_storage_key.blank?

          row_content = CSV.generate do |csv|
            csv << self.class.csv_headers_to_struct_fields(
              prompt_deployed_to_prod:,
              prompt_handles_pii:,
              prompt_business_critical:,
              prompt_internet_accessible:,
              prompt_experimental:
            ).values.map { |struct_field| result.send(struct_field) } # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          end

          AlertPrioritizationHelper.with_retry(block_description: __method__.to_s) do
            log_timing(step: "append row to csv blob") do
              blob_storage_service.store(blob_storage_key, row_content, OwnerRepoClassificationControlJob::CSV_FEATURE)
            end
          end
        end

        sig do
          params(
            repo_id: Integer,
            results: T::Array[RepositoryEvaluationPromptResult],
            is_experimental: T::Boolean
          ).void
        end
        def write_kv(repo_id, results:, is_experimental: false)
          ::SecurityCenter::KV::DataStore.throttle_writes_with_retry do
            ::SecurityCenter::KV.store.set(
              self.class.repo_results_kv_key(repo_id, is_experimental:),
              results.to_json,
            )
          end
        end

        sig { params(repo_id: Integer, is_experimental: T::Boolean).returns(String) }
        def self.repo_results_kv_key(repo_id, is_experimental: false)
          is_experimental ? "#{KV_PREFIX}experimental.#{repo_id}" : "#{KV_PREFIX}#{repo_id}"
        end

        sig { returns(::SecurityCenter::AlertPrioritization::CopilotApiClient) }
        memoize def copilot_api_client
          ::SecurityCenter::AlertPrioritization::CopilotApiClient.new(
            hmac_secret:,
            integration_id: COPILOT_INTEGRATION_ID,
            token: copilot_mint_token(T.must(actor.most_recent_session), entry_point: :security_center_alert_prioritization_copilot_prompt_experiments_owner_repo_classification_slice_job),
            user: actor
          )
        end

        sig { returns(::SecurityCenter::Export::BlobStorageService) }
        memoize def blob_storage_service
          ::SecurityCenter::Export::BlobStorageService.get
        end

        sig { returns(Promise[CopilotChatResponse]) }
        memoize def empty_copilot_chat_response_promise
          Promise.resolve(CopilotChatResponse.new(answer: nil, confidence: nil, reasoning: nil))
        end

        sig { returns(String) }
        def hmac_secret
          # If env secret is not set, assume codespace and use the dev secret from capi.
          GitHub.environment.fetch("HMAC_SECRET_CAPI_INTEGRATION_ADVANCED_SECURITY_DEV", DEV_HMAC)
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

        sig { returns(Integer) }
        def slice_id
          job_arguments.fetch(:slice_id, 0)
        end

        sig { returns(String) }
        def blob_storage_key
          job_arguments.fetch(:blob_storage_key)
        end

        sig { returns(T.nilable(String)) }
        def prompt_deployed_to_prod
          job_arguments.fetch(:prompt_deployed_to_prod, OwnerRepoClassificationControlJob::DEFAULT_PROMPT_DEPLOYED_TO_PROD)
        end

        sig { returns(T.nilable(String)) }
        def prompt_handles_pii
          job_arguments.fetch(:prompt_handles_pii, OwnerRepoClassificationControlJob::DEFAULT_PROMPT_HANDLES_PII)
        end

        sig { returns(T.nilable(String)) }
        def prompt_business_critical
          job_arguments.fetch(:prompt_business_critical, OwnerRepoClassificationControlJob::DEFAULT_PROMPT_BUSINESS_CRITICAL)
        end

        sig { returns(T.nilable(String)) }
        def prompt_internet_accessible
          job_arguments.fetch(:prompt_internet_accessible, OwnerRepoClassificationControlJob::DEFAULT_PROMPT_INTERNET_ACCESSIBLE)
        end

        sig { returns(T.nilable(String)) }
        def prompt_experimental
          job_arguments.fetch(:prompt_experimental, nil)
        end

        sig { returns(Integer) }
        def copilot_api_max_retries
          job_arguments.fetch(:copilot_api_max_retries, OwnerRepoClassificationControlJob::DEFAULT_COPILOT_API_MAX_RETRIES)
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

        # Allows custom control of job status so it's maintained between batches and can be read by control job
        sig { params(throttle: T::Boolean).returns(JobStatus) }
        def upsert_job_status(throttle: false)
          ttl = 10.minutes
          job_id = self.class.job_id(owner, slice_id)
          existing_job_status = self.class.status(owner, slice_id)
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
            # When kicking off job initially, don't throttle writes to KV - the initial kickoff is done from UI for example
            update_job_status.call
          end

          T.must(job_status)
        end

        sig { returns(ActiveRecord::Relation) }
        def base_batch_query
          owner.repositories
          .where(id: accessible_repo_ids)
          .where("mod(id, ?) = ?", PARALLEL_SLICES, slice_id)
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
