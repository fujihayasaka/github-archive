require "rails_helper"
require "rspec"
require "faraday"
require_relative "../../../lib/faraday_middleware/hmac_auth"
require_relative "../../../lib/hmac_authentication"

describe HMACAuthentication do
  before do
    @key = "HMAC_SECRET_KEY"
  end

  it "sets hmac header" do
    todays_date = Date.parse("2018-08-13")
    Timecop.freeze(todays_date) do
      timestamp = Time.now.to_i.to_s
      hmac = OpenSSL::HMAC.hexdigest("sha256", @key, timestamp)

      res = stub_http(expected_hmac: "#{timestamp}.#{hmac}").get "test"

      expect(res.status).to eq(200)
      expect(res.body).to eq("OK")
    end
  end
end

def stub_http(expected_hmac:)

  Faraday.new("http://localhost:8080/twirp") do |b|
    b.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: @key
    b.adapter :test do |stub|
      headers = { "User-Agent" => "Faraday v#{Faraday::VERSION}", "Request-HMAC" => expected_hmac }
      stub.get("/twirp/test", headers) do
        [200, { "Content-Type" => "text/plain" }, "OK"]
      end
    end
  end
end
