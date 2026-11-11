# typed: strict
# frozen_string_literal: true

module Site
  class EnterpriseContactRequest < ApplicationRecord::Domain::Site
    serialize :product_interest, coder: JSON

    enum :status, [:submission_pending, :submitted]
    enum :variant, [:control]

    before_validation :generate_submission_id
    before_save :set_default_marketing_email_opt_in

    validates :first_name, presence: true
    validates :last_name, presence: true
    validates :company, presence: true
    validates :job_title, presence: true
    validates :email, format: { with: UserEmail::MarketingDependency::EMAIL_REGEX }, presence: true
    validates :submission_id, presence: true
    validate :product_interest_as_array

    sig { returns(Symbol) }
    def submission_type
      :contact
    end

    sig { returns(String) }
    def fetch_cdl_program_name
      self[:cdl_program_name].presence || GitHub.enterprise_contact_campaign_id
    end

    sig { returns(String) }
    def fetch_source
      self[:source].presence || GitHub.enterprise_contact_source.presence || fetch_cdl_program_name
    end

    sig { returns(String) }
    def salesforce_campaign_status
      self[:sfdc_last_campaign_status].presence || GitHub.enterprise_contact_status
    end

    sig { returns(T::Hash[Symbol, String]) }
    def marketing_forms_data
      {
        company: company,
        contactComments: request_details,
        country: country,
        email_address: email,
        first_name: first_name,
        last_name: last_name,
        title: job_title,
        marketingConsent: marketing_consent,
        phone: phone,
        cDLProgramName: fetch_cdl_program_name,
        source: fetch_source,
        sFDCLastCampaignStatus: salesforce_campaign_status,
        directToSfdcCampaignId: direct_to_sfdc_campaign_id,
        referrer_details: referrer_details,
        utm_campaign: utm_campaign,
        utm_medium: utm_medium,
        utm_source: utm_source,
        number_of_developers: number_of_developers,
        product_interest: product_interest&.join(","),
        short_custom_1: short_custom_1,
        github_enterprise_cloud_set_up: github_enterprise_cloud_set_up,
        ado_is_cloud_hosted: ado_is_cloud_hosted,
        using_git_or_version_control: using_git_or_version_control,
      }.compact
    end

    sig { void }
    def enqueue_submission_job
      return unless persisted?
      EnterpriseContactRequestSubmissionJob.perform_later(id)
    end

    private

    sig { returns(T.nilable(MarketingForms::Consent)) }
    def marketing_consent
      if marketing_email_opt_in?
        MarketingForms::Consent::Explicit
      elsif country == "US"
        MarketingForms::Consent::Implicit
      end
    end

    sig { void }
    def set_default_marketing_email_opt_in
      self.marketing_email_opt_in = false if marketing_email_opt_in.blank?
    end

    sig { returns(T.nilable(String)) }
    def email_domain
      return if email.nil?
      email.split("@").last
    end

    sig { void }
    def generate_submission_id
      self.submission_id = SecureRandom.uuid unless self.submission_id.present?
    end

    sig { returns(T.nilable(String)) }
    def referrer_details
      { ref_page: ref_page, ref_cta: ref_cta, ref_loc: ref_loc }.reject { |_, v| v.nil? || v.empty? }.to_query.presence
    end

    sig { void }
    def product_interest_as_array
      return if product_interest.nil?

      unless product_interest.is_a?(Array)
        errors.add(:product_interest, "must be an array")
      end
    end
  end
end
