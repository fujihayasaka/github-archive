# frozen_string_literal: true

require "rails_helper"

RSpec.describe GitHub::RESTClient::Retries do
  describe "#using_retries" do
    let(:max_retries) { 4 }
    let(:client) { GitHub::RESTClient.new.using_retries(max: max_retries) }

    let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
    let(:user_url) { github_url + "user" }

    it "adds a new faraday retries middleware" do
      index = client.middleware.handlers.index(Faraday::Retry::Middleware)
      expect(index).not_to be_nil
      middleware = client.middleware.handlers[index].build

      # validate the middleware's default max_retries
      expect(middleware.instance_variable_get(:@options).max).to eq(max_retries)
    end

    [*GitHubHelpers::CONNECTION_FAILURE_ERRORS, Zlib::BufError].each do |error_class|
      it "retries errors by default: #{error_class}" do
        stub_request(:get, user_url).to_raise(error_class.new)

        expect { client.user }.to raise_error(error_class)
        expect(WebMock).to have_requested(:get, user_url).times(max_retries + 1)
      end
    end

    describe "with existing retry middleware" do
      it "updates the client middleware" do
        client.using_retries(max: max_retries + 1)

        handlers = client.middleware.handlers.select { |h| h == Faraday::Retry::Middleware }
        expect(handlers.count).to eq(1)

        middleware = handlers[0].build
        expect(middleware.instance_variable_get(:@options).max).to eq(max_retries + 1)
      end
    end
  end
end
