require "rails_helper"

describe Types::Manifest do
  describe "#supersedes?" do
    let(:gemfile)           { Types::Manifest[:gemfile] }
    let(:gemfile_lock)      { Types::Manifest[:gemfile_lock] }
    let(:package_json)      { Types::Manifest[:package_json] }
    let(:package_lock_json) { Types::Manifest[:package_lock_json] }

    it "is true when a manifest type takes precedence" do
      expect(gemfile_lock.supersedes?(gemfile)).to be_truthy
      expect(package_lock_json.supersedes?(package_json)).to be_truthy
    end

    it "is false when a manifest type does not take precedence" do
      expect(gemfile.supersedes?(gemfile_lock)).to be_falsey
      expect(package_json.supersedes?(package_lock_json)).to be_falsey
    end
  end
end

describe Types::PackageManager do
  describe "to_proto" do
    it "converts package managers to expected types" do
      expect(Types::PackageManager[:npm].to_proto).to eq(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_NPM)
    end

    it "supports all understood formats of package manager" do
      Types::PackageManager.each do |type|
        if type.to_sym == :unknown
          expect(Types::PackageManager[type.to_sym].to_proto).to eq(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_UNKNOWN)
        else
          expect(Types::PackageManager[type.to_sym].to_proto).not_to eq(DependencyGraphAPI::V1::PackageManager::PACKAGE_MANAGER_UNKNOWN)
          expect(Types::PackageManager[type.to_sym].to_proto).not_to eq(nil)
        end
      end
    end
  end

  describe "supported_by_dgp" do
    it "should return a list of package managers supported by dgp" do
      expected = [Types::PackageManager[:npm]]
      expect(Types::PackageManager.supported_by_dgp).to eq(expected)
    end
  end
end
