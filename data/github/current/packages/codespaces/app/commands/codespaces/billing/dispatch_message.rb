# typed: true
# frozen_string_literal: true

class Codespaces::Billing::DispatchMessage < Codespaces::Command
  include GitHub::Memoizer
  include Codespaces::BillingEntryQueryable
  class NoBillingEntryError < StandardError; end
  class MappingError < StandardError; end
  class DriftError < StandardError; end
  DISPATCHERS = [Codespaces::Billing::DispatchCodespaceMessage, Codespaces::Billing::DispatchPrebuildMessage]
  DRIFT_LOG_THRESHOLD = 3.hours.to_i

  attr_reader :billing_message, :vscs_target

  def initialize(
    message:,
    message_body:,
    vscs_target:,
    codespace_plan_id:,
    error_reporter: Codespaces::ErrorReporter
  )
    @message = message
    @billing_message = Codespaces::EphemeralBillingMessage.new(message_body:, vscs_target:, caller_name: self.class.name&.underscore, codespace_plan_id:)
    @vscs_target = vscs_target
    @error_reporter = error_reporter
    @error_reporter.push(app: "codespaces-billing")
  end

  # Note about making changes:
  # It's recommended to test changes with dev and/or ppe billing data first (see Codespaces::Billing::MeuseMessageHandler),
  # then in prod under a feature flag so you can switch it off if needed.
  def perform
    @error_reporter.push(codespace_billing_message_id: @billing_message.id) do
      GitHub.dogstats.distribution("codespaces.billing_message_drift_seconds.latency", billing_message_drift_seconds, tags: default_dogstats_tags)

      if billing_message_drift_seconds >= DRIFT_LOG_THRESHOLD
        active_job_id = GitHub.context[:active_job_id]
        aqueduct_job_id = GitHub.context[:aqueduct_job_id]

        GitHub.logger.warn(
          "Billing message drift is too high",
          "code.namespace" => "Codespaces::Billing::DispatchMessage",
          "code.function" => "perform",
          "gh.codespaces.billing_message.id" => billing_message.id,
          "gh.codespaces.billing_message.drift_seconds" => billing_message_drift_seconds,
          "gh.codespaces.billing_message.created_at" => billing_message.created_at,
          "gh.codespaces.billing_message.period_end" => billing_message.period_end,
          "gh.codespaces.billing_message.plan_subscription" => billing_message.message_body.dig("plan", "subscription"),
          "gh.codespaces.billing_message.plan_location" => billing_message.message_body.dig("plan", "location"),
          "gh.codespaces.billing_message.plan_name" => billing_message.message_body.dig("plan", "name"),
          # We should try to avoid nested arguments in logs for querying
          #   but usage details is an array of environment hashes that would likely be used for debugging not querying
          #   this means you should not expect to use this field for querying
          #   if our needs change then we would likely need to send a log per environment hash in the array instead of per billing message
          "gh.codespaces.billing_message.usage_detail" => billing_message.message_body.dig("usageDetail")&.to_json,
          "gh.codespaces.vscs_target" => vscs_target,
          "gh.catalog_service" => "github/codespaces",
          "gh.codespaces.queue_billing_message" => @message,
          "gh.active_job_id" => active_job_id,
          "gh.aqueduct_job_id" => aqueduct_job_id
        )

        error = DriftError.new("Billing message drift is too high for #{billing_message.id}. active_job_id: #{active_job_id}, aqueduct_job_id: #{aqueduct_job_id}")
        error.set_backtrace(caller)
        @error_reporter.report(error)
      end

      raise MappingError, billing_message.errors.full_messages.to_sentence unless billing_message.valid?

      to_publish = @billing_message.codespace_guids.map do |codespace_guid|
        billing_entry, _ = get_billing_entry(codespace_guid, @billing_message.period_start)
        if billing_entry.nil?
          # We don't want to publish anything to hydro if the billing_entry doesn't exist
          # This would mean the codespace was never created & stored in the database but there could be an
          # unaccounted for VM is emitting billing messages. This is normal in ppe and dev where some codespaces
          # are created locally and not stored in the production db.
          handle_nil_billing_entry(codespace_guid)
          []
        else
          tracked_usages = billing_message.tracked_usages_for(codespace_guid)
          DISPATCHERS.map do |dispatcher|
            dispatcher.call(billing_message: @billing_message, tracked_usages: tracked_usages, billing_entry: billing_entry)
          end
        end
      end

      to_publish.flatten.compact.each do |handler_result|
        handler_result.publish
      end
    end
  end

  private

  def handle_nil_billing_entry(codespace_guid)
    GitHub.dogstats.increment("codespaces.missing_billing_entry", tags: default_dogstats_tags)

    if billing_message.vscs_target == "production"

      CodespacesCleanUpEnvironmentJob.perform_later(
        plan_id: billing_message.codespace_plan_id,
        codespace_guid: codespace_guid,
        vscs_target: Codespaces::Vscs.default_target,
        location: Codespaces::Locations::Region.find(billing_message.location)&.id)

      GitHub.logger.info(
        "nil billing entry",
        "code.namespace" => "Codespaces::DispatchBilingMessage",
        "code.function" => "handle_nil_billing_entry",
        "gh.codespaces.billing_message.id" => billing_message.id,
        "gh.codespaces.guid" => codespace_guid,
        "gh.codespaces.plan.id" => billing_message.codespace_plan_id,
      )

      @error_reporter.report(NoBillingEntryError.new("No billing_entry found for codespace: #{codespace_guid}, plan: #{billing_message.codespace_plan_id}, billing message: #{billing_message.id}"))
    end
  end

  memoize def billing_message_drift_seconds
    return 0 unless @billing_message

    @billing_message.created_at.to_i - @billing_message.period_end.to_i
  end

  def default_dogstats_tags
    ["vscs_target:#{vscs_target}"]
  end
end
