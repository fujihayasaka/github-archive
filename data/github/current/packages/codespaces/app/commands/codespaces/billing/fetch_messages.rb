# typed: true
# frozen_string_literal: true

class Codespaces::Billing::FetchMessages < Codespaces::Command
  include Scientist
  include Codespaces::BillingEntryQueryable
  include Codespaces::BillingMessageValidator

  class AdditionalParamsError < Codespaces::Error; end
  class PlanNameNotFound < Codespaces::Error; end

  MAX_DEQUEUE_ATTEMPTS = 3

  attr_reader :azure_storage_account_name, :environment
  def initialize(
    azure_storage_account_name:,
    environment: :production,
    error_reporter: Codespaces::ErrorReporter.new(app: "codespaces-billing"),
    client: Codespaces::StorageClient.new(account_name: azure_storage_account_name, environment: environment)
  )
    @azure_storage_account_name = azure_storage_account_name
    @environment = environment
    @error_reporter = error_reporter
    @client = client
    @messages_scheduled_for_deletion = []

    @total_messages = 0
    @dead_letter_messages = 0

    @error_reporter.push(codespace_storage_account_name: azure_storage_account_name)
  end

  def perform
    messages = @client.get_messages(visibility_timeout: 10.minutes)
    @total_messages = messages.count

    get_messages_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # approximate_messages_count could be higher than the actual number of messages in the queue, but not lower.
    # This makes sure we're not doing many extra API calls if messages is actually empty.
    #
    # See: https://docs.microsoft.com/en-us/rest/api/storageservices/get-queue-metadata#response-headers
    if messages.empty?
      return false
    end

    messages.each do |message|
      plan_name = message.body.dig("plan", "name")

      handle_errors_with_context(start_time: get_messages_start_time, plan_name: plan_name, message: message) do
        unless validate_required_fields(message)
          move_to_dead_letter_queue(message) if dead_letter?(message)
          next
        end

        unless plan = find_plan!(message, plan_name)
          move_to_dead_letter_queue(message)
          next
        end
        if FeatureFlag.vexi.enabled_or_raise?(:codespaces_hide_message_in_billing) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          CodespacesDispatchBillingMessageJob.perform_later(message: nil, message_body: message.body, vscs_target: @environment, codespace_plan_id: plan.id)
        else
          CodespacesDispatchBillingMessageJob.perform_later(message: message.to_json, message_body: message.body, vscs_target: @environment, codespace_plan_id: plan.id)
        end

        validate_no_extra_fields(message)

        ack_message(message)
      end
    end

    delete_scheduled_messages
    more_messages_in_queue?
  ensure
    record_message_metrics
  end

  def ack_message(message)
    @messages_scheduled_for_deletion << message
  end

  def delete_scheduled_messages
    @client.delete_messages(@messages_scheduled_for_deletion)
  end

  def more_messages_in_queue?
    approximate_messages_count = @client.approximate_messages_count

    GitHub.dogstats.gauge(
      "codespaces.fetch_billing_messages.approximate_messages_count",
      approximate_messages_count,
      tags: default_dogstats_tags
    )
    approximate_messages_count > 0
  end

  def validate_required_fields(message)
    validation_errors = GitHub.dogstats.distribution_time("codespaces.fetch_billing_messages.json_validation.time.latency") do
      validate_message(message_body: message.body, fragment_path: "#/properties/additionalPropertiesAllowed")
    end

    if validation_errors.any?
      # we will send this no matter what
      error = Codespaces::Error.new("Failed vscs_billing_schema validation\nMessage Id - #{message.event_id}\nErrors\n#{validation_errors}")
      @error_reporter.report(error)

      false
    else
      true
    end
  end

  def validate_no_extra_fields(message)
    strict_validation_errors = GitHub.dogstats.distribution_time("codespaces.fetch_billing_messages.strict_json_validation.time.latency") do
      validate_message(message_body: message.body, fragment_path: "#/properties/additionalPropertiesDenied")
    end

    if strict_validation_errors.any?
      @error_reporter.report(AdditionalParamsError.new(strict_validation_errors.join(", ")), billing_message_id: message.id)

      false
    else
      true
    end
  end

  def find_plan!(message, plan_name)
    GitHub.dogstats.distribution_time("codespaces.fetch_billing_messages.find_plan.time.latency") do
      Codespaces::Plan.find_by!(name: plan_name)
    end
  rescue ActiveRecord::RecordNotFound => e
    plan_not_found = PlanNameNotFound.new
    GitHub.logger.error(
      :exception => plan_not_found,
      "code.namespace" => "Codespaces::Billing::FetchMessages",
      "code.function" => "call",
      "gh.codespaces.plan.name" => plan_name,
      "gh.codespaces.billing_message.event_id" => message.event_id,
      "gh.codespaces.azure_storage_account_name" => @azure_storage_account_name,
      "gh.codespaces.vscs_target" => @environment,
    )

    # only send an error if this was production to cut down on noise
    @error_reporter.report(e) if @environment == :production

    nil
  end

  def move_to_dead_letter_queue(message)
    # the dlq is only used for production messages
    if @environment == :production
      ActiveRecord::Base.connected_to(role: :writing) do
        Codespaces::UnprocessedBillingMessage.create!(
          message_id: message.id,
          azure_storage_account_name: @azure_storage_account_name,
          body: message.body.to_json
        )
      end

      @dead_letter_messages += 1 # this feeds the datadog monitor so only production
    end

    ack_message(message)
  end

  def dead_letter?(message)
    message.dequeue_count >= MAX_DEQUEUE_ATTEMPTS
  end

  def handle_errors_with_context(start_time:, plan_name:, message:, &block)
    @error_reporter.push(codespace_plan_name: plan_name, codespace_azure_message_id: message.id, codespace_billing_message_id: message.event_id) do
      begin
        yield
      rescue Codespaces::Client::BadResponseError
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @error_reporter.push(codespace_time_since_get_messages: (end_time - start_time) * 1_000)
        raise
      end
    end
  end

  def record_message_metrics
    GitHub.dogstats.count(
      "codespaces.fetch_billing_messages.messages_fetched",
      @total_messages,
      tags: default_dogstats_tags
    )
    GitHub.dogstats.count(
      "codespaces.fetch_billing_messages.dead_letters",
      @dead_letter_messages,
      tags: default_dogstats_tags
    )
  end

  def default_dogstats_tags
    ["account_name:#{azure_storage_account_name}", "vscs_target:#{environment}"]
  end
end
