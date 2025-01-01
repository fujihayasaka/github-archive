# typed: true
# frozen_string_literal: true

class Codespaces::Billing::DispatchCodespaceMessage < Codespaces::Command
  class CodespaceHasBeenDeprovisionedError < StandardError; end

  ANALYTICS_HANDLERS = [
    Codespaces::Billing::ComputeAnalyticsMessageHandler,
    Codespaces::Billing::StorageAnalyticsMessageHandler,
  ]

  MEUSE_HANDLERS = [
    Codespaces::Billing::ComputeMeuseMessageHandler,
    Codespaces::Billing::StorageMeuseMessageHandler,
  ]

  V_NEXT_HANDLERS = [
    Codespaces::Billing::StorageVNextMessageHandler,
    Codespaces::Billing::ComputeVNextMessageHandler,
  ]

  COPILOT_WORKSPACE_HANDLERS = [
    Codespaces::Billing::CopilotWorkspaceMessageHandler,
  ]

  SPARK_WORKBENCH_HANDLERS = [
    Codespaces::Billing::SparkWorkbenchMessageHandler,
  ]

  attr_reader :billing_message, :tracked_usages, :billing_entry, :vscs_target

  def initialize(
    billing_message:,
    tracked_usages:,
    billing_entry:,
    error_reporter: Codespaces::ErrorReporter
  )
    @billing_message = billing_message
    @vscs_target = billing_message.vscs_target
    @tracked_usages = tracked_usages
    @billing_entry = billing_entry
    @error_reporter = error_reporter
    @error_reporter.push(app: "codespaces-billing")
  end

  def perform
    @error_reporter.push(codespace_billing_message_id: @billing_message.id) do
      return unless billing_entry.is_a?(Codespaces::BillingEntry)

      perform_health_checks
      if valid_billing_message?
        dispatch
      end
    end
  end

  private

  def perform_health_checks
    mark_spammy_billiable_owner
    accessibility_check
    enforce_concurrency_limits
  end

  def valid_billing_message?
    deletion_timing_makes_sense?
  end

  def mark_spammy_billiable_owner
    if billing_entry&.billable_owner&.spammy?
      GitHub.dogstats.increment("codespaces.process_billing_message.spammy_billable_owner", tags: default_dogstats_tags)
    end
  end

  def accessibility_check
    # Reactively handle a codespace becoming unbillable
    if billing_entry&.codespace.present? && !billing_entry&.codespace.accessible?
      GitHub.dogstats.increment("codespaces.accessibility_check", tags: ["is_accessible:no"] + default_dogstats_tags)
      GlobalInstrumenter.instrument(::Codespaces::Events::INACCESSIBLE_CODESPACE, {
        codespace_id: billing_entry.codespace.id,
      })
    else
      GitHub.dogstats.increment("codespaces.accessibility_check", tags: ["is_accessible:yes"] + default_dogstats_tags)
    end
  end

  def enforce_concurrency_limits
    owner = billing_entry.codespace_owner
    return true unless owner && FeatureFlag.vexi.enabled_or_raise?(:codespaces_retroactive_concurrency_enforcement_billing, owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    billable_owner = billing_entry.billable_owner
    Codespaces::ConcurrencyPolicy.new(owner, billable_owner:).enforce_concurrency_limits!
    true
  end

  def deletion_timing_makes_sense?
    return true if billing_entry&.codespace_deprovisioned_at.nil?
    billing_before_deletion = billing_message.period_start.to_datetime < billing_entry&.codespace_deprovisioned_at.to_datetime

    unless billing_before_deletion
      GitHub.dogstats.increment("codespaces.deprovisioned_codespaces_billing_message", tags: default_dogstats_tags)
    end
    billing_before_deletion
  end

  def dispatch
    tracked_usages.flat_map do |tracked_usage|
      handlers.map do |handler|
        handler.call(billing_message:, tracked_usage:, billing_entry:)
      end
    end.compact
  end

  def handlers
    ANALYTICS_HANDLERS + V_NEXT_HANDLERS + COPILOT_WORKSPACE_HANDLERS + SPARK_WORKBENCH_HANDLERS
  end

  def default_dogstats_tags
    ["vscs_target:#{vscs_target}"]
  end
end
