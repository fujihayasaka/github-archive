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

      destroy_result = Destroyer.perform(access, :regeneration)
      return destroy_result if destroy_result.failed?

      create_result = Creator.perform(access, options)
      access.notify_owner(about: :regenerated) if create_result.success?

      create_result
    end
  end
end
