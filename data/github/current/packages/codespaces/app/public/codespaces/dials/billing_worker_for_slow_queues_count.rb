# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module Dials
    class BillingWorkerForSlowQueuesCount < Codespaces::Dial
      # We need to stay under 2000 requests per second per azure storage queue: https://docs.microsoft.com/en-us/azure/storage/queues/scalability-targets#scale-targets-for-queue-storage
      # We make 3 requests to the storage queue for every worker, which we previously found takes up to 12 seconds.
      # 2000/3 ~= 666. This is the current value we've tested with the GitHub Billing team. We may need to adjust and test again.

      validates :value, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 666 }

      sig { override.returns(String) }
      def key
        "codespaces_billing_for_slow_queues_worker_count"
      end

      sig { override.returns(Integer) }
      def default_value
        60
      end

      sig { override.returns(String) }
      def description
        "This value sets the number of workers responsible for pulling billing messages from the Azure Storage only for our slower to process queues
        Queue and processing them. For example, if this value is changed from 60 to 600, the rate at which we pull
        Codespaces billing messages from the Azure Storage Queue, process those messages, and emit that data to Meuse,
        will increase."
      end

      private

      def transform_value_to_use(value)
        value.to_i
      end
    end
  end
end
