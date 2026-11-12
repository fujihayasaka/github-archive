# frozen_string_literal: true

require "rails_helper"
require "ecosystem_file_regex"

RSpec.describe EcosystemFileRegex do
  describe "#updated_files_regex" do
    context "when checking all package managers" do
      it "returns non-empty regex patterns for each package manager" do
        PackageManagers::ALL.each do |package_manager|
          regex_instance = described_class.new(package_manager)

          # Check that updated_files_regex returns a non-empty array
          expect(regex_instance.updated_files_regex).
            not_to be_empty,
                   "Expected non-empty regex patterns for package manager: #{package_manager}"
        end
      end
    end

    context "when the package manager is bundler" do
      let(:regex) { described_class.new("bundler") }

      it "returns correct regex patterns for bundler" do
        expected_regex = [
          %r{^(Gemfile(\.lock|\.jumpstart)?|gems\.(rb|locked)|.*\.gemspec|vendor/.*)$},
          %r{^.*/(Gemfile|Gemfile\.lock|Gemfile\.jumpstart|gems\.rb|gems\.locked)$},
        ]
        expect(regex.updated_files_regex).to eq(expected_regex)
      end
    end

    context "when the package manager is cargo" do
      let(:regex) { described_class.new("cargo") }

      it "returns correct regex patterns for cargo" do
        expected_regex = [
          /Cargo\.toml$/,
          /Cargo\.lock$/,
        ]
        expect(regex.updated_files_regex).to eq(expected_regex)
      end
    end

    context "when the package manager is pip" do
      let(:regex) { described_class.new("pip") }

      it "returns correct regex patterns for pip" do
        expected_regex = [
          /^.*Pipfile$/,
          /^.*Pipfile\.lock$/,
          /^.*\.txt$/,
          /^.*\.in$/,
          /^.*setup\.py$/,
          /^.*setup\.cfg$/,
          /^.*pyproject\.toml$/,
          /^.*pyproject\.lock$/,
          /^.*poetry\.lock$/,
        ]
        expect(regex.updated_files_regex).to eq(expected_regex)
      end
    end

    context "when the package manager is go_modules" do
      let(:regex) { described_class.new("go_modules") }

      it "returns correct regex patterns for go_modules" do
        expected_regex = [
          %r{\A(?:.+/)?go\.mod\z},
          %r{\A(?:.+/)?go\.sum\z},
          /\Ago\.work\z/,
          /\Ago\.work\.sum\z/,
          %r{\A(?:.+/)?vendor/},
        ]
        expect(regex.updated_files_regex).to eq(expected_regex)
      end

      it "allows root-level go.mod and go.sum" do
        expect(regex.updated_files_regex[0]).to match("go.mod")
        expect(regex.updated_files_regex[1]).to match("go.sum")
      end

      it "allows subdirectory go.mod and go.sum (go.work workspace modules)" do
        expect(regex.updated_files_regex[0]).to match("module-a/go.mod")
        expect(regex.updated_files_regex[1]).to match("module-b/go.sum")
        expect(regex.updated_files_regex[0]).to match("nested/deep/module/go.mod")
      end

      it "allows go.work and go.work.sum" do
        expect(regex.updated_files_regex[2]).to match("go.work")
        expect(regex.updated_files_regex[3]).to match("go.work.sum")
      end

      it "does not allow go.work or go.work.sum in subdirectories" do
        patterns = regex.updated_files_regex
        expect(patterns.none? { |p| "dir/go.work".match?(p) }).to be true
        expect(patterns.none? { |p| "dir/go.work.sum".match?(p) }).to be true
      end

      it "allows vendor directories in subdirectories" do
        expect(regex.updated_files_regex[4]).to match("vendor/github.com/foo/bar/baz.go")
        expect(regex.updated_files_regex[4]).to match("module-a/vendor/github.com/foo/bar.go")
      end
    end

    context "when the package manager is docker_compose" do
      let(:regex) { described_class.new("docker_compose") }

      it "returns correct regex patterns for docker_compose" do
        expected_regex = [
          /(docker-)?compose(-\w+)?(?>\.[\w-]+)?\.ya?ml/i,
        ]
        expect(regex.updated_files_regex).to eq(expected_regex)
      end
    end

    context "when the package manager is uv" do
      let(:regex) { described_class.new("uv") }

      it "returns correct regex patterns for uv" do
        expected_regex = [
          /^.*\.txt$/,
          /^.*\.in$/,
          /^.*pyproject\.toml$/,
          /^.*uv\.lock$/,
        ]
        expect(regex.updated_files_regex).to eq(expected_regex)
      end
    end

    context "when the package manager is sbt" do
      let(:regex) { described_class.new("sbt") }

      it "returns correct regex patterns for sbt" do
        expected_regex = [
          %r{(?:\A|/)build\.sbt\z},
          %r{(?:\A|/)project/plugins\.sbt\z},
          %r{(?:\A|/)project/.*\.scala\z},
          %r{(?:\A|/)project/build\.properties\z},
        ]
        expect(regex.updated_files_regex).to eq(expected_regex)
      end
    end

    context "when the package manager is helm" do
      let(:regex) { described_class.new("helm") }

      it "returns correct regex patterns for helm" do
        expected_regex = [
          /^Chart\.ya?ml$/i,
          /^.*values\.ya?ml$/i,
          /^Chart\.lock$/i,
        ]
        expect(regex.updated_files_regex).to eq(expected_regex)
      end
    end

    context "when the package manager is bazel" do
      let(:regex) { described_class.new("bazel") }

      it "returns correct regex patterns for bazel" do
        expected_regex = [
          %r{(?:^|/)WORKSPACE(\.bazel)?$},
          %r{(?:^|/)MODULE\.bazel$},
          %r{(?:^|/)[^/]*\.MODULE\.bazel$},
          %r{(?:^|/)BUILD(\.bazel)?$},
          %r{(?:^|/)\.bazelrc$},
          %r{(?:^|/)MODULE\.bazel\.lock$},
        ]
        expect(regex.updated_files_regex).to eq(expected_regex)
      end
    end

    context "when the package manager is opentofu" do
      let(:regex) { described_class.new("opentofu") }

      it "returns correct regex patterns for opentofu" do
        expected_regex = [
          /\.tf$/,
          /\.tofu$/,
          /\.terraform\.lock\.hcl$/,
        ]
        expect(regex.updated_files_regex).to eq(expected_regex)
      end
    end

    context "when the package manager is gradle" do
      let(:regex) { described_class.new("gradle") }

      it "returns correct regex patterns for gradle" do
        expected_regex = [
          %r{(^|.*/)build\.gradle(\.kts)?$},
          %r{(^|.*/)gradle\.lockfile$},
          %r{(^|.*/)?gradle/libs\.versions\.toml$},
          %r{(^|.*/)settings\.gradle(\.kts)?$},
          %r{(^|.*/)settings\.gradle\.lockfile$},
          %r{(^|.*/)(dependencies(-.+)?\.(gradle|manifest))$},
          %r{(^|.*/)gradlew$},
          %r{(^|.*/)gradlew\.bat$},
          %r{(^|.*/)?gradle/wrapper/gradle-wrapper\.jar$},
          %r{(^|.*/)?gradle/wrapper/gradle-wrapper\.properties$},
        ]
        expect(regex.updated_files_regex).to eq(expected_regex)
      end
    end

    context "when the package manager is pre_commit" do
      let(:regex) { described_class.new("pre_commit") }

      it "returns correct regex patterns for pre_commit" do
        expected_regex = [
          /\.pre-commit(-config)?\.ya?ml$/i,
        ]
        expect(regex.updated_files_regex).to eq(expected_regex)
      end
    end

    context "when the package manager is nix" do
      let(:regex) { described_class.new("nix") }

      it "returns correct regex patterns for nix" do
        expected_regex = [
          %r{(?:^|/)flake\.nix\z},
          %r{(?:^|/)flake\.lock\z},
        ]
        expect(regex.updated_files_regex).to eq(expected_regex)
      end
    end

    context "when the package manager is unsupported" do
      let(:regex) { described_class.new("unsupported") }

      it "raises an error for unsupported package manager" do
        expect { regex.updated_files_regex }.to raise_error("Unsupported package manager: unsupported")
      end
    end
  end
end
