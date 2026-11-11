require "rails_helper"

describe "an invalid graphql query" do
  it "returns an error" do
    post "/query"

    expect(response).to_not be_successful
    expect(response_json[:error]).to eq "'query' is required."
  end
end
