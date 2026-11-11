# typed: true
# frozen_string_literal: true

module GitHub
  module TradeCompliance
    module TradeScreening
      class FakeServer
        def call(env)
          request = Rack::Request.new(env)
          case request.path
          when "/token"
            body = { access_token: "test-sdn-token", token_type: "Bearer", expires_in: 3600 }
            [200, { "Content-Type" => "application/json" }, [GitHub::JSON.encode(body)]]
          else
            [404, {}, ["This endpoint is either incorrect or hasn't been stubbed"]]
          end
        end
      end
    end
  end
end
