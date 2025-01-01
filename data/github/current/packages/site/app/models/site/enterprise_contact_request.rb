# typed: strict
# frozen_string_literal: true

module Site
  class EnterpriseContactRequest < ApplicationRecord::Domain::Site

    enum :status, [:submission_pending, :submitted]
    enum :variant, [:control]

    before_validation :generate_submission_id

    validates :first_name, presence: true
    validates :last_name, presence: true
    validates :company, presence: true
    validates :job_title, presence: true
    validates :email, format: { with: UserEmail::MarketingDependency::EMAIL_PERSONAL_DOMAIN_REGEX }, presence: true
    validates :submission_id, presence: true

    sig { returns(Symbol) }
    def submission_type
      :contact
    end

    sig { returns(String) }
    def cdl_program_name
      GitHub.enterprise_contact_campaign_id
    end

    sig { returns(String) }
    def source
      GitHub.enterprise_contact_source.presence || cdl_program_name
    end

    sig { returns(String) }
    def salesforce_campaign_status
      GitHub.enterprise_contact_status
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
        marketingConsent: marketing_email_opt_in ? "optInExplicit" : nil,
        phone: phone,
        cDLProgramName: cdl_program_name,
        source: source,
        sFDCLastCampaignStatus: salesforce_campaign_status,
        referrer_details: referrer_details,
        utm_campaign: utm_campaign,
        utm_medium: utm_medium,
        utm_source: utm_source,
      }.compact
    end

    sig { void }
    def enqueue_submission_job
      return unless persisted?
      EnterpriseContactRequestSubmissionJob.perform_later(id)
    end

    private

    sig { returns(T.nilable(String)) }
    def email_domain
      return if email.nil?
      T.must(email).split("@").last
    end

    sig { void }
    def generate_submission_id
      self.submission_id = SecureRandom.uuid unless self.submission_id.present?
    end

    sig { returns(T.nilable(String)) }
    def referrer_details
      { ref_page: ref_page, ref_cta: ref_cta, ref_loc: ref_loc }.reject { |_, v| v.nil? || v.empty? }.to_query.presence
    end
  end
end
