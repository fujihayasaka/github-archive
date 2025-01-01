# typed: true
# frozen_string_literal: true

module ProgrammaticAccessToken
  # TODO: this class is just a placeholder for Finder & Credential
  class ExpirationReader
    CATALOG_SERVICE = "github/apps"

    attr_reader :access

    def self.perform(access)
      new(access).perform
    end

    def initialize(access, opts = {})
      @access = access
    end

    def perform
      return Result.failed("PAT is required") unless access.present?

      found_credentials_result = Finder.perform(access)
      return found_credentials_result unless found_credentials_result.success?

      credentials = found_credentials_result.value
      return Result.success(:expired) if credentials.blank?

      expirations = credentials.map &:expires_at
      return Result.success(nil) if expirations.include?(nil)

      Result.success(expirations.sort.last)
    end

  end
end
