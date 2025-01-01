# typed: true
# frozen_string_literal: true

class Codespaces::Billing::FetchStorageAccountNames < Codespaces::Command

  attr_reader :environment, :azure_storage_account_name, :error_reporter

  def initialize(environment: :production, azure_storage_account_name:)
    @environment = environment
    @azure_storage_account_name = azure_storage_account_name

    @error_reporter = Codespaces::ErrorReporter.new(app: "codespaces-billing")
    error_reporter.push(environment: @environment)
  end

  def perform
    estimated_queue_depth = Codespaces::StorageClient.new(
      account_name: azure_storage_account_name,
      environment: @environment
    ).approximate_messages_count

    GitHub.dogstats.gauge(
      "codespaces.fetch_billing_storage_account_names.approximate_messages_count",
      estimated_queue_depth,
      tags: default_dogstats_tags
    )
    num_of_message_batches = [estimated_queue_depth / Codespaces::StorageClient::DEFAULT_NUM_MESSAGES, 1].max
    dial_value = if Codespaces::Vscs::SLOW_BILLING_QUEUE_NAMES.include?(azure_storage_account_name)
      Codespaces::Dials::BillingWorkerForSlowQueuesCount.new.value
    else
      Codespaces::Dials::BillingWorkerCount.new.value
    end
    num_workers = [dial_value, num_of_message_batches].min

    (1..num_workers).each do |count|
      CodespacesFetchBillingMessagesJob.perform_later(
        azure_storage_account_name: azure_storage_account_name,
        sequence_number: count,
        environment: @environment
      )
    end
  rescue Codespaces::Client::BadResponseError, Codespaces::StorageClient::ConnectionFailed => e
    error_reporter.push(codespace_storage_account_name: azure_storage_account_name)
    error_reporter.report(e)
  end

  private

  def default_dogstats_tags
    ["account_name:#{azure_storage_account_name}", "vscs_target:#{environment}"]
  end

  def dd_tags
    super.concat(default_dogstats_tags)
  end
end
