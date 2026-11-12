require_relative "../response"

module BlobOperations
  module Responses
    class Ping < BlobOperations::Response
      def message
        data&.message
      end
    end
  end
end
