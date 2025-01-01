require "spec_helper"

RSpec.describe Blackbird do
  it "has a version number" do
    expect(Blackbird::VERSION).not_to be nil
  end

  it "can create an admin client" do
    rpc = Blackbird::Admin::V1::AdminAPIClient.new("http://localhost:8003/twirp")
    expect(rpc).not_to be nil
  end

  it "can create a query client" do
    rpc = Blackbird::Query::V1::QueryAPIClient.new("http://localhost:8003/twirp")
    expect(rpc).not_to be nil
  end

  it "handles hydro symbol kinds" do
    s = Blackbird::Query::V1::Symbol.new
    expect(s.kind).to be :SYMBOL_KIND_UNKNOWN
  end
end
