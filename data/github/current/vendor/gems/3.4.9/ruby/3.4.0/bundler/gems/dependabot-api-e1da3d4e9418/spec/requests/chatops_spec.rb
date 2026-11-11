# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/_chatops", type: :request do
  describe "GET /_chatops" do
    context "without the CHATOPS_SERVICE envvar set" do
      before do
        ENV.delete("CHATOPS_SERVICE")
        Rails.application.reload_routes!
      end

      it "is not served" do
        get "/_chatops"
        expect(response.status).to eq(404)
      end
    end
  end
end
