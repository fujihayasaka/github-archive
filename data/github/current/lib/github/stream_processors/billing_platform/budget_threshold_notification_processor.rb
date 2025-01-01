# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module BillingPlatform
      class BudgetThresholdNotificationProcessor < BaseProcessor

        DEFAULT_GROUP_ID = "github-#{Rails.env}-billing_platform-budget_threshold_notification_processor"
        DEFAULT_SUBSCRIBE_TO = /billingplatform\.v1\.BudgetThresholdNotification\Z/

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
          customer_id = message.value.with_indifferent_access[:budget][:key][:customer_id]
          begin
            customer = Customer.find(customer_id)
            customer.business
          rescue ActiveRecord::RecordNotFound
            GitHub.logger.error(
              "Failed to resolve tenant context.",
              "code.namespace": self.class.name&.underscore,
              "code.function": __method__,
              "gh.customer.id": customer_id,
              "gh.threshold_notice.reason": "Customer not found.",
            )
            raise
          end
        end

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # Public: Process a single Hydro message
        sig { params(message: GitHub::StreamProcessors::Message).void }
        def process_message(message)
          message_value = message.value
          budget_data = message_value.deep_transform_keys { |key| key.to_s.camelize(:lower) }

          # transform the enum values to Upper Camel case for consistence with twirp response
          budget_data["budget"]["key"]["targetType"] = camelize(budget_data["budget"]["key"]["targetType"])
          budget_data["budget"]["key"]["pricingTargetType"] = camelize(budget_data["budget"]["key"]["pricingTargetType"])
          budget_data["budget"]["budgetLimitType"] = camelize(budget_data["budget"]["budgetLimitType"])

          budget = ::Billing::Platform::Api::Budget.new(budget_data)
          notification = ::Billing::Notifications::BudgetNotification.new(budget: budget).serialize

          if notification.present?
            ::Billing::Notifications::BudgetThresholdNotifier.new(notification: notification).call
          end
        end

        private

        def camelize(upper_snakecase)
          upper_snakecase.to_s.downcase.camelize(:upper)
        end
      end
    end
  end
end
