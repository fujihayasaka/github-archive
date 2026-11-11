# typed: strict
# frozen_string_literal: true

module MarketingForms
  class Submission
    include ActiveModel::Validations

    validates :email, presence: { message: "Valid email key is missing. Valid keys are: email, email_address, emailAddress" }
    validates :cdl_program_name, presence: true
    validate :marketing_consent_missing_or_valid

    sig { params(form_name: String, raw_data: T::Hash[Symbol, T.untyped]).returns(Submission) }
    def self.enqueue!(form_name:, raw_data:)
      new(form_name: form_name, raw_data: raw_data).tap do |s|
        s.enqueue!
      end
    end

    sig { params(form_name: String, raw_data: T::Hash[Symbol, T.untyped]).void }
    def initialize(form_name:, raw_data:)
      @form_name = form_name
      @raw_data = raw_data
    end

    sig { returns(T::Boolean) }
    def enqueue!
      validate!
      enqueue
    end

    sig { returns(T::Boolean) }
    def enqueue
      if valid?
        MarketingFormsSubmissionJob.perform_later(form_name: @form_name, raw_data: @raw_data)
        true
      else
        false
      end
    end

    private

    sig { returns(T.nilable(String)) }
    def email
      @raw_data[:email] || @raw_data[:email_address] || @raw_data[:emailAddress]
    end

    sig { returns(T.nilable(String)) }
    def cdl_program_name
      @raw_data[:cDLProgramName]
    end

    sig { void }
    def marketing_consent_missing_or_valid
      # It's okay if marketingConsent is missing, but if it's present, it must be "optInExplicit". Sending a `nil`
      # value to the API will cause an error.
      return unless @raw_data.keys.include?(:marketingConsent)

      if @raw_data[:marketingConsent] != "optInExplicit"
        errors.add(:marketingConsent, "Invalid marketingConsent value. Must be 'optInExplicit' or excluded from the raw_data.")
      end
    end
  end
end
