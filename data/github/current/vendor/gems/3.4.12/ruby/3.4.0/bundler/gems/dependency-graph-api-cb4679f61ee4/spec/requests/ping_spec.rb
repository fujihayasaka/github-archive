require "rails_helper"

describe "Health check" do
  it "returns a 200" do
    get "/_ping", as: :json

    expect(response).to be_successful
    expect(response_json[:status]).to eq "OK"
  end
end
