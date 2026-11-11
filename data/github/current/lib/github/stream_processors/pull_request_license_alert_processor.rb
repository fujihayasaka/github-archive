# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class PullRequestLicenseAlertProcessor < SingleMessageProcessor
      default_to_write_connection! # rubocop:disable GitHub/JobsDoNotDefaultToWriteConnection

      DEFAULT_GROUP_ID = "github-#{Rails.env}-pull_request_license_alert_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.dependencygraph\.v1\.PullRequestLicenseCheckComplete\Z/

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
        Repositories::Public.get_active_or_deleted!(message.value[:repository_id]).owner&.business
      end

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
        repo_id = event[:repository_id]
        pull_request_id = event[:pull_request_id]
        pull_request_number = event[:pull_request_number]
        commit_sha = event[:commit_sha]
        base_sha = event[:base_sha]

        # Require at least one of pull_request_id or pull_request_number
        # Note: check for presence (not just nil) since 0 is a common default for missing integer fields
        has_pr_id = pull_request_id && pull_request_id > 0
        has_pr_number = pull_request_number && pull_request_number > 0

        if !has_pr_id && !has_pr_number
          return message.skip("Missing required parameter: must provide either pull_request_id or pull_request_number")
        end

        repo = Repository.find_by(id: repo_id)
        return message.skip("Repository not found") if repo.nil?

        unless FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance, repo, repo.owner, repo.business, default: false)
          return message.skip("License compliance feature not enabled for repository")
        end

        # Look up pull request by ID first, fall back to number
        pull_request = if has_pr_id
          PullRequest.find_by(id: pull_request_id)
        else
          PullRequest.with_number_and_repo(pull_request_number, repo)
        end

        return message.skip("Pull request not found") if pull_request.nil?

        # Use pull request's head_sha if commit_sha not provided or empty
        commit_sha = pull_request.head_sha if commit_sha.nil? || commit_sha.empty?

        if pull_request.head_sha != commit_sha
          return message.skip("Commit SHA mismatch: PR head_sha=#{pull_request.head_sha}, event commit_sha=#{commit_sha}")
        end

        # Compute merge base if base_sha not provided or empty
        computed_merge_base_sha = pull_request.find_best_merge_base_sha(head_sha: commit_sha)
        base_sha = computed_merge_base_sha if base_sha.nil? || base_sha.empty?

        if base_sha != computed_merge_base_sha
          return message.skip("Base SHA mismatch: PR merge_base_sha=#{computed_merge_base_sha}, event base_sha=#{base_sha}")
        end

        GitHub.logger.info("Processing PullRequestLicenseCheckComplete event", {
          "gh.repo.id" => repo_id,
          "gh.pull_request.number" => pull_request.number,
          "git.commit.sha" => commit_sha,
        })

        LicenseCompliance::PrCommentsManager.manage_automated_review_comments(
          pull_request: pull_request,
          open_license_alerts: proto_alerts(event[:open_license_alerts]),
          remediation_guidance: event[:remediation_guidance]
        )
      end

      private

      sig { params(alerts: T::Array[T.untyped]).returns(T::Array[Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert]) }
      def proto_alerts(alerts)
        alerts.map do
          Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert.new(
            alert_id: _1[:alert_id],
            alert_number: _1[:alert_number],
            manifest_name: _1[:manifest_name],
            package_name: _1[:package_name],
            spdx_license_expression: _1[:spdx_license_expression]
          )
        end
      end
    end
  end
end
