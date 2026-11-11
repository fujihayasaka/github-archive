# typed: true
# frozen_string_literal: true

require "uri"
require "net/http"

module Copilot
  # This class makes requests to copilot-proxy for experimental autocompletion in the monolith.
  # For more information, reach out in #copilot-workspace-components.
  class Completions
    include T::Sig

    class Model < T::Enum
      enums do
        GPT35Turbo = new("github-completion")
        GPT4oMini = new("copilot-ppe-centralus-4o-mini")
      end
    end

    sig { params(body: String, auth_token: String, user_agent: String, domain: String, engine: Model).returns(String) }
    def self.prompt_code_completion(body:, auth_token:, user_agent:, domain: "https://copilot-proxy.githubusercontent.com", engine: Model::GPT35Turbo)
      url = URI(code_completion_url(domain, engine: engine))
      https = Net::HTTP.new(url.host, url.port)
      https.read_timeout = 10
      https.use_ssl = true
      request = Net::HTTP::Post.new(url)
      request["Authorization"] = "Bearer #{auth_token}"
      request["Content-Type"] = "application/json"
      request["User-Agent"] = user_agent

      request.body = body

      response = https.request(request)
      response.read_body
    end

    sig { params(domain: String, engine: Model).returns(String) }
    def self.code_completion_url(domain, engine:)
      domain + "/v1/engines/#{engine.serialize}/completions"
    end
  end
end
