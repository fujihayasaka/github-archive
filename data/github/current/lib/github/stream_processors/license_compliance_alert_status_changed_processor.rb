# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class LicenseComplianceAlertStatusChangedProcessor < SingleMessageProcessor
      include TransientErrorResiliency

      DEFAULT_GROUP_ID = "github-#{Rails.env}-license_compliance_alert_status_changed_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.dependencygraph\.v1\.LicenseComplianceAlertStatusChanged\Z/

      # This is the timeout used for determining if a given Kafka consumer has
      # failed or quit due to e.g. a deploy. Setting it to a lower value is NOT
      # recommended if your Hydro processor interacts with the database, since
      # Freno may wait up to 30 seconds when throttling writes. Processors that
      # do not interact with a database may lower this value to allow faster
      # consumer group rebalancing during deploys and processor failures.
      #
      # See https://kafka.apache.org/documentation/#session.timeout.ms
      options[:session_timeout] = 60.seconds

      # This value must be greater than "session_timeout"
      #
      # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
      options[:socket_timeout] = 65.seconds

      # When the processor starts consuming from a partition for the first time and has no committed offsets,
      # `start_from_beginning` determines if should start from the beginning of the log (i.e. the oldest available messages)
      # or the end of the log (i.e. the newest available messages).
      #
      # This is the equivalent of the java client `auto.offset.reset` consumer config.
      # See: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset
      options[:start_from_beginning] = false

      # Other options you may want to set...
      #
      # This will cause the Kafka consumer to wait until there is at least a
      # given number of bytes available to fetch; but the consumer will wait
      # no longer than "max_wait_time" (described below). This allows the
      # processor to wait for a large enough batch of data. The default is
      # 1 byte, meaning data will be fetched as soon as it's available. Value
      # below is for example purposes only and not a recommendation; the default
      # value of 1 should be suitable for most cases.
      # See https://kafka.apache.org/documentation/#fetch.min.bytes
      # options[:min_bytes] = 1.kilobyte
      #
      # This is the maximum amount of time the Kafka consumer will wait to
      # fetch data. The default is 500ms (0.5.seconds). Value below is for
      # example purposes only and not a recommendation; the default value of
      # 500ms should be suitable for most cases.
      # options[:max_wait_time] = 1.second
      #
      # This is the maximum amount of data that will be fetched at a time. This
      # value is specified in bytes, so the number of distinct Hydro messages
      # fetched depends on the size of those messages. The default is 1MB. You
      # may want to consider lowering this if processing each batch of messages
      # is taking more than 60 seconds in order to ensure that your processor
      # shuts down in a timely manner during deploys.
      # See https://kafka.apache.org/documentation/#max.partition.fetch.bytes
      # options[:max_bytes_per_partition] = 100.kilobytes

      resolve_tenant_context do |message|
        repo_id = message.value.dig(:alert, :repository_id)
        Repositories::Public.get_active_or_deleted(repo_id)&.owner&.business
      end

      # Public: Configure the Hydro processor
      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      # Processes an individual message from Hydro.
      #
      # This is the main hook that you must implement.
      #
      # For individual message processing (in a subclass of `SingleMessageProcessor`), this method will be called once
      # per consumer invocation. For batch message processing (in a subclass of `BatchedMessageProcessor`), the
      # default implementation of `process_batch` will call this method in a loop, once for each message in the batch
      # to be processed by a single consumer invocation.
      #
      # @param message - An individual GitHub::StreamProcessors::Message, which represents a Hydro event.
      #
      # @returns An arbitrary value that sub-classes may use for internal testing but that is ignored by this base
      #   class and all framework code in production.
      sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
      def process_message(message)
        event = message.value

        alert = proto_alert(event[:alert])
        previous_status = event[:previous_status]
        actor = User.find_by(id: event[:user_id])
        closure_user_id = extract_int64_value(event[:closure_user_id])
        closure_actor = closure_user_id ? User.find_by(id: closure_user_id) : nil
        comment = extract_comment(event[:comment])

        repo = Repositories::Public.get_active_or_deleted(alert.repository_id)
        return message.skip("Repository not found") if repo.nil?

        unless FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance, repo, repo.owner, repo.business, default: false)
          return message.skip("License compliance feature not enabled for repository")
        end

        # Default to the license compliance bot if no user is specified
        actor ||= license_compliance_bot

        # process exemption request status changes
        notify_alert_status_changed(repo, alert.status, previous_status, actor, alert, comment)

        # process PR comment updates for status changes
        if alert.status == :ALERT_STATUS_CLOSED && previous_status == :ALERT_STATUS_REVIEW_REQUESTED && closure_actor.present?
          actor = closure_actor
        end
        manage_pr_comment_for_alert_status(repo, alert.status, actor, alert)
      end

      private

      # Drives notifications on the Alert index page listing all exemption requests
      sig { params(repo: Repository, status: T.any(Symbol, Integer), previous_status: T.any(Symbol, Integer), actor: User, alert: Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert, comment: T.nilable(String)).returns(T.untyped) }
      def notify_alert_status_changed(repo, status, previous_status, actor, alert, comment)
        # Use const_get because DependencyGraph module is defined in lib/dependency_graph.rb with explicit
        # autoloads, but LicenseComplianceDelegatedClosures is in packages/security_products/app/public/
        delegated_closures_class = T.unsafe(::DependencyGraph).const_get(:LicenseComplianceDelegatedClosures)
        delegated_closures = delegated_closures_class.new(repo, actor)

        case status
        when :ALERT_STATUS_REVIEW_REQUESTED
          _, error_message = with_write { delegated_closures.create_alert_closure_request(actor, alert, comment) }
          log_result("create_alert_closure_request", repo, alert, error_message)
        when :ALERT_STATUS_CLOSED
          # Do not approve request if the alert was closed from OPEN status,
          # as it would not have an associated exemption request.
          # OLC doesn't send events for this transition, so this should not happen in practice.
          return if previous_status != :ALERT_STATUS_REVIEW_REQUESTED

          _, error_message = with_write { delegated_closures.approve_request!(actor, alert, comment) }
          log_result("approve_request", repo, alert, error_message)
        when :ALERT_STATUS_REVIEW_DENIED
          _, error_message = with_write { delegated_closures.deny_request!(actor, alert, comment) }
          log_result("deny_request", repo, alert, error_message)
        else
          log_result("no_op", repo, alert, "#{status} is not a handled LicenseComplianceAlert status")
        end
      end

      # Drives event history for alerts on the PR page.
      sig { params(repo: Repository, status: T.any(Symbol, Integer), actor: User, alert: Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert).void }
      def manage_pr_comment_for_alert_status(repo, status, actor, alert)
        pull_request = find_pull_request(repo, alert)
        return unless pull_request

        if status == :ALERT_STATUS_UNKNOWN || !status.is_a?(Symbol)
          log_result("no_op", repo, alert, "#{status} is not a handled LicenseComplianceAlert status for comments")
          return
        end

        with_write do
          update_comment_metadata(
            pull_request: pull_request,
            alert_id: alert.alert_id,
            alert_status: status,
            actor_id: actor.id,
            closure_reason: alert.closure_reason
          )
          if status == :ALERT_STATUS_CLOSED
            LicenseCompliance::PrCommentsManager.mark_automated_review_comment_as_fixed(
             pull_request, alert.alert_id
            )
          end
        end
      end

      sig { params(repo: Repository, alert: Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert).returns(T.nilable(PullRequest)) }
      def find_pull_request(repo, alert)
        has_pr_id = !alert.pull_request_id.nil? && alert.pull_request_id > 0

        # Look up pull request by ID first, fall back to number
        pull_request = if has_pr_id
          PullRequest.find_by(id: alert.pull_request_id)
        else
          PullRequest.with_number_and_repo(alert.pull_request_number, repo)
        end

        if pull_request.nil?
          log_result("manage_pr_comment_for_alert_status", repo, alert, "No pull request associated with alert")
        end

        pull_request
      end

      sig { params(pull_request: PullRequest, alert_id: Integer, alert_status: Symbol, actor_id: Integer, closure_reason: T.any(Symbol, Integer)).void }
      def update_comment_metadata(pull_request:, alert_id:, alert_status:, actor_id:, closure_reason:)
        LicenseCompliance::PrCommentsManager.update_automated_review_comment_metadata(
          pull_request: pull_request,
          alert_id: alert_id,
          alert_status: alert_status.to_s,
          actor_id: actor_id,
          closure_reason: closure_reason.to_s
        )
      end

      sig { params(operation: String, repo: Repository, alert: Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert, error_message: T.nilable(String)).void }
      def log_result(operation, repo, alert, error_message = nil)
        log_hash = {
          :"code.namespace" => "LicenseComplianceAlertStatusChangedProcessor",
          :"code.function" => "process_message",
          "gh.repo.id" => repo.id,
          "gh.closures.operation" => operation,
          "olc.alert.id" => alert.alert_id,
        }

        if error_message.nil?
          GitHub.dogstats.increment("license_compliance.alert_status_changed_processor.success", tags: ["operation:#{operation}"])
          GitHub.logger.info("LicenseComplianceAlertStatusChangedProcessor operation succeeded", **log_hash)
        else
          GitHub.dogstats.increment("license_compliance.alert_status_changed_processor.error", tags: ["operation:#{operation}"])
          GitHub.logger.error("LicenseComplianceAlertStatusChangedProcessor operation failed", **log_hash.merge("error.message" => error_message))
        end
      end

      # Extract comment string from google.protobuf.StringValue wrapper
      # which deserializes as {value: "string"}
      sig { params(comment: T.nilable(T.any(String, Hash))).returns(T.nilable(String)) }
      def extract_comment(comment)
        return nil if comment.nil?
        if comment.is_a?(String)
          comment
        elsif comment.is_a?(Hash)
          value = comment[:value]
          value.is_a?(String) ? value : nil
        end
      end

      # Extract an Integer from google.protobuf.Int64Value wrapper
      # which deserializes as { value: 123 }
      sig { params(value: T.nilable(T.any(Integer, Hash))).returns(T.nilable(Integer)) }
      def extract_int64_value(value)
        return nil if value.nil?

        if value.is_a?(Integer)
          value
        elsif value.is_a?(Hash)
          inner = value[:value]
          inner.is_a?(Integer) ? inner : nil
        end
      end

      # Convert the Hash-based alert payload into a typed protobuf entity
      sig { params(alert: T.untyped).returns(Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert) }
      def proto_alert(alert)
        Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert.new(
          alert_id: alert[:alert_id],
          alert_number: alert[:alert_number],
          closure_reason: alert[:closure_reason],
          created_at: alert[:created_at],
          enterprise_id: alert[:enterprise_id],
          manifest_name: alert[:manifest_name],
          organization_id: alert[:organization_id],
          package_manager: alert[:package_manager],
          package_name: alert[:package_name],
          package_version: alert[:package_version],
          pull_request_id: alert[:pull_request_id],
          pull_request_number: alert[:pull_request_number],
          repository_id: alert[:repository_id],
          spdx_license_expression: alert[:spdx_license_expression],
          status: alert[:status]
        )
      end

      sig { returns(Bot) }
      def license_compliance_bot
        Apps::Privileged.attribution_only_system_identity_for(:license_compliance) ||
          raise("GitHub License Compliance bot not found")
      end
    end
  end
end
