require "rails_helper"
require Rails.root.join("lib", "dependency_graph", "sbom", "dependency")

RSpec.shared_examples "gets dependencies for SBOM request" do
  describe "get_dependencies_for_s_b_o_m" do
    before do
      @repo = Repository.create!(github_repository_id: 13)
      factory.given_manifest(repository: @repo, package_manager: :npm, filename: "package-lock.json", path: "", last_pushed_at: Time.utc(2023, 01, 01))
             .add_dependency("axios", "= 1.0.0")
             .add_dependency("handlebars", "= 2.1.0")
             .add_dependency("zlib", "= 3.2.0")

      # superseded by the above manifest and should be excluded
      factory.given_manifest(repository: @repo, package_manager: :npm, filename: "package.json", path: "", last_pushed_at: Time.utc(2023, 01, 01))
              .add_dependency("axios", "= 1.0.0")
              .add_dependency("handlebars", ">= 2.1.0")
              .add_dependency("zlib", "^3.2.0")

      factory.given_manifest(repository: @repo, package_manager: :rubygems, filename: "gemfile", last_pushed_at: Time.utc(2023, 01, 01))
             .add_dependency("multi_xml", "= 0.5.2")
             .add_dependency("httparty", "= 2.0.1")
             .add_dependency("mongrel", ">= 1.2.0")
             .add_dependency("fakeweb", "~> 1.3")
    end

    it "returns an empty response for an invalid repository_id" do
      req = DependencyGraphAPI::V1::GetDependenciesForSBOMRequest.new({
        repository_id: 666
      })

      resp = handler.get_dependencies_for_s_b_o_m(req, {})

      expect(resp).to eq(DependencyGraphAPI::V1::GetDependenciesForSBOMResponse.new)
    end

    it "returns a response with dependencies for a valid repository_id" do
      req = DependencyGraphAPI::V1::GetDependenciesForSBOMRequest.new({
        repository_id: 13
      })

      factory.given_manifest(repository: @repo, package_manager: :npm, filename: "package-lock.json", path: "somewhere", last_pushed_at: Time.utc(2023, 01, 01))
             .add_dependency("react", "= 1.2.3")

      factory.given_manifest(repository: @repo, package_manager: :npm, filename: "package-lock.json", path: "some/other/dir", last_pushed_at: Time.utc(2023, 01, 01))
             .add_dependency("typescript", "= 0.2.3")

      resp = handler.get_dependencies_for_s_b_o_m(req, {})

      expect(resp.dependencies.length).to eq(9)
      expect(resp.dependencies
         .sort_by { |dep| [dep.package_manager, dep.package_name] }
         .map(&:to_h)).to match_array([
            { package_manager: :PACKAGE_MANAGER_NPM, package_name: "axios", version: "1.0.0", version_range: "", manifest_path: "package-lock.json" },
            { package_manager: :PACKAGE_MANAGER_NPM, package_name: "handlebars", version: "2.1.0", version_range: "", manifest_path: "package-lock.json" },
            { package_manager: :PACKAGE_MANAGER_NPM, package_name: "zlib", version: "3.2.0", version_range: "", manifest_path: "package-lock.json" },
            { package_manager: :PACKAGE_MANAGER_RUBYGEMS, package_name: "fakeweb", version: "", version_range: "~> 1.3", manifest_path: "gemfile" },
            { package_manager: :PACKAGE_MANAGER_RUBYGEMS, package_name: "httparty", version: "2.0.1", version_range: "", manifest_path: "gemfile" },
            { package_manager: :PACKAGE_MANAGER_RUBYGEMS, package_name: "mongrel", version: "", version_range: ">= 1.2.0", manifest_path: "gemfile" },
            { package_manager: :PACKAGE_MANAGER_RUBYGEMS, package_name: "multi_xml", version: "0.5.2", version_range: "", manifest_path: "gemfile" },
            { package_manager: :PACKAGE_MANAGER_NPM, package_name: "react", version: "1.2.3", version_range: "", manifest_path: "somewhere/package-lock.json" },
            { package_manager: :PACKAGE_MANAGER_NPM, package_name: "typescript", version: "0.2.3", version_range: "", manifest_path: "some/other/dir/package-lock.json" },
         ])
    end

    it "instrumentation counts the number of dependencies" do
      allow(Instrument).to receive(:count).and_call_original

      req = DependencyGraphAPI::V1::GetDependenciesForSBOMRequest.new({
        repository_id: 13
      })

      resp = handler.get_dependencies_for_s_b_o_m(req, {})

      expect(Instrument).to have_received(:count).with(
        "sbom.dependencies.count", resp.dependencies.length,
        {
          dependency_source: :database,
          repository_id: 13,
          rpc_service: "DgpAPI",
          rpc_method: "GetDependenciesForSBOM"
        }
      )
    end

    it "excludes specified package managers" do
      req = DependencyGraphAPI::V1::GetDependenciesForSBOMRequest.new({
        repository_id: 13, excluding_package_managers: [:PACKAGE_MANAGER_NPM]
      })

      resp = handler.get_dependencies_for_s_b_o_m(req, {})

      expect(resp.dependencies.length).to eq(4)
      expect(resp.dependencies
         .sort_by { |dep| [dep.package_manager, dep.package_name] }
         .map(&:to_h)).to eq([
            { package_manager: :PACKAGE_MANAGER_RUBYGEMS, package_name: "fakeweb", version: "", version_range: "~> 1.3", manifest_path: "gemfile" },
            { package_manager: :PACKAGE_MANAGER_RUBYGEMS, package_name: "httparty", version: "2.0.1", version_range: "", manifest_path: "gemfile" },
            { package_manager: :PACKAGE_MANAGER_RUBYGEMS, package_name: "mongrel", version: "", version_range: ">= 1.2.0", manifest_path: "gemfile" },
            { package_manager: :PACKAGE_MANAGER_RUBYGEMS, package_name: "multi_xml", version: "0.5.2", version_range: "", manifest_path: "gemfile" }
         ])
    end

    it "correctly handles exact versions and ranges" do
      req = DependencyGraphAPI::V1::GetDependenciesForSBOMRequest.new({
        repository_id: 13
      })

      resp = handler.get_dependencies_for_s_b_o_m(req, {})

      expect(resp.dependencies.length).to eq(7)
      resp.dependencies.each do |dep|
        # one of: only one of these should be set
        expect([dep.has_version?, dep.has_version_range?].count(false)).to eq(1)
      end
    end

    it "deduplicates packages with same name, requirements, and package manager" do
      repo = Repository.create!(github_repository_id: 50)
      factory.given_manifest(repository: repo, package_manager: :npm, filename: "package.json", path: "first", last_pushed_at: Time.utc(2023, 01, 01))
      .add_dependency("axios", "= 1.0.0")
      .add_dependency("handlebars", "= 2.1.0")
      .add_dependency("zlib", "= 3.2.0")

      factory.given_manifest(repository: repo, package_manager: :npm, filename: "package.json", path: "second", last_pushed_at: Time.utc(2023, 01, 01))
      .add_dependency("axios", "= 1.0.0")
      .add_dependency("handlebars", "= 2.1.0")
      .add_dependency("zlib", "= 3.2.0")

      req = DependencyGraphAPI::V1::GetDependenciesForSBOMRequest.new({
        repository_id: 50
      })

      resp = handler.get_dependencies_for_s_b_o_m(req, {})

      expect(resp.dependencies.length).to eq(3)
      expect(resp.dependencies
         .sort_by { |dep| [dep.package_manager, dep.package_name] }
         .map(&:to_h)).to eq([
           { package_manager: :PACKAGE_MANAGER_NPM, package_name: "axios", version: "1.0.0", version_range: "", manifest_path: "first/package.json" },
           { package_manager: :PACKAGE_MANAGER_NPM, package_name: "handlebars", version: "2.1.0", version_range: "", manifest_path: "first/package.json" },
           { package_manager: :PACKAGE_MANAGER_NPM, package_name: "zlib", version: "3.2.0", version_range: "", manifest_path: "first/package.json" },
         ])
    end

    context "retrieving go dependencies" do
      before do
        @go_repo = Repository.create!(github_repository_id: 42)

        manifest = factory.given_manifest(
          repository: @go_repo,
          package_manager: :go,
          filename: "go.mod",
          path: "",
          last_pushed_at: Time.utc(2023, 01, 01)
        )

        manifest.add_dependency("github.com/spf13/cobra", "= 1.8.0")
        # At time of writing, we do not persist the `v` prefix in dg-api, but lets
        # add a test case to verify we behave correctly if it does happen.
        manifest.add_dependency("github.com/github/go_spdx", "= v1.8.1")
        manifest.add_dependency("github.com/mattn/go-isatty", "= 0.0.0-20250303144028-a0af3efb3deb")
      end

      it "consistently returns versions prefixed with a v" do
        req = DependencyGraphAPI::V1::GetDependenciesForSBOMRequest.new({
          repository_id: @go_repo.github_repository_id
        })

        resp = handler.get_dependencies_for_s_b_o_m(req, {})

        expect(resp.dependencies.length).to eq(3)
        expect(resp.dependencies
         .sort_by { |dep| [dep.package_manager, dep.package_name] }
         .map(&:to_h)).to match_array([
            { package_manager: :PACKAGE_MANAGER_GOMOD, package_name: "github.com/spf13/cobra", version: "v1.8.0", version_range: "", manifest_path: "go.mod" },
            { package_manager: :PACKAGE_MANAGER_GOMOD, package_name: "github.com/github/go_spdx", version: "v1.8.1", version_range: "", manifest_path: "go.mod" },
            { package_manager: :PACKAGE_MANAGER_GOMOD, package_name: "github.com/mattn/go-isatty", version: "v0.0.0-20250303144028-a0af3efb3deb", version_range: "", manifest_path: "go.mod" },
         ])
      end
    end
  end
