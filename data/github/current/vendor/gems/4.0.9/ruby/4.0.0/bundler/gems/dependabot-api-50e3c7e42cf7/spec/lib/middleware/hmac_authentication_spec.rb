# frozen_string_literal: true

require "rails_helper"
require "middleware/hmac_authentication"

RSpec.describe Middleware::HmacAuthentication do
  subject(:authenticated_app) do
    described_class.new(app, skip_paths: skip_paths)
  end

  let(:app) { ->(_env) { [200, { "Content-Type" => "text/plain" }, ["OK"]] } }
  let(:skip_paths) { [%r{^/foo}, "/bar/baz"] }
  let(:mock_hmac_keys) { "HMAC_SECRET_KEY_1 HMAC_SECRET_KEY_2" }

  def get(path, token: nil)
    authenticated_app.call(
      "PATH_INFO" => path,
      "HTTP_REQUEST_HMAC" => token,
    )
  end

  def make_token(secret:, time: Time.zone.now)
    timestamp = time.to_i.to_s
    hmac = OpenSSL::HMAC.hexdigest(
      "sha256",
      secret,
      timestamp,
    )
    "#{timestamp}.#{hmac}"
  end

  before do
    allow(Prius).to receive(:get).
      with(:dependabot_api_hmac_keys).
      and_return(mock_hmac_keys)
  end

  it "401s by default" do
    response = get("/hello_world")

    expect(response[0]).to eq 401
  end

  it "401s with a malformed token" do
    response = get("/hello_world", token: "randomnonesense")

    expect(response[0]).to eq 401
  end

  it "200s with a valid request token" do
    token = make_token(secret: "HMAC_SECRET_KEY_1")
    response = get("/hello_world", token: token)

    expect(response[0]).to eq 200
    expect(response[2]).to eq ["OK"]
  end

  it "200s with a an alternative request token" do
    token = make_token(secret: "HMAC_SECRET_KEY_2")
    response = get("/hello_world", token: token)

    expect(response[0]).to eq 200
    expect(response[2]).to eq ["OK"]
  end

  it "401s with an invalid request token" do
    token = make_token(secret: "NO_SUCH_KEY")
    response = get("/hello_world", token: token)

    expect(response[0]).to eq 401
  end

  context "clock skew" do
    10.times do |skew|
      it "permits #{skew} minutes in the past" do
        time = skew.minutes.ago
        token = make_token(secret: "HMAC_SECRET_KEY_1", time: time)
        response = get("/hello_world", token: token)

        expect(response[0]).to eq 200
        expect(response[2]).to eq ["OK"]
      end

      it "permits #{skew} minutes in the future" do
        time = skew.minutes.from_now
        token = make_token(secret: "HMAC_SECRET_KEY_1", time: time)
        response = get("/hello_world", token: token)

        expect(response[0]).to eq 200
        expect(response[2]).to eq ["OK"]
      end
    end

    it "disallows 11 minutes in the past" do
      time = 11.minutes.ago
      token = make_token(secret: "HMAC_SECRET_KEY_1", time: time)
      response = get("/hello_world", token: token)

      expect(response[0]).to eq 401
    end

    it "disallows 11 minutes in the future" do
      time = 11.minutes.from_now
      token = make_token(secret: "HMAC_SECRET_KEY_1", time: time)
      response = get("/hello_world", token: token)

      expect(response[0]).to eq 401
    end
  end

  context "skipping paths" do
    describe "skipping paths by regex" do
      [
        "/foo/bar",
        "/foo/baz",
        "/foo/bar/qux",
      ].each do |request_path|
        it "permits #{request_path} without a token" do
          response = get(request_path)

          expect(response[0]).to eq 200
          expect(response[2]).to eq ["OK"]
        end
      end

      it "does not permit /bar/foo/ without a token" do
        response = get("/bar/foo")

        expect(response[0]).to eq 401
      end
    end

    describe "skipping exact paths" do
      it "permits /bar/baz without a token" do
        response = get("/bar/baz")

        expect(response[0]).to eq 200
        expect(response[2]).to eq ["OK"]
      end

      it "does not permit /bar/baz/qux without a token" do
        response = get("/bar/baz/qux")

        expect(response[0]).to eq 401
      end
    end
  end
end
