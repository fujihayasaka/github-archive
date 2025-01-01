# typed: true
# frozen_string_literal: true

class Organization
  class TermsOfService
    include Instrumentation::Model

    attr_reader :organization

    CORPORATE = "Corporate"
    CUSTOM = "Custom"

    TERMS_OF_SERVICE_TYPES = ["Standard", CUSTOM, CORPORATE, "Evaluation", "ESA+Education"]
    BUSINESS_TERMS_OF_SERVICE_TYPES = %w[Corporate Evaluation]
    CORPORATE_UPGRADE_BANNER_NAME = "org_corporate_tos_banner"
    ESA_EDUCATION_UPGRADE_BANNER_NAME = "org_esa_education_tos_banner"

    def initialize(organization:)
      @organization = organization
    end

    # Public: The name of the terms of service that was accepted.
    #
    # Returns a String.
    def name
      async_name.sync
    end

    # Public: The name of the terms of service that was accepted.
    #
    # Returns a Promise<String>.
    def async_name
      organization.async_terms_of_service_acceptance.then do |acceptance|
        if acceptance
          Organization::TermsOfServiceAcceptance.accepted_terms_types[acceptance.accepted_terms_type]
        else
          "Standard"
        end
      end
    end

    # Public: Is this organization under the Standard terms of service?
    #
    # Returns a Boolean.
    def standard?
      name == "Standard"
    end

    # Public: Is this organization under the Custom terms of service?
    #
    # Returns a Boolean.
    def custom?
      name == "Custom"
    end

    # Public: Is this organization under the Corporate terms of service?
    #
    # Returns Boolean.
    def corporate?
      name == "Corporate"
    end

    # Public: Is this organization under the Evaluation terms of service?
    #
    # Returns Boolean.
    def evaluation?
      name == "Evaluation"
    end

    # Public: Is this organization under the Evaluation terms of service?
    #
    # Returns Boolean.
    def esa_education?
      name == "ESA+Education"
    end

    # Public: Is this organization under the Evaluation or Corporate terms of service?
    #
    # Returns Boolean.
    def business_terms_of_service?
      BUSINESS_TERMS_OF_SERVICE_TYPES.include?(name)
    end

    # Public: Has the corporate ToS upgrade prompt been enabled by a staff user?
    #
    # Returns a Boolean.
    def corporate_upgrade_prompt_enabled?
      corporate_upgrade_prompt_enabled_at.present?
    end

    # Public: The time that the prompt to change to the Corporate ToS was enabled
    #         by staff, if it ever has been.
    #
    # Returns a String | nil.
    def corporate_upgrade_prompt_enabled_at
      if prompt = organization.terms_of_service_corporate_upgrade_prompt
        prompt.updated_at.to_s
      end
    end

    # Public: Enable the corporate ToS upgrade banner for all owners for this
    #         organization.
    #
    # Returns a Boolean.
    def enable_corporate_upgrade_prompt
      organization.admins.each do |admin|
        admin.reset_notice(CORPORATE_UPGRADE_BANNER_NAME)
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        Organization::TermsOfServiceUpgradePrompt.create_or_find_by!(
          organization: organization,
          upgraded_terms_type: :corporate
        ).touch
      end

      organization.reset_terms_of_service_corporate_upgrade_prompt

      true
    end

    # Public: Has the ESA+Education ToS upgrade prompt been enabled by a staff user?
    #
    # Returns a Boolean.
    def esa_education_upgrade_prompt_enabled?
      esa_education_upgrade_prompt_enabled_at.present?
    end

    # Public: The time that the prompt to change to the ESA+education ToS was enabled
    #         by staff, if it ever has been.
    #
    # Returns a String | nil.
    def esa_education_upgrade_prompt_enabled_at
      if prompt = organization.terms_of_service_esa_education_upgrade_prompt
        prompt.updated_at.to_s
      end
    end

    # Public: Enable the ESA+education ToS upgrade banner for all owners for this
    #         organization.
    #
    # Returns true
    def enable_esa_education_upgrade_prompt
      organization.admins.each do |admin|
        admin.reset_notice(ESA_EDUCATION_UPGRADE_BANNER_NAME)
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        Organization::TermsOfServiceUpgradePrompt.create_or_find_by!(
          organization: organization,
          upgraded_terms_type: :esa_education
        ).touch
      end

      organization.reset_terms_of_service_esa_education_upgrade_prompt

      true
    end

    # Public: Update the terms of service for an organization.
    #
    # type - The String terms of service type, from `TERMS_OF_SERVICE_TYPES`.
    # actor - The User updating the terms of service for this organization.
    # company_name - The name of the company that the terms of service is
    #                accepted on behalf of.
    # staff_actor - A Boolean indicating if a staff user is updating the terms
    #               of service for this account.
    # change_note - A String note explaining why the terms of service is being
    #               updated. Required if `staff_actor` is `true`.
    #
    # Returns a Boolean.
    def update(type:, actor:, company_name: nil, staff_actor: false, change_note: nil, removed_from_business: false)
      return false if organization.id.nil?
      return false unless TERMS_OF_SERVICE_TYPES.include?(type)
      # Changes made by staff are required to have a change note.
      return false if staff_actor && change_note.blank?

      if organization.archived?
        organization.errors.add(:base, "This organization cannot change terms of service because it is archived.")
        return false
      end

      audit_context = organization.event_context
      existing_company = organization.company.try(:name)
      existing_terms = name
      company_changed = !company_name.nil? && (company_name != existing_company)
      terms_changed = type != existing_terms

      # Update the terms of service value for this organization,
      # if it changed.

      if terms_changed
        organization.unlink_billing_contact(actor: actor)
        organization.reset_billing_memoized_attributes

        set_terms!(type)

        terms_context = {
          terms_of_service_type: {
            old_value: existing_terms,
            new_value: type,
          },
        }

        if standard? || removed_from_business
          company_name = nil
          company_changed = true
        end

        audit_context = audit_context.merge(terms_context)
      end

      # Return true if there are no actual changes.
      return true unless company_changed || terms_changed

      if company_changed
        return false unless organization.update(company_name: company_name)

        # If the company name is blank, remove all companies for this
        # organization.
        organization.companies.delete_all if company_name.blank?

        company_context = {
          company_name: {
            old_value: existing_company,
            new_value: company_name,
          },
        }
        audit_context = audit_context.merge(company_context)
      end

      if staff_actor
        guarded_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
        staff_context = {
          prefix: "staff",
          terms_of_service_change_reason: change_note,
        }.merge(guarded_actor)

        audit_context = audit_context.merge(staff_context)
      else
        audit_context = audit_context.merge({ prefix: "org", actor: actor })
      end

      instrument :update_terms_of_service, audit_context

      true
    end

    private

    # Private: Set the stored terms of service value for this organization.
    #
    # value – A String terms of service name, from `TERMS_OF_SERVICE_TYPES`.
    #
    # Returns nothing.
    def set_terms!(value)
      raise ArgumentError, "Invalid terms of service type" unless TERMS_OF_SERVICE_TYPES.include?(value)
      ActiveRecord::Base.connected_to(role: :writing) do
        Organization::TermsOfServiceAcceptance.create_or_find_by!(organization: organization) do |terms|
          terms.accepted_terms_type = value
        end.update!(accepted_terms_type: value)
      end
      organization.reset_terms_of_service_acceptance
    end
  end
end
