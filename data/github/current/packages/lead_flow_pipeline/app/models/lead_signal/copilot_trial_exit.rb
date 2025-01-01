# typed: strict
# frozen_string_literal: true

# Represents when a user exits the Copilot trial, regardless of the reason.
module LeadSignal
  class CopilotTrialExit < Base
    extend T::Sig

    sig { override.returns(String) }
    def campaign_name
      GitHub.copilot_trial_cancel_campaign_id
    end

    sig { returns(String) }
    def campaign_status
      GitHub.copilot_trial_sf_status
    end

    sig { override.returns(T::Hash[Symbol, String]) }
    def attributes
      { gitHubLastSFDCCampaignStatus: campaign_status }
    end
  end
end
