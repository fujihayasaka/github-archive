# Class used to simulate an HTTP connection for testing purposes.
require 'uri'
require 'net/http'

module Tools
  class HttpClient

    def get(path, params = {}, headers = {})
      uri = URI(path)
      uri.query = URI.encode_www_form(params) unless AdvisoryDBToolkit::Utility.blank?(params)
      res = Net::HTTP.get_response(uri, headers)
      Response.new(res)
    end

    class Response
      def initialize(response)
        @response = response
      end

      def body
        @body ||= @response.body
      end

      def status
        @status ||= @response.code.to_i
      end

      def env
        OpenStruct.new(:url => "#{@response.uri.origin}#{@response.uri.path}")
      end
    end
  end
end
