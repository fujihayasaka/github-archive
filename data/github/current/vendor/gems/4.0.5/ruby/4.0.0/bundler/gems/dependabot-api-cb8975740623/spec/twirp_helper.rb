# frozen_string_literal: true

require "rails_helper"

RSpec.shared_context "twirp request helpers" do
  let(:hmac_token) do
    Middleware::HmacAuthentication.request_hmac(
      key: "dotcomhmac",
      time: Time.zone.now
    )
  end

  let(:twirp_headers) do
    {
      "HTTP_REQUEST_HMAC" => hmac_token,
      "CONTENT_TYPE" => "application/protobuf",
    }
  end

  # Helper to hydrate a Twirp RPC shorthand into an rspec `post` command
  def rpc_call(method:, params: nil, headers: twirp_headers)
    rpc_def = described_class.rpcs.fetch(method, "")

    # If we have a hash and there is an rpc definition for this method,
    # we should encode the content.
    if params.is_a?(Hash) && rpc_def.present?
      params = rpc_def[:input_class].encode(
        rpc_def[:input_class].new(params)
      )
    end

    post path_for(method), headers: headers, params: params
  end

  def path_for(method)
    "/twirp/" + described_class.service_full_name + "/" + method
  end
end

RSpec.configure do |config|
  config.include_context "twirp request helpers"
end