end

describe DgpService::V1::Handler do
  let(:handler) { described_class.new }
  published_at = Time.now

  context "normalised tables (dotcom and Proxima)" do
    before do
      allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(true)
    end

    context "get_dependencies_for_s_b_o_m" do
      it_behaves_like "gets dependencies for SBOM request"
    end
  end

  context "unnormalized tables (GHES)" do
    before do
      allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(false)
    end

    context "get_dependencies_for_s_b_o_m" do
      it_behaves_like "gets dependencies for SBOM request"
    end
  end

  context "get_licenses_for_packages" do
    before do
      factory do
        def add_attributions_to_release(release, attributions)
          a = attributions.map do |attribution|
            Attribution.create!(package_release: release, attribution: attribution)
          end

          release.update!(attributions: a)
        end

        package_factory = given_package("react", "1.0.0", :npm)
        add_attributions_to_release(package_factory.release, ["Copyright 2024 Aguirre, der Zorn Gottes"])
        package_factory.release.update!(license: "MIT", published_at: published_at)

        package_factory = given_package("react", "2.0.0", :npm)
        add_attributions_to_release(package_factory.release, ["Copyright 2024 Example Four", "Copyright 2024 Example Five"])
        package_factory.release.update!(license: "GPL", published_at: published_at)

        package_factory = given_package("react", "3.0.0-alpha", :npm)
        add_attributions_to_release(package_factory.release, [
          "Copyright 2024 Aguirre, der Zorn Gottes",
          "Copyright 2024 Another Example",
          "Copyright 2024 Yet Another Example"
        ])
        package_factory.release.update!(license: "BSD")

        package_factory = given_package("chalk", "1.2.3", :npm)
        add_attributions_to_release(package_factory.release, ["Copyright 2024 Another Example"])
        package_factory.release.update!(license: "MIT", published_at: published_at)

        package_factory = given_package("chalk", "1.2.5", :npm)
        add_attributions_to_release(package_factory.release, ["Copyright 2024 Yet Another Example"])
        package_factory.release.update!(license: "MIT", published_at: published_at)
      end
    end

    it "returns list of licenses for all packages versions when no versions are specified" do

      req = DependencyGraphAPI::V1::GetLicensesForPackagesRequest.new({
        packages: [
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react"
          },
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "chalk"
          }
        ]
      })

      resp = handler.get_licenses_for_packages(req, {})

      licenses = resp.licenses
                     .sort_by { |license| [license.package_manager, license.package_name] }
                     .map { |license| license.to_h }

      expect(licenses).to eq(
        [
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "chalk",
            package_licenses: [
              { attributions: [], package_version: "1.2.3", package_license: "MIT" },
              { attributions: [], package_version: "1.2.5", package_license: "MIT" }
            ]
          },
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react",
            package_licenses: [
              { attributions: [], package_version: "1.0.0", package_license: "MIT" },
              { attributions: [], package_version: "2.0.0", package_license: "GPL" },
              { attributions: [], package_version: "3.0.0-alpha", package_license: "BSD" }
            ]
          }
        ]
      )
    end

    it "returns list of licenses for specific packages versions when versions are specified" do

      req = DependencyGraphAPI::V1::GetLicensesForPackagesRequest.new({
        packages: [
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react",
            package_versions: ["3.0.0-alpha"]
          },
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "chalk",
            package_versions: ["1.2.3"]
          }
        ]
      })

      resp = handler.get_licenses_for_packages(req, {})

      licenses = resp.licenses
                     .sort_by { |license| [license.package_manager, license.package_name] }
                     .map { |license| license.to_h }

      expect(licenses).to eq(
        [
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "chalk",
            package_licenses: [
              { attributions: [], package_version: "1.2.3", package_license: "MIT" }
            ]
          },
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react",
            package_licenses: [
              { attributions: [], package_version: "3.0.0-alpha", package_license: "BSD" }
            ]
          }
        ]
      )
    end

    it "returns combined results when specific packages versions are partly specified for some packages" do

      req = DependencyGraphAPI::V1::GetLicensesForPackagesRequest.new({
        packages: [
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react",
            package_versions: ["3.0.0-alpha"]
          },
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "chalk"
          }
        ]
      })

      resp = handler.get_licenses_for_packages(req, {})

      licenses = resp.licenses
                     .sort_by { |license| [license.package_manager, license.package_name] }
                     .map { |license| license.to_h }

      expect(licenses).to eq(
        [
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "chalk",
            package_licenses: [
              { attributions: [], package_version: "1.2.3", package_license: "MIT" },
              { attributions: [], package_version: "1.2.5", package_license: "MIT" }
            ]
          },
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react",
            package_licenses: [
              { attributions: [], package_version: "3.0.0-alpha", package_license: "BSD" }
            ]
          }
        ]
      )
    end

    it "includes attributions when requested" do

      req = DependencyGraphAPI::V1::GetLicensesForPackagesRequest.new({
        packages: [
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react",
            package_versions: ["3.0.0-alpha"]
          },
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "chalk"
          }
        ],
        include_copyright_attributions: true
      })

      resp = handler.get_licenses_for_packages(req, {})

      licenses = resp.licenses
                     .sort_by { |license| [license.package_manager, license.package_name] }
                     .map { |license| license.to_h }

      expect(licenses).to eq(
        [
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "chalk",
            package_licenses: [
              { attributions: ["Copyright 2024 Another Example"], package_version: "1.2.3", package_license: "MIT" },
              { attributions: ["Copyright 2024 Yet Another Example"], package_version: "1.2.5", package_license: "MIT" }
            ]
          },
          {
            package_manager: :PACKAGE_MANAGER_NPM,
            package_name: "react",
            package_licenses: [
              { attributions: [
                  "Copyright 2024 Aguirre, der Zorn Gottes",
                  "Copyright 2024 Another Example",
                  "Copyright 2024 Yet Another Example"
                ],
                package_version: "3.0.0-alpha",
                package_license: "BSD"
              }
            ]
          }
        ]
      )
    end

    context "retrieving licenses for go packages" do
      let(:mixed_case_package_name) do
        "github.com/mATTN/go-isatty"
      end

      let(:lowercase_package_name) do
        "github.com/mattn/go-isatty"
      end

      before do
        factory do
          # Our package ingestion for go always prefixes release versions with 'v'
          package_factory = given_package("github.com/spf13/cobra", "v1.8.0", :go)
          package_factory.release.update!(license: "MIT", published_at: published_at)
          package_factory = given_package("github.com/spf13/cobra", "v1.8.1", :go)
          package_factory.release.update!(license: "BSD", published_at: published_at)

          package_factory = given_package("github.com/github/go_spdx", "v1.8.0", :go)
          package_factory.release.update!(license: "BSD", published_at: published_at)
          package_factory = given_package("github.com/github/go_spdx", "v1.8.1", :go)
          package_factory.release.update!(license: "MIT", published_at: published_at)

          # It can also ingest packages with mixed case names
          package_factory = given_package("github.com/mATTN/go-isatty", "v0.0.20", :go)
          package_factory.release.update!(license: "MIT", published_at: published_at)

          # The case can be inconsistent between releases as well
          package_factory = given_package("github.com/mattn/go-isatty", "v0.0.21", :go)
          package_factory.release.update!(license: "MIT", published_at: published_at)
        end
      end

      it "returns the correct list of licences when no specific versions are specified" do
        req = DependencyGraphAPI::V1::GetLicensesForPackagesRequest.new({
          packages: [
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: "github.com/spf13/cobra",
            },
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: "github.com/github/go_spdx",
            }
          ]
        })

        resp = handler.get_licenses_for_packages(req, {})

        licenses = resp.licenses
                      .sort_by { |license| [license.package_manager, license.package_name] }
                      .map { |license| license.to_h }

        expect(licenses).to eq(
          [
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: "github.com/github/go_spdx",
              package_licenses: [
                { attributions: [], package_version: "v1.8.0", package_license: "BSD" },
                { attributions: [], package_version: "v1.8.1", package_license: "MIT" }
              ]
            },
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: "github.com/spf13/cobra",
              package_licenses: [
                { attributions: [], package_version: "v1.8.0", package_license: "MIT" },
                { attributions: [], package_version: "v1.8.1", package_license: "BSD" }
              ]
            }
          ]
        )
      end

      # This typically happens when the versions are submitted via a snapshot, it tends to follow
      # ecosystem-specific conventions to prefix versions with `v` consistently
      it "returns the correct versions when specified versions start with v" do
        req = DependencyGraphAPI::V1::GetLicensesForPackagesRequest.new({
          packages: [
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: "github.com/spf13/cobra",
              package_versions: ["v1.8.0"],
            },
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: "github.com/github/go_spdx",
              package_versions: ["v1.8.1"],
            }
          ]
        })

        resp = handler.get_licenses_for_packages(req, {})

        licenses = resp.licenses
                      .sort_by { |license| [license.package_manager, license.package_name] }
                      .map { |license| license.to_h }

        expect(licenses).to eq(
          [
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: "github.com/github/go_spdx",
              package_licenses: [
                { attributions: [], package_version: "v1.8.1", package_license: "MIT" }
              ]
            },
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: "github.com/spf13/cobra",
              package_licenses: [
                { attributions: [], package_version: "v1.8.0", package_license: "MIT" },
              ]
            }
          ]
        )
      end

      # This typically happens when the versions are obtained from static parsing as we will use
      # generic versions persisted to SQL that do not follow go-specific conventions.
      it "returns the correct versions when specified versions do not start with v" do
        req = DependencyGraphAPI::V1::GetLicensesForPackagesRequest.new({
          packages: [
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: "github.com/spf13/cobra",
              package_versions: ["1.8.0"],
            },
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: "github.com/github/go_spdx",
              package_versions: ["1.8.1"],
            }
          ]
        })

        resp = handler.get_licenses_for_packages(req, {})

        licenses = resp.licenses
                      .sort_by { |license| [license.package_manager, license.package_name] }
                      .map { |license| license.to_h }

        expect(licenses).to eq(
          [
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: "github.com/github/go_spdx",
              package_licenses: [
                { attributions: [], package_version: "v1.8.1", package_license: "MIT" }
              ]
            },
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: "github.com/spf13/cobra",
              package_licenses: [
                { attributions: [], package_version: "v1.8.0", package_license: "MIT" },
              ]
            }
          ]
        )
      end

      it "matches releases without case sensitivity" do
        req = DependencyGraphAPI::V1::GetLicensesForPackagesRequest.new({
          packages: [
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: lowercase_package_name,
            }
          ]
        })

        resp = handler.get_licenses_for_packages(req, {})

        licenses = resp.licenses
                      .sort_by { |license| [license.package_manager, license.package_name] }
                      .map { |license| license.to_h }

        expect(licenses).to eq(
          [
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: lowercase_package_name,
              package_licenses: [
                { attributions: [], package_version: "v0.0.20", package_license: "MIT" },
                { attributions: [], package_version: "v0.0.21", package_license: "MIT" }
              ]
            },
          ]
        )
      end

      it "returns the package name in the specified case instead of the database case" do
        req = DependencyGraphAPI::V1::GetLicensesForPackagesRequest.new({
          packages: [
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: mixed_case_package_name,
              package_versions: ["v0.0.21"],
            }
          ]
        })

        resp = handler.get_licenses_for_packages(req, {})

        licenses = resp.licenses
                      .sort_by { |license| [license.package_manager, license.package_name] }
                      .map { |license| license.to_h }

        expect(licenses).to eq(
          [
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: mixed_case_package_name,
              package_licenses: [
                { attributions: [], package_version: "v0.0.21", package_license: "MIT" }
              ]
            },
          ]
        )
      end

      # This is a corner case, it seems irregular for a caller to ask us
      # to find licences for a single package twice with different cases of
      # package name.
      #
      # This test exists mainly to document how we will behave were this to
      # happen, which is to return the same releases for both versions of the
      # package name.
      #
      # This is best effort to adhere to the rule of least surprise in the event
      # of a batch operation across several manifests using randomised cases.
      it "tolerates the same package being given twice with difference cases" do
        req = DependencyGraphAPI::V1::GetLicensesForPackagesRequest.new({
          packages: [
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: mixed_case_package_name,
            },
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: lowercase_package_name,
            }
          ]
        })

        resp = handler.get_licenses_for_packages(req, {})

        licenses = resp.licenses
                      .sort_by { |license| [license.package_manager, license.package_name] }
                      .map { |license| license.to_h }

        expect(licenses).to eq(
          [
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: mixed_case_package_name,
              package_licenses: [
                { attributions: [], package_version: "v0.0.20", package_license: "MIT" },
                { attributions: [], package_version: "v0.0.21", package_license: "MIT" }
              ]
            },
            {
              package_manager: :PACKAGE_MANAGER_GOMOD,
              package_name: lowercase_package_name,
              package_licenses: [
                { attributions: [], package_version: "v0.0.20", package_license: "MIT" },
                { attributions: [], package_version: "v0.0.21", package_license: "MIT" }
              ]
            },
          ]
        )
      end
    end
  end
end
