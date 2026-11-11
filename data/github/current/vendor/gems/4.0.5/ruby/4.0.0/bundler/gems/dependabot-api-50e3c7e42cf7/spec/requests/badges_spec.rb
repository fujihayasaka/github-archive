# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/badges", type: :request do
  describe "GET /badges/compatibility_score" do
    let(:request_params) do
      {
        "dependency-name" => "pg",
        "package-manager" => "bundler",
        "previous-version" => "0.20.0",
        "new-version" => "0.21.0",
      }
    end

    let(:redis) { Dependabot.redis }

    before { redis.flushdb }

    before do
      Dependabot::Logger.disable
    end

    def with_stubbed_badge_service(enabled:)
      allow(Prius).to receive(:get).with(:enterprise)
      allow(Prius).to receive(:get).with(:actions_deployment)
      allow(Prius).to receive(:get).with(:proxima_stamp)
      allow(Prius).to receive(:get).with(:badge_service).and_return(enabled)
      Rails.application.reload_routes!
      yield
    ensure
      allow(Prius).to receive(:get).with(:badge_service).and_call_original
      Rails.application.reload_routes!
    end

    context "with the BADGE_SERVICE envvar set" do
      context "requesting an svg" do
        it "serves a badgen.net badge" do
          with_stubbed_badge_service(enabled: true) do
            get "/badges/compatibility_score", params: request_params
            expect(response).to have_http_status(:ok)
            expect(response.body).to include("<svg")
            expect(response.body).to include("unknown")
            expect(response.body).to include("#999")
          end
        end
      end

      context "requesting JSON" do
        it "serves the correct JSON" do
          with_stubbed_badge_service(enabled: true) do
            get(
              "/badges/compatibility_score",
              params: request_params,
              headers: { "Accept" => "application/json" }
            )
            expect(response).to have_http_status(:ok)
            expect(JSON.parse(response.body)).to eq(json_fixture("api_responses/badges/compatibility_score"))
          end
        end
      end
    end

    context "without the BADGE_SERVICE envvar set" do
      it "is not served" do
        with_stubbed_badge_service(enabled: false) do
          get "/badges/compatibility_score", params: request_params
          expect(response.status).to eq(404)
        end
      end
    end
  end
end
