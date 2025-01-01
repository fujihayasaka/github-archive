# typed: strict
# frozen_string_literal: true

module EnterpriseCloudOnboard
  class GhasTrialEligibility
    extend T::Sig

    sig { returns(Organization) }
    attr_reader :organization

    ELIGIBLE_LANGUAGES = T.let(%w(
      JavaScript
      Python
      Ruby
      TypeScript
    ), T::Array[String])

    sig { params(organization: Organization).void }
    def initialize(organization)
      @organization = T.let(organization, Organization)
    end


    sig { returns(String) }
    def set_value
      return "Invalid number of seats" unless eligible_seats?

      repository_ids = organization.repositories.pluck(:id)
      actions_enabled = Actions::WorkflowRun.limit_execution_time.where(repository_id: repository_ids).exists?
      return "Actions not enabled" unless actions_enabled

      contributions = CommitContribution.where(repository_id: repository_ids, created_at: 90.days.ago..Time.current).exists?
      return "Could not find contributions" unless contributions

      languages = LanguageName.where(name: ELIGIBLE_LANGUAGES)
      GitHub.logger.info("languages for GHAS Trial eligibility",
        "gh.org.login": organization.login,
        "gh.ghas_trial_eligibility.languages": languages.pluck(:name).join(", "),
        "code.namespace": "EnterpriseCloudOnboard::GhasTrialEligibility",
        "code.function": "set_value"
      )

      language_name_ids = languages.pluck(:id)
      eligible_language = Language.where(repository_id: repository_ids, language_name_id: language_name_ids).exists?
      return "Could not find eligible language" unless eligible_language
      return "Enterprise Managed User is enabled for this org" if organization.enterprise_managed_user_enabled?

      organization.enable_advanced_security_eligiblity_for_entity(actor: User.ghost)

      GlobalInstrumenter.instrument("analytics.event",
        category: "ghas_trial_eligibility",
        action: "is_ghas_trial_eligible",
        label: organization.id.to_s,
      )
      "Success"
    end

    sig { returns(String) }
    def enterprise_eligibility_criteria
      return "Invalid number of seats" if organization.seats < 20 || organization.seats > 1250
      return "Outside of renewal window" unless valid_renewal_window?
      return "Not enough eligible languages in the past 6 months" unless recent_languages_eligible?

      organization.enable_advanced_security_eligiblity_for_entity(actor: User.ghost)

      GlobalInstrumenter.instrument("analytics.event",
        category: "ghas_trial_eligibility",
        action: "is_ghas_trial_eligible",
        label: organization.id.to_s,
      )
      "Success"
    end


    sig { returns(String) }
    def remove_eligibility
      result = organization.disable_advanced_security_eligibility_for_entity(actor: User.ghost)
      result ? "Success" : "Failed"
    end

    private

    sig { returns(T::Boolean) }
    def valid_renewal_window?
      return false unless business = organization.business
      T.must(business.billed_on) < 6.months.from_now
    end

    sig { returns(T::Boolean) }
    def recent_languages_eligible?
      language_name_ids = LanguageName.where(name: ELIGIBLE_LANGUAGES).pluck(:id)
      total_repos_count = organization.repositories.count
      active_repos = organization.repositories.where(updated_at: 6.months.ago..Time.current, active: true)
      eligible_repos_count = active_repos.where(primary_language_name_id: language_name_ids).count

      (total_repos_count * 100 / 4) <= eligible_repos_count * 100
    end

    sig { returns(T::Boolean) }
    def eligible_seats?
      return organization.seats >= 10 && organization.seats <= 1250 if organization.plan.business_plus?
      false
    end
  end
end
