# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class ActionsUsageRelay < SingleMessageProcessor
      include GitHub::Tracing

      default_to_write_connection!

      include TransientErrorResiliency

      self.slack_pause_notifications_channel = "#actions-alerts"

      DEFAULT_GROUP_ID = "actions_usage_relay"
      DEFAULT_SUBSCRIBE_TO = /github\.actions\.v0\.JobExecution\Z/

      options[:min_bytes] = 1
      options[:max_wait_time] = 0.2.seconds
      options[:max_bytes_per_partition] = 100.kilobytes
      options[:session_timeout] = 60.seconds
      options[:socket_timeout] = 65.seconds
      options[:start_from_beginning] = false

      MACOS_LATEST_XL         = "macos-latest-xl".freeze
      MACOS_12_XL             = "macos-12-xl".freeze
      MACOS_12_XL_BETA        = "macos-12-xl-beta".freeze
      MACOS_13_XL             = "macos-13-xl".freeze
      MACOS_LATEST_XL_ARM64   = "macos-latest-xl-arm64".freeze
      MACOS_13_XL_ARM64       = "macos-13-xl-arm64".freeze
      # newer large/xlarge labels:
      MACOS_12_LARGE          = "macos-12-large".freeze
      MACOS_13_LARGE          = "macos-13-large".freeze
      MACOS_LATEST_LARGE      = "macos-latest-large".freeze
      MACOS_13_XLARGE         = "macos-13-xlarge".freeze
      MACOS_14_XLARGE         = "macos-14-xlarge".freeze
      MACOS_14_LARGE          = "macos-14-large".freeze
      MACOS_15_XLARGE         = "macos-15-xlarge".freeze
      MACOS_15_LARGE          = "macos-15-large".freeze
      MACOS_LATEST_XLARGE     = "macos-latest-xlarge".freeze

      trace_method :process_message, span_attribute_extractor: -> (instance, *args, **_kwargs) { instance.trace_message_tags(args[0]) }
      trace_method :process_message_internal, span_attribute_extractor: -> (instance, *args, **_kwargs) { instance.trace_message_tags(args[0]) }

      resolve_tenant_context do |message|
        Repositories::Public.resolve_tenant(id: message.value[:workflow_repository_id])
      end

      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

        self.dead_letter_topic = "github.actions.v0.JobExecution.DeadLetter"
      end

      def process_message(message)

        log_hash = {
          class: self.class.name,
          actor_id: message.value[:invoking_user_id],
          topic: message.topic,
          check_run_id: message.value[:check_run_id],
          job_id: message.value[:job_id],
          partition: message.partition,
          offset: message.offset,
        }

        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::Logger.log_context(log_hash) do
            GitHub::Logger.log({
              msg: "Starting to process message",
            })
            process_message_internal(message)
            GitHub::Logger.log({
              msg: "Finished processing message",
            })
          end
        end
      end

      # This needs to be public so the instrumentation can access it
      def trace_message_tags(message)
        tags = {
          "hydro_msg_topic" => message.topic || "unknown",
          "hydro_msg_partition" => message.partition || 0,
          "hydro_msg_offset" => message.offset || 0,
        }

        tags["gh.check_run.id"] = message.value[:check_run_id] if message.value[:check_run_id]
        tags["gh.repo.id"] = message.value[:repository_id] if message.value[:repository_id]
        tags["gh.actions.workflow_job_run.job_id"] = message.value[:job_id] if message.value[:job_id]

        tags
      end

      private

      # Create a UsageLineItem for the message
      #
      # message - The Hydro::Consumer::ConsumerMessage to process
      #
      # Returns nothing
      def process_message_internal(message)
        # Skip message if the runner type is self hosted
        if self_hosted_runner?(message)
          return skip(message, "self_hosted")
        end

        owner = User.find_by(id: message.value[:workflow_repository_owner_id])

        if owner.nil?
          return skip(message, "missing_owner")
        end

        if public_repository?(message)
          unless custom_runner?(message) || macos_large_runner?(message) || macos_xlarge_runner?(message) || FeatureFlag.vexi.enabled?(:actions_billing_public_hosted, owner, default: false)
            return skip(message, "public_repository")
          end
        end

        classroom_repo = ClassroomRepository.find_by(repository_id: message.value[:workflow_repository_id])
        if classroom_repo&.has_teacher_toolbox_coupon && !custom_runner?(message)
          return skip(message, "classroom")
        end

        if FeatureFlag.vexi.enabled?(:actions_skip_billing_quotas, owner, default: false)
          return skip(message, "actions_skip_billing_quotas")
        end

        # Being explicit here to be sure the value is present and is `false`
        if message.value[:billing_checked] == false
          # TODO: this makes the run free. In the future charge if there is budget available
          return skip(message, "billing_checked_false")
        end

        # Launch emits zero values for job_id and check_run_id for CANCELED workflow run of a deleted repo
        # when a corresponding workflow run doesn't exist on dotcom.
        # `repo_deleted_jobid_zero` is unlikely to occur compared to `repo_deleted`, but handled for completeness.
        if zero_job_id_check_run_id?(message)
          return skip(message, "repo_deleted_jobid_zero")
        end

        repo = ActiveRecord::Base.connected_to(role: :reading) do
          if FeatureFlag.vexi.enabled?(:repos_by_id_lib, default: false)
            Repositories.domain.by_id(message.value[:workflow_repository_id])
          else
            Repository.find_by(id: message.value[:workflow_repository_id])
          end
        end

        # Repos are soft-deleted, and hard-deleted after 30 days. Therefore, check both nil and deleted?.
        if repo.nil? || repo.deleted?
          return skip(message, "repo_deleted")
        end

        # TODO when the new billing system is ready, we can remove this and work with the billing to team to
        # file for an exemption for the dynamic workflow in a more cleaner way.
        return skip(message, "pages_dynamic_workflow") if skip_dynamic_workflow?(message, "pages")
        return skip(message, "dependabot_dynamic_workflow") if skip_dynamic_workflow?(message, "dependabot")

        compute_usage = ::Billing::Actions::ComputeUsage.new(
          job_id: message.value[:job_id],
          actor_id: message.value[:invoking_user_id],
          owner_id: message.value[:workflow_repository_owner_id],
          owner: owner,
          check_run_id: message.value[:check_run_id],
          repository_id: message.value[:workflow_repository_id],
          repository: repo,
          duration_in_milliseconds: message.value[:job_execution_billable_ms],
          job_runtime: message.value[:job_runtime],
          start_time: Time.at(message.value[:start_time][:seconds]),
          end_time: Time.at(message.value[:end_time][:seconds]),
          runner_type: message.value[:runner_type],
          runner_properties: message.value[:runner_properties],
          product_sku: message.value[:product_sku],
        )

        # If negative duration then skip the line item. Could indicate a bug in the job
        return skip(message, "zero_duration") unless compute_usage.duration_in_minutes.positive?

        usage = compute_usage.to_meuse

        # If we can't map to a product the product_sku_name will be nil, we should skip
        if usage[:product_sku_name].nil?
          return skip(message, "unknown_product")
        end

        # Skip billing if the SKU is for an experimental product and the feature flag is enabled for the owner
        if FeatureFlag.vexi.enabled?(:actions_experimental_skip_billing, owner, default: false) && usage[:product_sku_name] == :experimental
          return skip(message, "experimental")
        end

        customer = owner.billable_owner.customer

        sku = usage[:product_sku_name].to_s
        GitHub.dogstats.increment("meuse.cutoff.actions.dropped_usage.counter", tags: { sku: sku, customer_exists: customer.present? })
        GitHub.dogstats.count("meuse.cutoff.actions.dropped_usage.quantity", usage[:quantity], tags: { sku: sku, customer_exists: customer.present? })
        owner.find_or_create_customer if customer.nil? && owner.feature_flag_enabled?(:use_find_or_create_customer, default: true)

        # We now discard usage messages in this processor
        skip(message, "billed_via_billing_platform")
      end

      def macos_large_runner?(message)

        # Check if job os is macos
        return false unless message.value[:job_runtime] == :MACOS

        # Parse runner_properties to json and check if empty
        begin
          runner_properties_json = JSON.parse(message.value[:runner_properties]) if message.value[:runner_properties].present?
        rescue ::JSON::ParserError
          return false
        end

        return false if runner_properties_json.blank?

        return false unless runner_properties_json["RequestedLabel"].present?

        requested_label = runner_properties_json["RequestedLabel"].downcase

        # Check if RequestedLabel exists
        requested_label == MACOS_LATEST_XL ||
          requested_label == MACOS_12_XL ||
          requested_label == MACOS_12_XL_BETA ||
          requested_label == MACOS_13_XL ||
          requested_label == MACOS_12_LARGE ||
          requested_label == MACOS_13_LARGE ||
          requested_label == MACOS_14_LARGE ||
          requested_label == MACOS_15_LARGE ||
          requested_label == MACOS_LATEST_LARGE
      end

      def macos_xlarge_runner?(message)

        # Check if job os is macos
        return false unless message.value[:job_runtime] == :MACOS

        # Parse runner_properties to json and check if empty
        begin
          runner_properties_json = JSON.parse(message.value[:runner_properties]) if message.value[:runner_properties].present?
        rescue ::JSON::ParserError
          return false
        end

        return false if runner_properties_json.blank?

        return false unless runner_properties_json["RequestedLabel"].present?

        requested_label = runner_properties_json["RequestedLabel"].downcase

        # Check if RequestedLabel exists
        requested_label == MACOS_LATEST_XL_ARM64 ||
          requested_label == MACOS_13_XL_ARM64 ||
          requested_label == MACOS_13_XLARGE ||
          requested_label == MACOS_14_XLARGE ||
          requested_label == MACOS_15_XLARGE ||
          requested_label == MACOS_LATEST_XLARGE
      end

      def public_repository?(message)
        message.value[:workflow_repository_visibility].to_s.upcase == "PUBLIC"
      end

      # Utilzing the new runner_type field vs the old self_hosted field
      def self_hosted_runner?(message)
        message.value[:runner_type] == :RUNNER_TYPE_SELF_HOSTED
      end

      # TODO remove this once custom runners go GA
      def custom_runner?(message)
        message.value[:runner_type] == :RUNNER_TYPE_CUSTOM
      end

      def zero_job_id_check_run_id?(message)
        message.value[:job_id] && message.value[:job_id].to_i == 0 && message.value[:check_run_id] == 0
      end

      def skip_dynamic_workflow?(message, app)
        workflow_file_path = message.value[:workflow_file_path]
        is_dynamic, app_name, slug = ::Actions::Workflow.extract_dynamic_workflowfile_path(workflow_file_path)

        return app_name == app if is_dynamic
        false
      end

      # skip encapsulates the various logging and stats logic we want to execute each time a message is skipped.
      #
      # message - Object<HydroConsumerMesssage>
      # reason - String
      #
      # Returns nothing
      def skip(message, reason)
        message.skip(reason)
        GitHub::Logger.log({
          reason: reason || "unknown",
          msg: "SKIPPED: skipped processing due to #{reason}",
        })
      end

      # error encapsulates the various logging and stats logic we want to execute each time a message has an error.
      #
      # message - Object<HydroConsumerMesssage>
      # err - Error
      # skip_reason - String
      #
      # Returns nothing
      def error(message, err)
        message.error(err)

        report_error(err)

        GitHub::Logger.log({
          msg: "ERROR: threw an error: #{err.message}",
          error: err,
        })
      end

      def error_context_for_message(message)
        super(message).merge({
          billing: {
            owner_id: message.value[:workflow_repository_owner_id],
            repository_id: message.value[:workflow_repository_id],
            job_id: message.value[:job_id],
          },
        })
      end
    end
  end
end
