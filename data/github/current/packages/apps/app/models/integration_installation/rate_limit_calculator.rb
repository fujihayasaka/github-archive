# typed: true
# frozen_string_literal: true

class IntegrationInstallation
  class RateLimitCalculator
    attr_reader :installation

    ORGANIZATION_MEMBER_COUNT_THRESHOLD     = 20
    ORGANIZATION_MEMBER_RATE_LIMIT_ADDITION = 50

    REPOSITORY_COUNT_THRESHOLD     = 20
    REPOSITORY_RATE_LIMIT_ADDITION = 50

    # Public: Given an installation calculate the appropriate
    # rate limit.
    #
    # installation - The IntegrationInstallation whose rate limit is
    #                being calculated.
    #
    # Returns an Integer.
    def self.calculate(installation)
      new(installation).calculate
    end

    def initialize(installation)
      @installation = installation
    end

    def calculate
      # Always set the base to be the default rate limit.
      new_rate_limit = GitHub.api_default_rate_limit
      # Handle race conditions involving Apps being destroyed during rate limit
      # recalculation.
      return new_rate_limit if @installation.integration.nil?

      if skip_rate_limit_calculation?(@installation.integration)
        return new_rate_limit
      end

      new_rate_limit += organization_rate_limit_addition
      new_rate_limit += repository_rate_limit_addition

      if new_rate_limit == @installation.rate_limit
        @installation.rate_limit
      elsif new_rate_limit > GitHub.api_tier_one_rate_limit
        # This is our cap for now.
        GitHub.api_tier_one_rate_limit
      else
        new_rate_limit
      end
    end

    private

    def skip_rate_limit_calculation?(integration)
      # Global apps only use IntegrationInstallation records for book keeping.
      integration.enabled_global_app? && !Apps::Internal.capable?(:global_app_overrides_rate_limit, app: integration)
    end

    def organization_rate_limit_addition
      return 0 unless @installation.target.is_a?(Organization)

      organization      = @installation.target
      number_of_members = organization.members_count
      return 0 unless number_of_members > ORGANIZATION_MEMBER_COUNT_THRESHOLD

      ((number_of_members - ORGANIZATION_MEMBER_COUNT_THRESHOLD) * ORGANIZATION_MEMBER_RATE_LIMIT_ADDITION)
    end

    def repository_rate_limit_addition
      number_of_repositories = @installation.repositories_count
      return 0 unless number_of_repositories > REPOSITORY_COUNT_THRESHOLD

      ((number_of_repositories - REPOSITORY_COUNT_THRESHOLD) * REPOSITORY_RATE_LIMIT_ADDITION)
    end
  end
end
