# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This job is triggered every hour after creating a new security campaign to check if the autofixes
  # for all alerts in the campaign have been created, or have failed to generate. If that is the case,
  # it will emit a Hydro event.
  class AutofixStateCheckJob < ApplicationJob
    # The maximum time we will wait for the autofixes to complete before we consider the campaign complete
    COMPLETION_DEADLINE = T.let(14.days, ActiveSupport::Duration)

    queue_as :security_campaigns

    retry_on_dirty_exit

    class Alert < T::Struct
      prop :number, Integer
      prop :turboscan_result, T.nilable(Turboscan::Proto::Result)
      prop :suggested_fix_state, T.nilable(Turboscan::Proto::RepoSuggestedFixState)
      prop :repository, Repository
    end

    class CampaignAutofixState < T::Enum
      enums do
        Incomplete = new("incomplete")
        Complete = new("complete")
        TimedOut = new("timed_out")
      end
    end

    sig { params(campaign_id: Integer).void }
    def perform(campaign_id:)
      return if GitHub.enterprise?
      return if FeatureFlag.vexi.enabled?(:security_campaigns_disable_autofix_state_check_job, default: false)

      campaign = SecurityCampaigns::SecurityCampaign.published.find_by(id: campaign_id)
      return if campaign.nil?

      alerts = build_alerts_for(campaign:)

      autofix_enabled_repo_alerts, autofix_not_enabled_repo_alerts = alerts.partition do |alert|
        alert.repository.present? && CodeScanning::Autofix.any_enabled_for_repo?(alert.repository)
      end

      autofix_enabled_tool_alerts, autofix_not_enabled_tool_alerts = autofix_enabled_repo_alerts.partition do |alert|
        alert.turboscan_result.present? && CodeScanning::Autofix.enabled_for_tool?(alert.repository, T.must(alert.turboscan_result&.tool).name)
      end

      # Retrieve all suggested fix states to check the status of the autofixes
      add_suggested_fix_states(alerts:, campaign:)

      campaign_autofix_state = campaign_autofix_state(campaign:, alerts: autofix_enabled_tool_alerts)

      hydro_alerts = alerts.map do |alert|
        state_updated_at = alert.suggested_fix_state&.state_updated_at&.to_time&.utc
        autofix_state = autofix_state_for_alert(alert: alert, not_enabled: autofix_not_enabled_repo_alerts.include?(alert) || autofix_not_enabled_tool_alerts.include?(alert), allow_pending: campaign_autofix_state == CampaignAutofixState::Incomplete)

        {
          repository_id: alert.repository.id,
          number: alert.number,
          autofix_duration: state_updated_at ? { seconds: (state_updated_at - campaign.published_at).to_i } : nil,
          # Hydro only supports symbols, not the numeric values. However, the symbols don't ensure type-safety
          autofix_state: Hydro::Schemas::Github::SecurityCampaigns::V0::Entities::AutofixState.lookup(autofix_state),
        }
      end

      ineligible_alerts_size = hydro_alerts.count { |alert| alert[:autofix_state] == :AUTOFIX_STATE_INELIGIBLE }

      if campaign_autofix_state != CampaignAutofixState::Incomplete
        # Find when the last autofix was probably generated based on when the last autofix state was updated
        last_autofix_state_updated_at = autofix_enabled_tool_alerts.filter_map do |alert|
          alert.suggested_fix_state&.state_updated_at&.to_time&.utc
        end.max
        campaign_autofix_duration = last_autofix_state_updated_at.present? ? { seconds: (last_autofix_state_updated_at - campaign.published_at).to_i } : nil

        if campaign_autofix_duration.present?
          campaign_autofix_duration_ms = (campaign_autofix_duration[:seconds] * 1000)
          campaign_autofix_duration_kind = campaign_autofix_duration_ms <= 0 ? "negative" : "positive"
          GitHub.dogstats.distribution("security_campaigns.autofix.duration", campaign_autofix_duration_ms, tags: ["kind:#{campaign_autofix_duration_kind}", "campaign_autofix_state:#{campaign_autofix_state.serialize}"])
        else
          GitHub.dogstats.increment("security_campaigns.autofix_no_duration", tags: ["campaign_autofix_state:#{campaign_autofix_state.serialize}"])
        end

        GitHub.logger.info(
          "Security campaign autofixes have completed",
          "gh.organization.id" => campaign.organization_id,
          "gh.security_campaign.id" => campaign.id,
          "gh.security_campaign.created_at" => campaign.created_at,
          "gh.security_campaign.published_at" => campaign.published_at,
          "gh.security_campaign.autofix_duration" => last_autofix_state_updated_at.present? ? last_autofix_state_updated_at - campaign.published_at : nil,
          "gh.security_campaign.alerts_size" => alerts.size,
          "gh.security_campaign.autofix_not_enabled_repo_alerts_size" => autofix_not_enabled_repo_alerts.size,
          "gh.security_campaign.autofix_not_enabled_tool_alerts_size" => autofix_not_enabled_tool_alerts.size,
          "gh.security_campaign.autofix_not_eligible_alerts_size" => ineligible_alerts_size,
          "gh.security_campaign.completed_alerts_size" => autofix_enabled_tool_alerts.size,
          "gh.security_campaign.autofix_state" => campaign_autofix_state.serialize,
        )

        GlobalInstrumenter.instrument("security_campaigns.security_campaign_autofix_generation_complete", {
          security_campaign: campaign,
          duration: campaign_autofix_duration,
          alerts: hydro_alerts,
        })
      else
        # The campaign isn't complete yet, so we need to check again in an hour
        self.class.set(wait: 1.hour).perform_later(campaign_id:)

        GitHub.dogstats.increment("security_campaigns.autofix_check_deferred", tags: ["campaign_autofix_state:#{campaign_autofix_state.serialize}"])
        elapsed_time_ms = (Time.now - campaign.published_at).to_f * 1000
        GitHub.dogstats.distribution("security_campaigns.autofix_deferred.duration", elapsed_time_ms, tags: ["campaign_autofix_state:#{campaign_autofix_state.serialize}"])

        complete_alerts, incomplete_alerts = autofix_enabled_tool_alerts.partition do |alert|
          alert_complete?(alert:)
        end

        GitHub.logger.info(
          "Security campaign autofixes are not yet complete",
          "gh.organization.id" => campaign.organization_id,
          "gh.security_campaign.id" => campaign.id,
          "gh.security_campaign.created_at" => campaign.created_at,
          "gh.security_campaign.published_at" => campaign.published_at,
          "gh.security_campaign.alerts_size" => alerts.size,
          "gh.security_campaign.autofix_not_enabled_repo_alerts_size" => autofix_not_enabled_repo_alerts.size,
          "gh.security_campaign.autofix_not_enabled_tool_alerts_size" => autofix_not_enabled_tool_alerts.size,
          "gh.security_campaign.autofix_not_eligible_alerts_size" => ineligible_alerts_size,
          "gh.security_campaign.completed_alerts_size" => complete_alerts.size,
          "gh.security_campaign.incomplete_alerts_size" => incomplete_alerts.size,
          "gh.security_campaign.autofix_state" => campaign_autofix_state.serialize,
        )

        GlobalInstrumenter.instrument("security_campaigns.security_campaign_autofix_generation_incomplete", {
          security_campaign: campaign,
          alerts: hydro_alerts,
        })
      end
    end

    private

    sig { params(campaign: SecurityCampaigns::SecurityCampaign).returns(T::Array[Alert]) }
    def build_alerts_for(campaign:)
      turboscan_alerts = SecurityCampaigns::TurboscanHelper.alerts_by(campaign:)
      campaign_repos = T.must(campaign.organization).repositories.where(id: turboscan_alerts.map { |a| a.repository_id }).index_by(&:id)
      alerts = turboscan_alerts.map do |turboscan_result|
        repository = campaign_repos[turboscan_result.repository_id]
        Alert.new(
          number: T.must(turboscan_result.result).number,
          repository:,
          turboscan_result: T.must(turboscan_result.result)
        )
      end
      alerts.sort_by { |alert| [alert.repository.id, alert.number] }
    end

    sig { params(alerts: T::Array[Alert], campaign: SecurityCampaigns::SecurityCampaign).void }
    def add_suggested_fix_states(alerts:, campaign:)
      suggested_fix_states = SecurityCampaigns::TurboscanHelper.suggested_fix_states_by(campaign:)

      suggested_fix_states_by_repo_and_number = suggested_fix_states.index_by { |s| [s.repository_id, s.alert_number] }
      alerts.each do |alert|
        alert.suggested_fix_state = suggested_fix_states_by_repo_and_number[[alert.repository.id, alert.number]]
      end
    end

    sig { params(campaign: SecurityCampaigns::SecurityCampaign, alerts: T::Array[Alert]).returns(CampaignAutofixState) }
    def campaign_autofix_state(campaign:, alerts:)
      # Check if all autofixes have completed for the eligible alerts (succeeded or failed, or are not eligible).
      return CampaignAutofixState::Complete if alerts.all? do |alert|
        alert_complete?(alert:)
      end

      # If the campaign was published more than 14 days ago, we will assume any alerts for which autofixes are still pending
      # or there is no state have timed out, so we don't need to do any checks for those.
      return CampaignAutofixState::TimedOut if campaign.published_at < COMPLETION_DEADLINE.ago

      CampaignAutofixState::Incomplete
    end

    sig { params(alert: Alert).returns(T::Boolean) }
    def alert_complete?(alert:)
      return true if alert.turboscan_result.nil? # If there is no Turboscan alert, it can never complete
      return false if alert.suggested_fix_state.nil? # If we don't have an autofix state, we assume the SFA has not been created yet

      suggested_fix_state = T.must(alert.suggested_fix_state)

      return true unless suggested_fix_state.eligible # If the alert is not eligible for an autofix, it's completed

      state = suggested_fix_state.state
      state = Turboscan::Proto::SuggestedFixAlertState.resolve(state) if state.is_a?(Symbol)

      # The autofix is considered to have completed if the state is not pending or unknown (the latter of which should never happen)
      completed = state != Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_PENDING && state != Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_UNKNOWN

      completed
    end

    sig { params(alert: Alert, not_enabled: T::Boolean, allow_pending: T::Boolean).returns(Integer) }
    def autofix_state_for_alert(alert:, not_enabled:, allow_pending:)
      if alert.turboscan_result.nil? || alert.suggested_fix_state.nil?
        if not_enabled
          return Hydro::Schemas::Github::SecurityCampaigns::V0::Entities::AutofixState::AUTOFIX_STATE_NOT_ENABLED
        else
          return Hydro::Schemas::Github::SecurityCampaigns::V0::Entities::AutofixState::AUTOFIX_STATE_UNKNOWN
        end
      end

      suggested_fix_state = T.must(alert.suggested_fix_state)

      return Hydro::Schemas::Github::SecurityCampaigns::V0::Entities::AutofixState::AUTOFIX_STATE_INELIGIBLE unless suggested_fix_state.eligible

      alert_state = suggested_fix_state.state
      alert_state = Turboscan::Proto::SuggestedFixAlertState.resolve(alert_state) if alert_state.is_a?(Symbol)

      case alert_state
      when Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_PENDING
        if allow_pending
          Hydro::Schemas::Github::SecurityCampaigns::V0::Entities::AutofixState::AUTOFIX_STATE_PENDING
        else
          Hydro::Schemas::Github::SecurityCampaigns::V0::Entities::AutofixState::AUTOFIX_STATE_TIMED_OUT
        end
      when Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_APPLIED,
        Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_VALID,
        Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_VALID_MISSING_DEP
        Hydro::Schemas::Github::SecurityCampaigns::V0::Entities::AutofixState::AUTOFIX_STATE_SUCCESS
      when Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_ERROR,
        Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_INVALID
        Hydro::Schemas::Github::SecurityCampaigns::V0::Entities::AutofixState::AUTOFIX_STATE_FAILED
      when Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_RULE_NOT_SUPPORTED
        Hydro::Schemas::Github::SecurityCampaigns::V0::Entities::AutofixState::AUTOFIX_STATE_INELIGIBLE
      when Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_UNKNOWN
        # This should not really happen
        Hydro::Schemas::Github::SecurityCampaigns::V0::Entities::AutofixState::AUTOFIX_STATE_UNKNOWN
      else
        # This should not really happen
        Hydro::Schemas::Github::SecurityCampaigns::V0::Entities::AutofixState::AUTOFIX_STATE_UNKNOWN
      end
    end
  end
end
