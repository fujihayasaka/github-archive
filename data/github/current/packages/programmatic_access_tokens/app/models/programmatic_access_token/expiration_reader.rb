# typed: true
# frozen_string_literal: true

module ProgrammaticAccessToken
  # TODO: this class is just a placeholder for Finder & Credential
  class ExpirationReader
    CATALOG_SERVICE = "github/apps"

    attr_reader :access

    def self.perform(actor_id, access_id, opts = {})
      new(actor_id, access_id, opts).perform
    end

    def initialize(actor_id, access_id, opts)
      @actor_id = actor_id
      @access_id = access_id
      @opts = opts
    end

    def perform
      found_credentials_result = Finder.perform(@actor_id, @access_id, @opts)
      return found_credentials_result unless found_credentials_result.success?

      credentials = found_credentials_result.value
      return Result.success(:expired) if credentials.blank?

      expirations = credentials.map &:expires_at
      return Result.success(nil) if expirations.include?(nil)

      Result.success(expirations.sort.last)
    end

  end
end
