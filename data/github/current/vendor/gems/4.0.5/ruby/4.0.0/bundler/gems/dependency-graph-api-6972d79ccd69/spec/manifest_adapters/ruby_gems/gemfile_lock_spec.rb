require "rails_helper"

describe "Gemfile.lock parsing" do
  let(:file) do
    <<~LOCKFILE
      GEM
        remote: https://rubygems.org/
        specs:
          httparty (0.14.0)
            multi_xml (>= 0.5.2)
          multi_xml (0.5.5)
          rake (11.3.0)
          sprockets-rails (3.2.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        rake
        httparty

      BUNDLED WITH
         1.13.1
    LOCKFILE
  end

  def manifest(attrs = {})
    ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: "Gemfile.lock",
      path: "",
      content:  file,
      pushed_at: Time.now,
      fork: false,
      visibility_private: false,
    }.merge(attrs))
  end

  def dependency(args)
    ManifestAdapters::Manifest::Dependency.new(**args)
  end

  describe "#manifest_type" do
    it "is a Gemfile.lock" do
      expect(manifest.manifest_type).to eq Types::Manifest[:gemfile_lock]
    end
  end

  describe "#package_manager" do
    it "is rubygems" do
      expect(manifest.package_manager).to eq Types::PackageManager[:rubygems]
    end
  end

  describe "#dependent_name" do
    it "is nil" do
      expect(manifest.dependent_name).to be_nil
    end
  end

  describe "#dependent_version" do
    it "is nil" do
      expect(manifest.dependent_version).to be_nil
    end
  end

  describe "#git_ref" do
    it "returns the commit SHA" do
      expect(manifest.git_ref)
        .to eq "78716382bd3de2dbf141643bbe40f93185b5d4c6"
    end
  end

  describe "#github_repository_id" do
    it "returns the repo ID" do
      expect(manifest.github_repository_id).to eq 55
    end
  end

  describe "#dependencies" do
    it "parses dependencies" do
      expect(manifest.dependencies).to match_array [
        dependency(package_name: "httparty", scope: :runtime, requirements: "= 0.14.0", raw_requirements: "= 0.14.0"),
        dependency(package_name: "multi_xml", scope: :runtime, requirements: "= 0.5.5", raw_requirements: "= 0.5.5"),
        dependency(package_name: "rake", scope: :runtime, requirements: "= 11.3.0", raw_requirements: "= 11.3.0"),
        dependency(package_name: "sprockets-rails", scope: :runtime, requirements: "= 3.2.0", raw_requirements: "= 3.2.0"),
      ]
    end

    it "ignores malformed dependencies" do
      dependencies = manifest({
        content: <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              httparty
                multi_xml (>= 0.5.2)
              multi_xml (0.5.5)
              rake (11.3.0)
              (???)

        LOCKFILE
      }).dependencies

      expect(dependencies).to match_array [
        dependency(package_name: "multi_xml", scope: :runtime, requirements: "= 0.5.5", raw_requirements: "= 0.5.5"),
        dependency(package_name: "rake", scope: :runtime, requirements: "= 11.3.0", raw_requirements: "= 11.3.0")
      ]
    end

    it "removes platform metadata from version strings" do
      dependencies = manifest({
        content: <<~LOCKFILE
          GEM
            remote: https://rubygems.org/
            specs:
              nokogiri (1.13.4-arm64-darwin)

        LOCKFILE
      }).dependencies

      expect(dependencies).to match_array [
        dependency(package_name: "nokogiri", scope: :runtime, requirements: "= 1.13.4", raw_requirements: "= 1.13.4-arm64-darwin"),
      ]
    end
  end
end
