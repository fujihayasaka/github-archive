# typed: true
# frozen_string_literal: true

class Codespaces::Billing::DispatchPrebuildMessage < Codespaces::Command
  attr_reader :billing_message, :tracked_usages, :billing_entry, :vscs_target

  V_NEXT_HANDLERS = [
    Codespaces::Billing::PrebuildStorageVNextMessageHandler,
  ]

  ANALYTICS_HANDLERS = [
    Codespaces::Billing::PrebuildStorageAnalyticsMessageHandler,
  ]

  MEUSE_HANDLERS = [
    Codespaces::Billing::PrebuildStorageMeuseMessageHandler,
  ]

  class PrebuildHasBeenDeletedError < StandardError; end

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
      return unless billing_entry.is_a?(Codespaces::PrebuildTemplateBillingEntry)

      if valid_billing_message?
        dispatch
      end
    end
  end

  private

  def valid_billing_message?
    deletion_timing_makes_sense? && prebuild_configuration_is_valid?
  end

  # When a Prebuild template has been deleted, its billing entry has been updated with a deleted at date and
  # the deleted at date is not within the "periodEnd" and "periodStart" of the billing message.
  # We want to avoid sending a hydro message to Gitcoin for this Prebuild template's usage.
  # This will notify Sentry that a deleted Prebuild template is receiving billing messages outside of the allowable billable timeframe.
  # This will also signify that the Prebuild template have not been deleted correctly on the VSCS server.
  def deletion_timing_makes_sense?
    return true if billing_entry&.prebuild_deleted_at.nil?

    billing_before_deletion = @billing_message.period_start.to_datetime < billing_entry.prebuild_deleted_at.to_datetime
    unless billing_before_deletion
      GitHub.dogstats.increment("codespaces.deleted_prebuild_templates_billing_message", tags: default_dogstats_tags)
    end
    billing_before_deletion
  end

  def prebuild_configuration_is_valid?
    return true unless GitHub.flipper[:codespaces_check_prebuild_config_valid_before_billing].enabled?(billing_entry.repository) && billing_entry&.prebuild_template.present?

    # verify the prebuild configuration exists and location matches
    template = billing_entry.prebuild_template

    prebuild_configuration = template.configuration

    if prebuild_configuration.nil?
      # Prebuild Templates are deleted in the service by the combination of repo+branch+devcontainer_path+vscs_target+vscs_target_url+location
      # And Prebuild Configurations are unique by repo+branch+devcontainer_path+vscs_target+vscs_target_url
      # Because of this we need to find if there is a prebuild configuration with the same combination of attributes before deleting.
      # Otherwise we risk deleting templates for other active configurations.
      # Prebuild Configurations can no longer be nil on new templates, but for historical reasons we may have some.
      prebuild_configuration = Codespaces::PrebuildConfiguration.find_by(
        repository_id: template.repository_id,
        branch: template.branch,
        devcontainer_path: template.devcontainer_path,
        vscs_target: template.vscs_target,
        vscs_target_url: template.vscs_target_url,
      )
      # Log stat to see if we are still hitting this case, to see if we can delete this code.
      if prebuild_configuration.present?
        GitHub.dogstats.increment("codespaces.dispatch_prebuild_billing_message.prebuild_configuration_match_found", tags: default_dogstats_tags)
        GitHub.logger.warn(
          "Prebuild Configuration found for Prebuild Template with no configuration", {
            "gh.codespaces.guid" => template.guid,
          })
      end
    end


    if prebuild_configuration.nil? || prebuild_configuration.region_names.find_all { |item| item == template.location }.empty?
      Codespaces::DeletePrebuildTemplatesJob.perform_later(
        branch: template.branch,
        locations: [template.location],
        repository_id: template.repository_id,
        vscs_target: template.vscs_target,
        vscs_target_url: template.vscs_target_url,
        devcontainer_path: template.devcontainer_path,
        configuration_id: template.codespace_prebuild_configuration_id,
      )
      GitHub.dogstats.increment("codespaces.dispatch_prebuild_billing_message.prebuild_template_orphan_deleted", tags: default_dogstats_tags)

      return false
    end

    true
  end

  def dispatch
    tracked_usages.flat_map do |tracked_usage|
      handlers.map do |handler|
        handler.call(billing_message:, tracked_usage:, billing_entry:)
      end
    end.compact
  end

  def handlers
    if billing_entry.billable_owner&.billing_v_next_enabled_for_codespaces?
      V_NEXT_HANDLERS + ANALYTICS_HANDLERS
    else
      MEUSE_HANDLERS + ANALYTICS_HANDLERS
    end
  end

  def default_dogstats_tags
    ["vscs_target:#{vscs_target}"]
  end

  def with_write(&block)
    ActiveRecord::Base.connected_to(role: :writing, &block)
  end
end
