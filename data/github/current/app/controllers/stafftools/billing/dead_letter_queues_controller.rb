# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class DeadLetterQueuesController < StafftoolsController
      include GitHub::Memoizer

      before_action :dotcom_required

      depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Billing,
      ApplicationRecord::Ballast,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      only: [:index, :show]

      depends_on_clusters ApplicationRecord::Copilot,
      only: [:index, :show], optional: true

      MAX_JOBS = 100 # The maximum number of jobs to peek at one time.
      PAGE_SIZE = 10
      CLEAR_TIMEOUT = 8 # seconds
      AZURE_EMISSION_DLQ = "dead-letter-azure-emission"
      WATERMARK_HANDLER_DLQ = "dead-letter-watermark-handler"
      ZUORA_BATCH_EMISSION_DLQ = "dead-letter-zuora-batch-emission"
      ZUORA_DAILY_EMISSION_DLQ = "dead-letter-zuora-daily-emission"

      sig { void }
      def index
        queue_names = []
        queue_depths = {}
        error = ""

        begin
          queue_names = dead_letter_queue_names
          queue_depths = dead_letter_queue_depths
        rescue => e # rubocop:todo Lint/GenericRescue
          Failbot.report(e)
          error = e.message
        end


        render("stafftools/billing/dead_letter_queues/index",
          locals: {
            queue_names:,
            queue_depths:,
            error:
          })
      end

      sig { void }
      def show
        payloads = []
        error = ""

        queue_name = params[:id]
        queue_depth = aqueduct_client.queue_depth(queue: queue_name)[:depth]
        job_count = [queue_depth, MAX_JOBS].min

        begin
          payloads = aqueduct_client.peek_jobs(queue: queue_name, count: job_count)[:payloads]
        rescue Aqueduct::Client::ClientError => e
          Failbot.report(e)
          error = e.message
        end
        v2_payloads = false
        if payloads.any?
          payloads = if [AZURE_EMISSION_DLQ, WATERMARK_HANDLER_DLQ, ZUORA_BATCH_EMISSION_DLQ, ZUORA_DAILY_EMISSION_DLQ].include?(queue_name)
            dlq_payloads = payloads.map { |p| JSON.parse(p) }
            v2_payloads = true

            format_payloads_v2(dlq_payloads, queue_name)
          else
            format_payloads(payloads)
          end
        end

        render("stafftools/billing/dead_letter_queues/show",
          locals: {
            queue_name:,
            payloads:,
            error:,
            v2_payloads:
          })
      end

      sig { void }
      def do_process_queue # rubocop:todo GitHub/UseRestfulActions
        queue_name = params[:queue]
        num = params[:num].to_i

        if num <= 0
          flash[:error] = "Number of messages to process must be greater than 0."
          return redirect_to(action: :index)
        end

        response = if queue_name == "dead-letter"
          billing_platform_client.admin_process_dead_letter_queue(num: num)
        else
          billing_platform_client.admin_process_dead_letter_queue(num: num, queue_name: queue_name)
        end

        if response.is_a?(::Billing::Platform::Api::Error)
          flash[:error] = response
        else
          flash[:notice] = "Scheduled #{num} message(s) to be processed from the #{queue_name} queue."
        end

        redirect_to(action: :index)
      end

      sig { void }
      def do_clear_queue # rubocop:todo GitHub/UseRestfulActions
        queue_name = params[:queue]
        num = params[:num].to_i

        if num <= 0
          flash[:error] = "Number of messages to clear must be greater than 0."
          return redirect_to(action: :index)
        end


        ::Billing::DeadLetterQueueClearJob.perform_later(queue_name: queue_name, number_of_jobs_to_clear: num)

        flash[:notice] = "Queued up a job to clear #{num} message(s) from the #{queue_name} queue."
        redirect_to(action: :index)
      end

      private

      def format_payloads(payloads)
        payloads.map! do |payload|
          begin
            JSON.pretty_generate(JSON.parse(payload))
          rescue JSON::ParserError
            "#{payload}"
          end
        end
        payloads.paginate(page: params[:page], per_page: PAGE_SIZE)
      end

      def format_payloads_v2(payloads, queue)
        customer_hash = create_customer_hash(payloads, queue)
        hydrate_payloads(payloads, customer_hash, queue).paginate(page: params[:page], per_page: PAGE_SIZE)
      end

      def hydrate_payloads(dlq_payloads, customer_hash, queue)
        dlq_payloads.map do |payload|
          # the customer_id is in a different location depending on the queue
          is_cost_center = false
          case queue
          when WATERMARK_HANDLER_DLQ
            customer_id = payload["JobRun"]["CustomerId"]
          when AZURE_EMISSION_DLQ
            customer_id = payload["EntityDetail"]["CustomerId"]
            is_cost_center = payload["EntityDetail"]["CostCenterDetail"]["IsCostCenterProxy"]
          when ZUORA_DAILY_EMISSION_DLQ
            customer_id = payload.first["EntityDetail"]["CustomerId"]
          when ZUORA_BATCH_EMISSION_DLQ
            # No customer_id in the payload
            nil
          end

          hydrated_payload = {
            customer: customer_hash[customer_id.to_i],
            payload: prettify_payload(payload)
          }
          # Add queue-specific data
          case queue
          when AZURE_EMISSION_DLQ
            hydrated_payload[:is_cost_center] = is_cost_center || false
          when ZUORA_BATCH_EMISSION_DLQ
            hydrated_payload[:batch_date] = "#{payload['year']}-#{payload['month']}-#{payload['day']}"
            hydrated_payload[:batch_number] = payload["batchNumber"]
          when ZUORA_DAILY_EMISSION_DLQ
            hydrated_payload[:item_count] = payload.length
            hydrated_payload[:products] = payload.map { |item| item["Pricing"]["Product"] }.uniq
            hydrated_payload[:skus] = payload.map { |item| item["Pricing"]["Sku"] }.uniq
          end

          hydrated_payload
        end
      end

      def prettify_payload(payload)
        begin
          JSON.pretty_generate(payload)
        rescue JSON::ParserError
          "#{payload}"
        end
      end

      def create_customer_hash(dlq_payloads, queue)
        case queue
        when WATERMARK_HANDLER_DLQ
          customer_ids = dlq_payloads.map { |p| p["JobRun"]["CustomerId"] }
        when AZURE_EMISSION_DLQ
          customer_ids = dlq_payloads.map { |p| p["EntityDetail"]["CustomerId"] }
        when ZUORA_DAILY_EMISSION_DLQ
          customer_ids = dlq_payloads.flatten.map { |item| item.dig("EntityDetail", "CustomerId") }.uniq
        when ZUORA_BATCH_EMISSION_DLQ
          # No customer_id in the payload
          customer_ids = []
        end

        Customer.where(id: customer_ids).includes(:business).index_by(&:id)
      end


      memoize def dead_letter_queue_depths
        dead_letter_queues.map do |queue|
          queue[:queue] ||= queue[:name]
          queue[:depth] = aqueduct_client.queue_depth(queue: queue[:name])[:depth]
          queue
        end
      end

      memoize def dead_letter_queue_names
        dead_letter_queues.map { |queue| queue[:name] }
      end

      memoize def dead_letter_queues
        aqueduct_client.list_queues[:queues].select do |queue|
          queue[:name].include?("dead-letter")
        end
      end

      memoize def aqueduct_client
        GitHub.build_aqueduct_client(
          app: "billing-platform-#{Rails.env}",
          api_key: GitHub.aqueduct_billing_platform_api_key,
          api_key_version: GitHub.aqueduct_billing_platform_api_key_version,
        )
      end

      memoize def billing_platform_client
        ::Billing::Platform::Api::Client.new
      end
    end
  end
end
