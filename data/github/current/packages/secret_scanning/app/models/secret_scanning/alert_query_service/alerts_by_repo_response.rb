# typed: strict
# frozen_string_literal: true

module SecretScanning
  class AlertQueryService
    # Simple wrapper so callers can safely call `response.data` like with Twirp responses.
    class AlertsByRepoResponse
      sig { params(data: AlertsByRepoData).void }
      def initialize(data)
        @data = data
      end
      sig { returns(AlertsByRepoData) }
      attr_reader :data
      # Provide #error to mirror Twirp client response (always nil here on success)
      sig { returns(T.untyped) }
      def error; nil; end
    end
  end
end
