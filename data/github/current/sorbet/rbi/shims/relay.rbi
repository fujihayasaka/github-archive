# typed: true

module GitHub
  module Relay
    module GlobalIdentification
      sig { returns(Integer) }
      def id; end

      sig { returns(T.nilable(Integer)) }
      def pull_request_id; end
    end
  end
end
