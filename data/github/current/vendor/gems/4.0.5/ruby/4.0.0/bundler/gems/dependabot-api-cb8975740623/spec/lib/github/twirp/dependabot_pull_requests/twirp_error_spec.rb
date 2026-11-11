# frozen_string_literal: true

require "rails_helper"
require "github_helpers"

RSpec.describe GitHub::Twirp::DependabotPullRequests::TwirpError do
  let(:twirp_err) { Twirp::Error.not_found("error") }
  let(:err) { described_class.new("test", twirp_err) }

  describe "#message" do
    it "is the outer error's message" do
      expect(err.message).to eq("test")
    end
  end

  describe "#error" do
    it "is the inner Twirp error" do
      expect(err.error).to eq(twirp_err)
    end
  end

  describe "#details" do
    it "is the inner Twirp error's message" do
      expect(err.details).to eq("error")
    end
  end

  describe "#code" do
    it "is the inner Twirp error's code" do
      expect(err.code).to eq(:not_found)
    end
  end

  describe "#meta" do
    let(:twirp_err) { Twirp::Error.invalid_argument("error", field: "repository_id") }

    it "is the inner Twirp error's meta field" do
      expect(err.meta).to eq({ field: "repository_id" })
    end
  end

  describe "#http_status_code" do
    it "is the corresponding http status code for the Twirp error" do
      expect(err.http_status_code).to be(Twirp::ERROR_CODES_TO_HTTP_STATUS[err.code])
    end
  end

  describe ".for_error" do
    Twirp::ERROR_CODES.each do |code|
      http_status_code = Twirp::ERROR_CODES_TO_HTTP_STATUS[code]
      describe "with Twirp error code #{code}" do
        let(:twirp_error) { Twirp::Error.send(code, "error") }

        let(:error_class) do
          if http_status_code >= 500
            GitHub::Twirp::DependabotPullRequests::TransientTwirpError
          else
            described_class
          end
        end

        it "raises the expected error class" do
          expect(described_class.for_error("test", twirp_error)).to be_a(error_class)
        end
      end
    end
  end
end
