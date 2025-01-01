# typed: true
# frozen_string_literal: true

module ProgrammaticAccessToken
  class Regenerator
    attr_reader :access, :options

    def self.perform(access, opts = {})
      new(access, opts).perform
    end

    def initialize(access, opts = {})
      @access = access
      @options = opts
    end

    def perform
      return Result.failed("PAT is required") unless access.present?
      if invalid_expiration_date_for_target?
        grant = access.grant || access.grant_request
        grant_target = grant&.target
        policy_config = ProgrammaticAccessTokenLifetimeConfiguration.new(grant_target, grant.user_programmatic_access.pat_type)

        return Result.failed("expiration is above the limit set by #{policy_config.target_and_type_with_limit}")
      end

      destroy_result = Destroyer.perform(access, :regeneration)
      return destroy_result if destroy_result.failed?

      create_result = Creator.perform(access, options)
      access.notify_owner(about: :regenerated) if create_result.success?

      create_result
    end

    private

    def invalid_expiration_date_for_target?
      return false unless access.owner.feature_enabled?(:fg_pat_expiration_lifecycle_enforcement)
      return false unless access.targeting_organizations?

      grant = access.grant || access.grant_request
      return false unless grant&.target&.personal_access_token_expiration_limit_enabled?
      limit = grant.target_expiration_limit
      return false unless limit

      access.pat_lifetime_in_days > limit
    end
  end
end
