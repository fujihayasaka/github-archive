# typed: true
# frozen_string_literal: true

# Fake enterprise-web client to return results that make the API client happy
module GitHub
  module EnterpriseWeb
    class FakeServer
      def self.call(env)
        request = Rack::Request.new(env)

        case request.path
        when %r{\A/api/businesses/[^/]+/licenses\z}
          body = { data: [] }.to_json
          [
            200,
            { "Content-Type" => "application/json" },
            [body]
          ]
        when %r{\A/api/businesses/[^/]+/licenses/[^/]+/download\z}
          [
            200,
            { "Content-Type" => "application/x-binary" },
            ["abc123"]
          ]
        else
          [404, {}, ["not found"]]
        end
      end
    end
  end
end
