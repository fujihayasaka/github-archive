require "rails_helper"

describe ManifestAdapters::Rubygems::Adapter do
  it "identifies malformed manifests" do
    manifest = described_class.new(
      github_repository_id: 1,
      filename: "",
      path: "",
      git_ref: "0000000000000000000000000000000000000000",
      pushed_at: Time.now,
      fork: false,
      visibility_private: false,
      content: ""
    )

    expect(manifest.parse).to be_malformed
  end

  describe ".test" do
    def test(filename, path)
      described_class.test(filename: filename, path: path)
    end

    it "recognizes Gemfiles" do
      expect(test("Gemfile", nil)).to be_truthy
      expect(test("Gemfile", "/")).to be_truthy
      expect(test("Gemfile", "/lib")).to be_truthy
    end

    it "recognizes Gemfile.locks" do
      expect(test("Gemfile.lock", nil)).to be_truthy
      expect(test("Gemfile.lock", "/")).to be_truthy
      expect(test("Gemfile.lock", "/lib")).to be_truthy
    end

    it "recognizes gemspecs" do
      expect(test("rails.gemspec", nil)).to be_truthy
      expect(test("rails.gemspec", "/")).to be_truthy
      expect(test("rails.gemspec", "/lib/rails")).to be_truthy
    end

    it "recognizes gems.rb" do
      expect(test("gems.rb", nil)).to be_truthy
      expect(test("gems.rb", "/")).to be_truthy
      expect(test("gems.rb", "/lib")).to be_truthy
    end

    it "recognizes gems.locked" do
      expect(test("gems.locked", nil)).to be_truthy
      expect(test("gems.locked", "/")).to be_truthy
      expect(test("gems.locked", "/lib")).to be_truthy
    end

    it "returns nil when the file isn't recognized" do
      expect(test("gemspec", nil)).to be_falsey
      expect(test("Gem file", "/")).to be_falsey
      expect(test("README.md", "/")).to be_falsey
      expect(test("", "/")).to be_falsey
      expect(test(nil, "/")).to be_falsey
    end
  end
end
