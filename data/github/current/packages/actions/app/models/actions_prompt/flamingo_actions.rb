# typed: true
# frozen_string_literal: true

module ActionsPrompt
  class FlamingoActions
    include Marketplace::Domain::Provider

    attr_reader :repository

    def initialize(repository)
      @repository = repository
    end

    def allowed_experience?
      return false if GitHub.enterprise?
      return false unless repo_organization
      return false unless repo_organization.plan.business?

      allowed_experience_for_model? && !marketplace_domain.repository_settings.has_ci?(repository)
    end

    private

    def allowed_experience_for_model?
      return false unless repo_info_from_flamingo_api.present?

      repo_info_from_flamingo_api.symbolize_keys[:entity_id].present?
    end

    def repo_organization
      repository&.organization
    end

    def repo_info_from_flamingo_api
      return @repo_info_from_flamingo_api if defined?(@repo_info_from_flamingo_api)

      @repo_info_from_flamingo_api = GitHub.munger.flamingo_adoption_for_repository(repository)
    end
  end
end
