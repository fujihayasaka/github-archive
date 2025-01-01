# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class UsageThresholdNotificationProcessor < BaseProcessor
      extend T::Sig

      DEFAULT_GROUP_ID = "github-#{Rails.env}-usage_threshold_notification_processor"
      DEFAULT_SUBSCRIBE_TO = /meuse\.v0\.UsageThresholdReached\Z/

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

      # Public: Configure the Hydro processor
      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      # Public: Process a single Hydro message
      #
      # message - The Hydro message to process
      #
      # Returns nothing
      def process_message(message)
        return unless GitHub.flipper[:usage_threshold_notifications_processor].enabled?

        message_value = message.value
        return message.skip("Product name is blank") if message_value[:product][:name].blank?

        is_shared_storage = message_value[:product][:name] == ::Billing::Notifications::SHARED_STORAGE_PRODUCT
        return message.skip("SharedStorage not supported right now") if is_shared_storage

        product_name = message_value[:product][:name]

        is_codespaces = (product_name == ::Billing::Notifications::CODESPACES_PRODUCT)
        product_name = codespaces_product_name(message_value[:product_sku][:name]) if is_codespaces

        customer = Customer.find_by(id: message_value[:customer_id])
        return message.skip("Customer not found") unless customer.present?
        return message.skip("Billable owner not found") unless customer.billable_owner.present?

        MeteredBillingThresholdNotifierJob.perform_later(
          owner_id: T.must(customer.billable_owner).id,
          product: product_name,
          owner_type: T.must(customer.billable_owner).class.to_s,
        )
      end

      # Public: Maps product names from the products table to those in our config:
      #         https://github.com/github/github/blob/master/config/metered_products.yml
      #         This is necessary because MeteredBillingThresholdNotifierJob uses these names.
      #
      # sku_name - The name of the SKU for the product
      #
      # Returns String
      def codespaces_product_name(sku_name)
        return ::Billing::Notifications::CODESPACES_COMPUTE_PRODUCT if sku_name.start_with?("compute")

        ::Billing::Notifications::CODESPACES_STORAGE_PRODUCT
      end
    end
  end
end
