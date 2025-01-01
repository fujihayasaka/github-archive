# typed: true
# frozen_string_literal: true

module ProgrammaticAccessToken
  class Regenerator
    attr_reader :actor_id, :access_id, :options

    def self.perform(actor_id, access_id, opts = {})
      new(actor_id, access_id, opts).perform
    end

    def initialize(actor_id, access_id, opts)
      @actor_id = actor_id
      @access_id = access_id
      @options = opts
    end

    def perform
      destroy_result = Destroyer.perform(actor_id, access_id, options.merge(reason: :regeneration))
      return destroy_result if destroy_result.failed?

      Creator.perform(actor_id, access_id, options)
    end
  end
end
