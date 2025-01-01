require "rails_helper"
require "manifest_adapters"

describe "yarn.lock parsing" do
    def manifest(attributes = {})
      ::ManifestAdapters.parse(**{
        git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c7",
        github_repository_id: 100,
        filename: "yarn.lock",
        path: "",
        content: file_fixture("yarn.lock").read,
        pushed_at: Time.new(2017, 2, 1),
        fork: false,
        visibility_private: false,
      }.merge(attributes))
    end

    def newer_style_manifest(attributes = {})
      ::ManifestAdapters.parse(**{
        git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c7",
        github_repository_id: 100,
        filename: "yarn.lock",
        path: "",
        content: file_fixture("yarn.lock.v2").read,
        pushed_at: Time.new(2017, 2, 1),
        fork: false,
        visibility_private: false,
      }.merge(attributes))
    end

    def dependency(args)
      ManifestAdapters::Manifest::Dependency.new(**args)
    end

    it "parses metadata" do
      expect(manifest.dependent_name).to be_nil
      expect(manifest.dependent_version).to be_nil
      expect(manifest.malformed?).to be_falsey
      expect(manifest.dependencies).to_not be_nil
    end

    it "parses dependencies" do
      expect(manifest.dependencies).to match_array [
        dependency(package_name: "package-1", scope: Types::Scope[:runtime], requirements: "= 1.0.3", raw_requirements: "1.0.3"),
        dependency(package_name: "package-2", scope: Types::Scope[:runtime], requirements: "= 2.0.1", raw_requirements: "2.0.1"),
        dependency(package_name: "package-3", scope: Types::Scope[:runtime], requirements: "= 3.1.9", raw_requirements: "3.1.9"),
        dependency(package_name: "package-4", scope: Types::Scope[:runtime], requirements: "= 4.6.3", raw_requirements: "4.6.3"),

        # Optional is a known bad SemVer dependency, which prepends "v" to the requirement.
        # This causes "ArgumentError: v0.1.3 is not a valid SemVer Version", so we've coded a fix to strip prepending non-digits
        # Testing that we get this version tests that our fix works.
        dependency(package_name: "optional", scope: Types::Scope[:runtime], requirements: "= 0.1.3", raw_requirements: "0.1.3"),
      ]
    end

    it "parses dependencies for newer format" do
      expect(newer_style_manifest.dependencies).to match_array [
        dependency(package_name: "@actions/core", scope: Types::Scope[:runtime], requirements: "= 1.2.6", raw_requirements: "1.2.6"),
        dependency(package_name: "@algolia/cache-browser-local-storage", scope: Types::Scope[:runtime], requirements: "= 4.2.0", raw_requirements: "4.2.0"),
        dependency(package_name: "@algolia/cache-common", scope: Types::Scope[:runtime], requirements: "= 4.2.0", raw_requirements: "4.2.0"),
        dependency(package_name: "@babel/plugin-transform-parameters", scope: Types::Scope[:runtime], requirements: "= 7.15.4", raw_requirements: "7.15.4"),
      ]
    end
end
