require "rails_helper"

describe ParsedManifest do
  it "parses a Gemfile" do
    factory.given_package("rake", "11.2.0")

    factory.given_package("rails", "5.2.1")
      .update_package(github_repository_id: 100)
      .add_dependency("rake", "11.2.0")

    manifest = described_class.new(
      github_repository_id: 50,
      filename: "Gemfile",
      path: "/",
      content: <<~GEMFILE
        gem "rails", "~> 5.2.0", "< 5.3.0"

        group :development do
          gem "rspec", ">= 3.0.0"
        end
      GEMFILE
    )

    expect(manifest.manifest_type).to eq Types::Manifest[:gemfile]
    expect(manifest.filename).to eq "Gemfile"
    expect(manifest.path).to eq "/"
    expect(manifest.dependencies.count).to eq 2

    dependency = manifest.dependencies.first
    expect(dependency.package_name).to eq "rails"
    expect(dependency.package_github_repository_id).to eq 100
    expect(dependency.requirements).to eq "~> 5.2.0,< 5.3.0"
    expect(dependency.package_manager).to eq Types::PackageManager[:rubygems]
    expect(dependency.scope).to eq Types::Scope[:runtime]
    expect(dependency.has_dependencies?).to be_truthy

    dependency = manifest.dependencies.last
    expect(dependency.package_name).to eq "rspec"
    expect(dependency.package_github_repository_id).to be_nil
    expect(dependency.requirements).to eq ">= 3.0.0"
    expect(dependency.package_manager).to eq Types::PackageManager[:rubygems]
    expect(dependency.scope).to eq Types::Scope[:development]
    expect(dependency.has_dependencies?).to be_falsey
  end

  it "parses Gemfile.lock" do
    factory.given_package("actionpack", "5.0.0.1")
      .update_package(github_repository_id: 100)

    manifest = described_class.new(
      github_repository_id: 50,
      filename: "Gemfile.lock",
      path: "/",
      content: <<~GEMFILE_LOCK
        GEM
          remote: https://rubygems.org/
          specs:
            actionmailer (5.0.0.1)
              actionpack (= 5.0.0.1)
            actionpack (5.0.0.1)
      GEMFILE_LOCK
    )

    expect(manifest.manifest_type).to eq Types::Manifest[:gemfile_lock]
    expect(manifest.filename).to eq "Gemfile.lock"
    expect(manifest.path).to eq "/"
    expect(manifest.dependencies.count).to eq 2

    dependency = manifest.dependencies.first
    expect(dependency.package_name).to eq "actionmailer"
    expect(dependency.package_github_repository_id).to be_nil
    expect(dependency.requirements).to eq "= 5.0.0.1"
    expect(dependency.package_manager).to eq Types::PackageManager[:rubygems]
    expect(dependency.scope).to eq Types::Scope[:runtime]

    dependency = manifest.dependencies.last
    expect(dependency.package_name).to eq "actionpack"
    expect(dependency.package_github_repository_id).to eq 100
    expect(dependency.requirements).to eq "= 5.0.0.1"
    expect(dependency.package_manager).to eq Types::PackageManager[:rubygems]
    expect(dependency.scope).to eq Types::Scope[:runtime]
  end

  it "parses a gemspec" do
    manifest = described_class.new(
      github_repository_id: 50,
      filename: "my-gem.gemspec",
      path: "/lib",
      content: <<~GEMSPEC
        Gem::Specification.new do |spec|
          spec.name = "my-gem"

          spec.add_development_dependency "bundler", "~> 1.10"
        end
      GEMSPEC
    )

    expect(manifest.manifest_type).to eq Types::Manifest[:gemspec]
    expect(manifest.filename).to eq "my-gem.gemspec"
    expect(manifest.path).to eq "/lib"
    expect(manifest.dependencies.count).to eq 1

    dependency = manifest.dependencies.first
    expect(dependency.package_name).to eq "bundler"
    expect(dependency.package_github_repository_id).to be_nil
    expect(dependency.requirements).to eq "~> 1.10"
    expect(dependency.package_manager).to eq Types::PackageManager[:rubygems]
    expect(dependency.scope).to eq Types::Scope[:development]
  end

  it "handles invalid manifests" do
    manifest = described_class.new(
      github_repository_id: 50,
      filename: "Gemfile",
      path: "",
      content: <<~GEMSPEC
        gem "

        <<<<<<<<<<
        "rails
        >>>>>>>>>>
      GEMSPEC
    )

    expect(manifest.manifest_type).to eq Types::Manifest[:gemfile]
    expect(manifest.filename).to eq "Gemfile"
    expect(manifest.path).to eq ""
    expect(manifest.dependencies.count).to eq 0
  end

  it "sorts dependencies alphabetically" do
    manifest = described_class.new(
      github_repository_id: 50,
      filename: "Gemfile",
      path: "",
      content: <<~GEMSPEC
        gem "Rails"
        gem "capybara"
      GEMSPEC
    )

    expect(manifest.dependencies.map(&:package_name))
      .to eq %w{ capybara Rails }
  end

  it "treats unparsable requirements as 'any version' wildcards" do
    factory.given_package("promise", "1.0.0", :npm)
    factory.given_package("express", "2.0.0", :npm)
    factory.given_package("express", "2.1.0", :npm)
      .add_dependency("promise", "= 4.0.0")

    manifest = described_class.new(
      github_repository_id: 50,
      filename: "package.json",
      path: "",
      content: {
        dependencies: {
          express: "github/rails#new_brach"
        }
      }.to_json
    )

    expect(manifest.dependencies.count).to eq 1

    dependency = manifest.dependencies.first
    expect(dependency.package_name).to eq "express"
    expect(dependency.requirements).to eq ""
    expect(dependency.has_dependencies?).to be_truthy
  end

  describe "lacking a recognized manifest" do
    it "throws an exception when accessing manifest data" do
      expect {
        described_class.new(
          github_repository_id: 50,
          filename: "UNKNOWN",
          path: "/lib",
          content: ""
        )
      }.to raise_error(ManifestAdapters::NotRecognizedError)
    end
  end

  describe "vulnerabilities" do
    it "annotates dependencies with vulnerabilities" do
      included = factory.given_vulnerable_version_range({
        github_id: 200,
        package_name: "rails",
        package_manager: :rubygems,
        version_range: ">= 5.2.0, < 5.2.4"
      })

      excluded = factory.given_vulnerable_version_range({
        github_id: 201,
        package_name: "rails",
        package_manager: :rubygems,
        version_range: "> 5.3.0"
      })

      manifest = described_class.new(
        github_repository_id: 50,
        filename: "Gemfile",
        path: "/",
        content: <<~GEMFILE
          gem "rails", "~> 5.2.0", "< 5.3.0"
        GEMFILE
      )

      expect(manifest.dependencies.first.vulnerable_version_ranges)
        .to eq [included]
    end

    it "sanitizes SQL" do
      manifest = described_class.new(
        github_repository_id: 50,
        filename: "package.json",
        path: "/",
        content: <<~PACKAGE_JSON
          {
            "dependencies": {
              "react'; ": "0.4"
            }
          }
        PACKAGE_JSON
      )

      expect(manifest.dependencies.first.vulnerable_version_ranges)
        .to eq []
    end

    it "identifies unsupported vendored manifests" do
      manifest = described_class.new(
        github_repository_id: 50,
        filename: "package.json",
        path: ".npm/specifications/my-lib",
        content: <<~PACKAGE_JSON
          {
            "dependencies": {
              "react'; ": "0.4"
            }
          }
        PACKAGE_JSON
      )

      expect(manifest).to be_unsupported_vendored_manifest
    end
  end

  describe "when comparing versions" do
    it "handles four part versions" do
      vulnerable = factory.given_vulnerable_version_range({
        github_id: 200,
        package_name: "actionview",
        package_manager: :rubygems,
        version_range: "< 1.2.3.4"
      })

      manifest = described_class.new(
        github_repository_id: 50,
        filename: "Gemfile",
        path: "/",
        content: <<~GEMFILE
          gem "actionview", "= 1.2.3.3"
        GEMFILE
      )

      expect(manifest.dependencies.first.vulnerable_version_ranges)
        .to eq [vulnerable]
    end

    { "< 5.3.0": true,
      "<= 5.3.0": true,
      "= 5.3.0": false,
      ">= 5.3.0": false,
      "> 5.3.0": false }.each do |range, should_match|
      it "#{should_match ? "matches" : "does not match"} 5.3.0.alpha #{range}" do
        excluded = factory.given_vulnerable_version_range({
                                                            github_id: 200,
                                                            package_name: "rails",
                                                            package_manager: :rubygems,
                                                            version_range: range
                                                          })

        manifest1 = described_class.new(
          github_repository_id: 50,
          filename: "Gemfile",
          path: "/",
          content: <<~GEMFILE
          gem "rails", "= 5.3.0.alpha"
        GEMFILE
        )

        expected_result = should_match ? [excluded] : []
        expect(manifest1.dependencies.first.vulnerable_version_ranges)
          .to eq(expected_result)
      end
    end

  end

  describe "lazy loading" do
    it "doesn't query for package records if package information isn't requested" do
      manifest = described_class.new(
        github_repository_id: 50,
        filename: "Gemfile",
        path: "/",
        content: <<~GEMFILE
          gem "rails", "~> 5.2.0", "< 5.3.0"
        GEMFILE
      )

      expect { manifest.filename }
        .to_not make_database_queries(matching: "packages")

      expect { manifest.path }
        .to_not make_database_queries(matching: "package_versions")
    end
  end

  context "parses requirement.txt" do
    let(:file) do
      <<~TXT
      django
      mini__django..._..test==0.0.2
      TXT
    end
    let(:manifest) do
      described_class.new(
        github_repository_id: 42,
        filename: "requirements.txt",
        path: "/",
        content: file
      )
    end

    it "retrieves the dependency package_name and requirements" do
      expect(manifest.dependencies.first.package_name).to eq "django"
      expect(manifest.dependencies.first.requirements).to eq ""
      expect(manifest.dependencies.second.package_name).to eq "mini__django..._..test"
      expect(manifest.dependencies.second.requirements).to eq "= 0.0.2"
    end
  end

  context "actions" do
    before do
     factory.given_package("actions/checkout", "main", Types::PackageManager[:actions])
      .update_package(github_repository_id: 100)

      @manifest = described_class.new(
        github_repository_id: 50,
        filename: "stuff.yml",
        path: ".github/workflows/",
        content: <<~YAML
        name: Testing all types of dependencies

        jobs:
          first_job:
            runs-on: ubuntu-latest

            steps:
            - uses: actions/checkout@main
        YAML
      )
    end

    it "parses a manifest with named versions" do
      expect(@manifest.manifest_type).to eq Types::Manifest[:workflow_yaml]
      expect(@manifest.filename).to eq "stuff.yml"
      expect(@manifest.path).to eq ".github/workflows/"
      expect(@manifest.dependencies.count).to eq 1

      dependency = @manifest.dependencies.first

      expect(dependency.package_name).to eq "actions/checkout"
      expect(dependency.package_github_repository_id).to eq 100
      expect(dependency.requirements).to eq "= main"
      expect(dependency.package_manager).to eq Types::PackageManager[:actions]
      expect(dependency.scope).to eq Types::Scope[:runtime]
      expect(dependency.has_dependencies?).to be_falsey
    end

    it "does not attempt to create has_dependencies cache for ecosystems where sub dependencies don't exist" do
      expect_any_instance_of(Versioning::RequirementSet).to_not receive(:encoded_lower_bound)
      expect_any_instance_of(Versioning::RequirementSet).to_not receive(:encoded_upper_bound)

      dependency = @manifest.dependencies.first
      expect(dependency.has_dependencies?).to be_falsey
    end
  end
end
