require "rails_helper"
require_relative "../../lib/hmac_authentication"

context "HMACAuthentication" do
  let(:app) { lambda { |env| [200, { "Content-Type" => "text/plain" }, ["OK"]] } }

  before do
    ENV["DEPENDENCY_GRAPH_API_HMAC_KEYS"] = "HMAC_SECRET_KEY HMAC_SECRET_KEY_2"
    @validator = HMACAuthentication.new(app)
  end

  it "skips allowed list _ping" do
    res = @validator.call({
      PATH_INFO: "/_ping"
    }.stringify_keys)
    expect(res[0]).to eq 200
    expect(res[2]).to eq ["OK"]
  end

  it "skips allowed list keepalive" do
    res = @validator.call({
      PATH_INFO: "/"
    }.stringify_keys)
    expect(res[0]).to eq 200
    expect(res[2]).to eq ["OK"]
  end

  it "skips allowed chatops command route" do
    res = @validator.call({
      PATH_INFO: "/_chatops/ping"
    }.stringify_keys)
    expect(res[0]).to eq 200
    expect(res[2]).to eq ["OK"]
  end

  it "401-Unauthorized if request hmac is missing" do
    res = @validator.call({
        PATH_INFO: "/query"
      }.stringify_keys)
      expect(res[0]).to eq 401
  end

  it "401-Unauthorized if request hmac is malformed" do
    res = @validator.call({
        PATH_INFO: "/query",
        HTTP_REQUEST_HMAC: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4"
      }.stringify_keys)
      expect(res[0]).to eq 401
  end

  it "401-Unauthorized if request hmac is invalid" do
    timestamp = 5.minutes.ago.to_i.to_s
    hmac = OpenSSL::HMAC.hexdigest(
      "sha256",
      "SOME_OTHER_SECRET_KEY", timestamp
    )
    res = @validator.call({
      PATH_INFO: "/query",
      HTTP_REQUEST_HMAC: "#{timestamp}.#{hmac}"
    }.stringify_keys)
    expect(res[0]).to eq 401
  end

  it "200-OK allows request hmac with clock skew" do
    (0..9).each do |skew|
      timestamp = skew.minutes.ago.to_i.to_s
      hmac = OpenSSL::HMAC.hexdigest(
        "sha256",
        "HMAC_SECRET_KEY", timestamp
      )

      res = @validator.call({
        PATH_INFO: "/query",
        HTTP_REQUEST_HMAC: "#{timestamp}.#{hmac}"
      }.stringify_keys)
      expect(res[0]).to eq 200
      expect(res[2]).to eq ["OK"]
    end
  end

  it "200-OK allows valid request hmac" do
    (0..9).each do |skew|
      timestamp = skew.minutes.ago.to_i.to_s
      hmac = OpenSSL::HMAC.hexdigest(
        "sha256",
        "HMAC_SECRET_KEY", timestamp
      )

      res = @validator.call({
        PATH_INFO: "/query",
        HTTP_REQUEST_HMAC: "#{timestamp}.#{hmac}"
      }.stringify_keys)
      expect(res[0]).to eq 200
      expect(res[2]).to eq ["OK"]
    end
  end

  it "200-OK allows valid request hmac with legacy header" do
    (0..9).each do |skew|
      timestamp = skew.minutes.ago.to_i.to_s
      hmac = OpenSSL::HMAC.hexdigest(
        "sha256",
        "HMAC_SECRET_KEY", timestamp
      )

      res = @validator.call({
        PATH_INFO: "/query",
        HTTP_X_REQUEST_HMAC: "#{timestamp}.#{hmac}"
      }.stringify_keys)
      expect(res[0]).to eq 200
      expect(res[2]).to eq ["OK"]
    end
  end

  it "200-OK supports multiple keys" do
    (0..9).each do |skew|
      timestamp = skew.minutes.ago.to_i.to_s
      hmac = OpenSSL::HMAC.hexdigest(
        "sha256",
        "HMAC_SECRET_KEY_2", timestamp
      )

      res = @validator.call({
        PATH_INFO: "/query",
        HTTP_REQUEST_HMAC: "#{timestamp}.#{hmac}"
      }.stringify_keys)
      expect(res[0]).to eq 200
      expect(res[2]).to eq ["OK"]
    end
  end
end
