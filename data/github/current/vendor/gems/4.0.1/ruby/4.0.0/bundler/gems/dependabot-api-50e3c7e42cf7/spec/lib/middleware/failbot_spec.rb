# frozen_string_literal: true

require "rails_helper"
require "rack/test"
require "middleware/failbot"

RSpec.describe Middleware::Failbot do
  include Rack::Test::Methods

  def app
    Rack::Builder.new.tap do |b|
      b.use described_class, app: "test"
      b.run endpoint
    end
  end

  def last_report
    Failbot.backend.reports.last
  end

  let(:endpoint) do
    ->(_env) { [200, { "Content-Type" => "text/plain" }, ["OK"]] }
  end

  before do
    Failbot.reset!
    Failbot.setup(
      { "FAILBOT_BACKEND" => "memory" }, { "shared" => "Default Context" }
    )
  end

  it "passes through on success" do
    get "/"
    expect(last_response).to be_ok
  end

  context "raising an error" do
    let(:error) { ArgumentError.new }
    let(:endpoint) { ->(_env) { raise error } }

    it "reports the error" do
      expect { get "/" }.to raise_error(error)
      expect(last_report["exception_detail"].last["type"]).to eq(error.class.to_s)
    end

    it "pushes context" do
      expect { get "/" }.to raise_error(error)
      expect(last_report["app"]).to eq("test")
    end

    it "resets context before each request" do
      Dependabot::Exceptions.push "rpc.method": "bar"
      expect { get "/" }.to raise_error(error)
      expect(last_report).not_to be_key("rpc.method")
      # validate "rpc.method" is not getting renamed which would invalidate the previous test
      expect(Dependabot::Sentry::INDEXED_TELEMETRY_KEYS.include?(:"rpc.method")).to eq(false)
    end

    it "pushes request context" do
      expect { get "/foo" }.to raise_error(error)
      expect(last_report["method"]).to eq("GET")
      expect(last_report["url"]).to eq("http://example.org/foo")
    end

    it "reports time" do
      expect { get "/foo" }.to raise_error(error)
      expect(last_report["http.server.request.duration"]).to be_truthy
    end
  end

  context "raising with a transaction context" do
    let(:error) { ArgumentError.new }
    let(:transaction) { "RouteClass" }
    let(:rollup) do
      Digest::MD5.hexdigest("#{error.class}#{transaction}")
    end
    let(:endpoint) do
      lambda do |_env|
        Dependabot::Exceptions.push(transaction: transaction)
        raise error
      end
    end

    it "raises with transaction" do
      expect { get "/" }.to raise_error(error)
      expect(last_report["transaction"]).to eq(transaction)
      expect(last_report["rollup"]).to eq(rollup)
    end
  end

  context "with an existing rollup context" do
    let(:error) { ArgumentError }
    let(:transaction) { "MiddlewareThingy" }
    let(:rollup) { "4124bc0a9335c27f086f24ba207a4912" }
    let(:endpoint) do
      lambda do |_env|
        Dependabot::Exceptions.push(transaction: transaction, rollup: rollup)
        raise error
      end
    end

    it "raises with original rollup" do
      expect { get "/" }.to raise_error(error)
      expect(last_report["transaction"]).to eq(transaction)
      expect(last_report["rollup"]).to eq(rollup)
    end
  end
end
