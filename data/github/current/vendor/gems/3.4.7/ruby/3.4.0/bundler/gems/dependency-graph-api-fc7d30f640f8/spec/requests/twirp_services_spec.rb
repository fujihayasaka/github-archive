require "rails_helper"

describe Services do
  it "returns successfully for a simple request" do
    post "/twirp/health/DependencyGraphAPI.v1.HealthAPI/Ping", as: :json
    expect(response.status).to equal(200)
  end
end
