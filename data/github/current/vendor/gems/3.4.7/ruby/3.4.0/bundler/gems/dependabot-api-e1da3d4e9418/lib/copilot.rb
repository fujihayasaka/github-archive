# frozen_string_literal: true

require "openssl"
require "time"
require "excon"
require "json"

module Copilot
  class API
    # We can make this configurable later
    DEV_INTEGRATION_ID = "ghas-supply-chain-dev"
    CAPI_URL = "https://api.githubcopilot.com"

    def initialize(hmac_key, github_user)
      @hmac_key = hmac_key
      @github_user = github_user
    end

    def create_completion(prompt:, role: "user", model: "gpt-4")
      headers = generate_headers
      payload = {
        model: model,
        messages: [{ role: role, content: prompt }],
      }.to_json

      response = Excon.post("#{CAPI_URL}/chat/completions", headers: headers, body: payload)
      json_response = JSON.parse(response.body)

      Copilot::Completion.new(json_response)
    end

    private

    def generate_headers
      current = Time.now.to_i.to_s
      hmac = OpenSSL::HMAC.hexdigest("SHA256", @hmac_key, current)
      request_hmac = "#{current}.#{hmac}"

      {
        "Request-Hmac" => request_hmac,
        "Copilot-Integration-Id" => DEV_INTEGRATION_ID,
        "X-GitHub-User" => @github_user,
        "Content-Type" => "application/json",
      }
    end
  end

  class Completion
    attr_reader :choices, :created, :id, :model, :prompt_filter_results, :usage

    def initialize(response)
      @choices = response["choices"]
      @created = response["created"]
      @id = response["id"]
      @model = response["model"]
      @prompt_filter_results = response["prompt_filter_results"]
      @usage = response["usage"]
    end

    def text
      choices.first["message"]["content"]
    end
  end
end

# Usage example:
# api = Copilot::API.new(ENV["CAPI_HMAC_DEV_KEY"], "749864")
# completion = api.create_completion(prompt: "Hi Copilot!")
# puts completion.choices.first["message"]["content"]
