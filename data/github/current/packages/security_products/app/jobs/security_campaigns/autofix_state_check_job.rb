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
      prop :alert, SecurityCampaigns::SecurityCampaignAlert
      prop :turboscan_result, T.nilable(Turboscan::Proto::Result)
      prop :suggested_fix_state, T.nilable(Turboscan::Proto::RepoSuggestedFixState)

      sig { returns(Repository) }
      def repository
        T.must(alert.repository)
      end
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
      return if GitHub.flipper[:security_campaigns_disable_autofix_state_check_job].enabled?

      campaign = SecurityCampaigns::SecurityCampaign.find_by(id: campaign_id)
      return if campaign.nil?

      alerts = T.must(campaign.security_campaign_alerts.includes(:repository).find_each(batch_size: 100)).map do |alert|
        Alert.new(alert: alert)
      end
      alerts = alerts.sort_by { |alert| [alert.alert.repository_id, alert.alert.logical_alert_number] }
      eligible_repo_alerts, ineligible_repo_alerts = alerts.partition do |alert|
        alert.alert.repository.present? && CodeScanning::Autofix.any_enabled_for_repo?(alert.repository)
      end

      # Retrieve all Turboscan alerts to check if the tool is supported
      repo_numbers = SecurityCampaigns::CampaignBase::repo_numbers_from_alerts(eligible_repo_alerts.map(&:alert))
      turboscan_alerts = turboscan_alerts_for(campaign:, repo_numbers:)
      turboscan_alerts_by_repo_and_number = turboscan_alerts.index_by { |t| [t.repository_id, t.result.number] }
      alerts.each do |alert|
        alert.turboscan_result = turboscan_alerts_by_repo_and_number[[alert.repository.id, alert.alert.logical_alert_number]]&.result
      end

      eligible_tool_alerts, ineligible_tool_alerts = alerts.partition do |alert|
        alert.turboscan_result.present? && CodeScanning::Autofix.enabled_for_tool?(alert.repository, T.must(alert.turboscan_result&.tool).name)
      end

      # Retrieve all suggested fix states to check the status of the autofixes
      repo_numbers = SecurityCampaigns::CampaignBase::repo_numbers_from_alerts(eligible_tool_alerts.map(&:alert))
      suggested_fix_states = suggested_fix_states_for(campaign:, repo_numbers:)
      suggested_fix_states_by_repo_and_number = suggested_fix_states.index_by { |s| [s.repository_id, s.alert_number] }
      alerts.each do |alert|
        alert.suggested_fix_state = suggested_fix_states_by_repo_and_number[[alert.repository.id, alert.alert.logical_alert_number]]
      end

      campaign_autofix_state = campaign_autofix_state(campaign:, alerts: eligible_tool_alerts)

      hydro_alerts = alerts.map do |alert|
        state_updated_at = alert.suggested_fix_state&.state_updated_at&.to_time&.utc
        autofix_state = autofix_state_for_alert(alert: alert, ineligible: ineligible_repo_alerts.include?(alert) || ineligible_tool_alerts.include?(alert), allow_pending: campaign_autofix_state == CampaignAutofixState::Incomplete)

        {
          repository_id: alert.alert.repository_id,
          number: alert.alert.logical_alert_number,
          autofix_duration: state_updated_at ? { seconds: (state_updated_at - campaign.created_at).to_i } : nil,
          # Hydro only supports symbols, not the numeric values. However, the symbols don't ensure type-safety
          autofix_state: Hydro::Schemas::Github::SecurityCampaigns::V0::Entities::AutofixState.lookup(autofix_state),
        }
      end

      if campaign_autofix_state != CampaignAutofixState::Incomplete
        # Find when the last autofix was probably generated based on when the last autofix state was updated
        last_autofix_state_updated_at = eligible_tool_alerts.filter_map do |alert|
          alert.suggested_fix_state&.state_updated_at&.to_time&.utc
        end.max
        campaign_autofix_duration = last_autofix_state_updated_at.present? ? { seconds: (last_autofix_state_updated_at - campaign.created_at).to_i } : nil

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
          "gh.security_campaign.autofix_duration" => last_autofix_state_updated_at.present? ? last_autofix_state_updated_at - campaign.created_at : nil,
          "gh.security_campaign.alerts_size" => alerts.size,
          "gh.security_campaign.ineligible_repo_alerts_size" => ineligible_repo_alerts.size,
          "gh.security_campaign.ineligible_tool_alerts_size" => ineligible_tool_alerts.size,
          "gh.security_campaign.completed_alerts_size" => eligible_tool_alerts.size,
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
        elapsed_time_ms = (Time.now - T.must(campaign.created_at)) * 1000
        GitHub.dogstats.distribution("security_campaigns.autofix_deferred.duration", elapsed_time_ms, tags: ["campaign_autofix_state:#{campaign_autofix_state.serialize}"])

        complete_alerts, incomplete_alerts = eligible_tool_alerts.partition do |alert|
          alert_complete?(alert:)
        end

        GitHub.logger.info(
          "Security campaign autofixes are not yet complete",
          "gh.organization.id" => campaign.organization_id,
          "gh.security_campaign.id" => campaign.id,
          "gh.security_campaign.created_at" => campaign.created_at,
          "gh.security_campaign.alerts_size" => alerts.size,
          "gh.security_campaign.ineligible_repo_alerts_size" => ineligible_repo_alerts.size,
          "gh.security_campaign.ineligible_tool_alerts_size" => ineligible_tool_alerts.size,
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

    sig { params(campaign: SecurityCampaigns::SecurityCampaign, alerts: T::Array[Alert]).returns(CampaignAutofixState) }
    def campaign_autofix_state(campaign:, alerts:)
      # Check if all autofixes have completed for the eligible alerts (succeeded or failed, or are not eligible).
      return CampaignAutofixState::Complete if alerts.all? do |alert|
        alert_complete?(alert:)
      end

      # If the campaign was created more than 14 days ago, we will assume any alerts for which autofixes are still pending
      # or there is no state have timed out, so we don't need to do any checks for those.
      return CampaignAutofixState::TimedOut if T.must(campaign.created_at) < COMPLETION_DEADLINE.ago

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

    sig { params(campaign: SecurityCampaigns::SecurityCampaign, repo_numbers: T::Array[Turboscan::Proto::RepoNumber]).returns(T::Array[Turboscan::Proto::RepoResult]) }
    def turboscan_alerts_for(campaign:, repo_numbers:)
      return [] if repo_numbers.empty?

      turboscan_alerts = T.let([], T::Array[Turboscan::Proto::RepoResult])

      repo_numbers.each_slice(SecurityCampaigns::TURBOSCAN_MAX_PAGE_SIZE) do |repo_numbers_slice|
        alerts_response = GitHub::Turboscan.alerts_by_repo({
          owner_ids: [campaign.organization_id],
          repo_numbers: repo_numbers_slice,
          limit: SecurityCampaigns::TURBOSCAN_MAX_PAGE_SIZE,
        })

        raise StandardError.new(alerts_response&.error&.msg || "No response when fetching alerts") if alerts_response.nil? || alerts_response.error.present?

        alerts_response = alerts_response.data
        raise StandardError.new("No data when fetching alerts") if alerts_response.nil?

        page_turboscan_alerts = alerts_response.results.to_a
        turboscan_alerts += page_turboscan_alerts
      end

      turboscan_alerts
    end

    sig { params(campaign: SecurityCampaigns::SecurityCampaign, repo_numbers: T::Array[Turboscan::Proto::RepoNumber]).returns(T::Array[Turboscan::Proto::RepoSuggestedFixState]) }
    def suggested_fix_states_for(campaign:, repo_numbers:)
      return [] if repo_numbers.empty?

      suggested_fix_states = T.let([], T::Array[Turboscan::Proto::RepoSuggestedFixState])

      repo_numbers.each_slice(SecurityCampaigns::TURBOSCAN_MAX_PAGE_SIZE) do |repo_numbers_slice|
        suggested_fix_states_response = GitHub::Turboscan::SuggestedFixes.suggested_fix_states_for_org(
          owner_ids: [campaign.organization_id],
          filter: {
            repo_numbers: repo_numbers_slice,
          },
          limit: SecurityCampaigns::TURBOSCAN_MAX_PAGE_SIZE,
        )

        raise StandardError.new(suggested_fix_states_response&.error&.msg || "No response when fetching suggested fix states") if suggested_fix_states_response.nil? || suggested_fix_states_response.error.present?

        suggested_fix_states_response = suggested_fix_states_response.data
        raise StandardError.new("No data when fetching suggested fix states") if suggested_fix_states_response.nil?

        page_suggested_fix_states = suggested_fix_states_response.suggested_fix_states.to_a
        suggested_fix_states += page_suggested_fix_states
      end

      suggested_fix_states
    end

    sig { params(alert: Alert, ineligible: T::Boolean, allow_pending: T::Boolean).returns(Integer) }
    def autofix_state_for_alert(alert:, ineligible:, allow_pending:)
      if alert.turboscan_result.nil? || alert.suggested_fix_state.nil?
        if ineligible
          return Hydro::Schemas::Github::SecurityCampaigns::V0::Entities::AutofixState::AUTOFIX_STATE_INELIGIBLE
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
