# typed: true
# frozen_string_literal: true

module CodeScanning
  class AutoCodeqlError < StandardError
    attr_accessor :twirp_error
    attr_accessor :repo_id
    attr_accessor :reason

    def initialize(message, repo_id: nil, twirp_error: nil, reason: nil)
      super(message)
      self.repo_id = repo_id
      self.twirp_error = twirp_error
      self.reason = reason
    end
  end
end
