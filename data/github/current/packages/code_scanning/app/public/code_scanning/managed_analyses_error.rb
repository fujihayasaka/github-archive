# typed: strict
# frozen_string_literal: true

module CodeScanning
  class ManagedAnalysesError < StandardError
    sig { returns(T.nilable(Twirp::Error)) }
    attr_reader :twirp_error

    sig { params(message: String, twirp_error: T.nilable(Twirp::Error)).void }
    def initialize(message, twirp_error: nil)
      super(message)
      @twirp_error = twirp_error
    end
  end
end
