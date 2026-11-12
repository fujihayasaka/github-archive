# frozen_string_literal: true

require "rails_helper"
require "middleware/bad_request"

RSpec.describe Middleware::BadRequest do
  subject(:response) { described_class.new(app).call({}) }

  let(:app) { ->(_env) { [200, { "Content-Type" => "text/plain" }, ["OK"]] } }

  it "passes through success" do
    expect(response[0]).to eq 200
  end

  context "with error" do
    let(:error) { ArgumentError }
    let(:app) { ->(_env) { raise error } }

    it "raises" do
      expect { response }.to raise_error(ArgumentError)
    end

    context "ActionController::UnknownHttpMethod" do
      let(:error) { ActionController::UnknownHttpMethod }

      it "rescues" do
        expect(response[0]).to eq 400
      end
    end

    context "ActionController::BadRequest" do
      let(:error) { ActionController::BadRequest }

      it "raises" do
        expect { response }.to raise_error(ActionController::BadRequest)
      end
    end

    context "ActionController::BadRequest path encoding" do
      msg = "Invalid path parameters: Invalid encoding for parameter: �"
      let(:error) { ActionController::BadRequest.new(msg) }

      it "rescues" do
        expect(response[0]).to eq 400
      end
    end

    context "ActionController::BadRequest query encoding" do
      msg = "Invalid query parameters: invalid %-encoding (/cgi-bin/.%%32%65/.%%32%65/.%%32%65/.%%32%65/" \
            ".%%32%65/.%%32%65/.%%32%65/etc/passwd)"
      let(:error) { ActionController::BadRequest.new(msg) }

      it "rescues" do
        expect(response[0]).to eq 400
      end
    end

    context "ActionDispatch::Http::MimeNegotiation::InvalidType" do
      let(:error) { ActionDispatch::Http::MimeNegotiation::InvalidType }

      it "rescues" do
        expect(response[0]).to eq 400
      end
    end
  end
end
