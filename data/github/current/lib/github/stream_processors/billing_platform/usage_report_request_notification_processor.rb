# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module BillingPlatform
      class UsageReportRequestNotificationProcessor < SingleMessageProcessor
        DEFAULT_GROUP_ID = "github-#{Rails.env}-billing_platform-usage_report_request_notification_processor"
        DEFAULT_SUBSCRIBE_TO = /billingplatform\.v1\.UsageReportRequestNotification\Z/

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

        resolve_tenant_context do |message|
          requester_id = message.value[:actor_id]
          requester = ::User.find(requester_id)
          requester.enterprise_managed_business
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          message_value = message.value

          requester = User.find_by(id: message_value[:actor_id])
          return message.skip("requester is not found") if requester.nil?

          customer = Customer.find_by(id: message_value[:customer_id])
          return message.skip("customer is not found") if customer.nil?

          # The Customer table is not tenant-scoped, so we need to check if the requester is associated with the customer
          if GitHub.multi_tenant_enterprise? && requester.enterprise_managed_business != customer.billable_owner
            return message.skip("requester is not associated with the customer") unless GitHub::CurrentTenant.stafftools_tenant?
          end

          billable_owner = customer.billable_owner
          return message.skip("billable_owner is not found") if billable_owner.nil?

          unless message_value[:success]
            ::Billing::BillingPlatformUsageReportMailer.usage_report_error(requester.default_notification_email, billable_owner).deliver_later
            return
          end

          return message.skip("array is empty") if message_value[:blob_urls].size.zero?

          start_date = Time.at(message_value[:start_date]).to_datetime.utc
          end_date = Time.at(message_value[:end_date]).to_datetime.utc

          metered_export_records = []
          with_write do
            message_value[:blob_urls].each do |url|
              metered_export_record = ::Billing::MeteredUsageExport.create!(
                requester: requester,
                billable_owner: billable_owner,
                starts_on: start_date,
                ends_on: end_date,
                filename: url.split("/").last,
                is_azure_blob_storage:  true,
              )

              metered_export_records << metered_export_record
            end
          end

          report_type = get_report_type(message_value[:report_type])

          ::Billing::BillingPlatformUsageReportMailer.usage_report_complete(
            requester.default_notification_email,
            metered_export_records,
            get_period_text_for_start_and_end_dates(start_date, end_date),
            report_type,
          ).deliver_later
        end

        def get_period_text_for_start_and_end_dates(start_date, end_date)
          start_string = start_date.strftime("%B %d, %Y")
          end_string = end_date.strftime("%B %d, %Y")

          if start_string == end_string
            start_string
          else
            "#{start_string} - #{end_string}"
          end
        end

        sig { params(report_type: Symbol).returns(Integer) }
        def get_report_type(report_type)
          found_report_type = Hydro::Schemas::Billingplatform::V1::Entities::ReportType.resolve(report_type)
          return Hydro::Schemas::Billingplatform::V1::Entities::ReportType::UNKNOWN_REPORT_TYPE unless found_report_type

          found_report_type
        end
      end
    end
  end
end
