# typed: true
# frozen_string_literal: true

module Site
  class GhasTrialRequest
    extend T::Sig
    include ActiveModel::Model

    attr_accessor :organization, :email, :name, :country, :marketing_email_opt_in, :requester, :utm_campaign, :utm_medium, :utm_source, :utm_content

    validates :organization, :email, :name, presence: true
    validates :email, format: { with: UserEmail::MarketingDependency::EMAIL_REGEX }

    def can_send_request?
      return false if GitHub.enterprise?
      return false unless requester.present?
      return false unless organization.present?
      if organization.delegate_billing_to_business?
        return true if organization.business.adminable_by?(requester)
      end
      organization.adminable_by?(requester)
    end

    def save
      return false unless valid? && can_send_request?

      send_request
      self
    end

    def send_request
      log_request_on_hydro
      log_request_to_marketing_forms_api
    end

    def cdl_program_name
      GitHub.ghas_trial_campaign_id
    end

    def source
      GitHub.ghas_trial_source.presence || cdl_program_name
    end

    def salesforce_campaign_status
      GitHub.ghas_trial_status
    end

    private

    def log_request_to_marketing_forms_api
      MarketingForms::Submission.enqueue!(
        form_name: "ghas-trial",
        raw_data: {
          country: country,
          name: name,
          email: email,
          org_name: organization.name,
          marketingConsent: marketing_email_opt_in? ? "optInExplicit" : nil,
          cDLProgramName: cdl_program_name,
          source: source,
          sFDCLastCampaignStatus: salesforce_campaign_status,
          utm_campaign: utm_campaign,
          utm_medium: utm_medium,
          utm_source: utm_source,
          utm_content: utm_content
        }.compact
      )
    end

    def log_request_on_hydro
      GlobalInstrumenter.instrument("create.ghas_trial_request",
        organization_id: organization.id,
        submitted_at: Time.now.utc,
      )
    end

    sig { returns(T::Boolean) }
    def marketing_email_opt_in?
      marketing_email_opt_in.present? && marketing_email_opt_in != "false" && marketing_email_opt_in != "0"
    end
  end
end
