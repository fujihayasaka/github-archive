# typed: true
# frozen_string_literal: true

module Audit
  module Elastic
    class Error < StandardError
      attr_reader :data, :response
      def initialize(res, data = nil)
        @data = data || (GitHub::JSON.decode(res.body) rescue nil)
        @response = res
        super(@data["error"] || "ElasticSearch Error")
      end
    end
  end
end
