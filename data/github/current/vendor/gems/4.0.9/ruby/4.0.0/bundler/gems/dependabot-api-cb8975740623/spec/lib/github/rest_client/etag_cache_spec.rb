# frozen_string_literal: true

require "rails_helper"

RSpec.describe GitHub::RESTClient::EtagCache do
  let(:client) { GitHub::RESTClient.new.using_etag_cache }

  it "is not included in clients that do not call using_etag_cache" do
    expect(GitHub::RESTClient.new.middleware.handlers).not_to include(Faraday::EtagCache)
  end

  describe "#using_etag_cache" do
    it "adds etag cache middleware to the client" do
      expect(client.middleware.handlers).to include(Faraday::EtagCache)
    end

    it "does not add duplicate etag cache middleware" do
      client.using_etag_cache
      expect(client.middleware.handlers.count { |h| h.name == Faraday::EtagCache.to_s }).to eq(1)
    end
  end
end
