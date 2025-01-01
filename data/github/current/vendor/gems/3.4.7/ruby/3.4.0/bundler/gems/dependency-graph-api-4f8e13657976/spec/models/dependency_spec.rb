require "rails_helper"

describe Dependency do
  describe "#scope" do
    it "defaults to a runtime dependency" do
      expect(PackageDependency.new.scope)
        .to eq Types::Scope[:runtime]
    end

    it "allows an override" do
      expect(PackageDependency.new(scope: :development).scope)
        .to eq Types::Scope[:development]
    end
  end
end
