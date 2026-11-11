# frozen_string_literal: true

require "rails_helper"
require "dependency_file_allowlist"

RSpec.describe DependencyFileAllowlist do
  let(:update_config) { create(:update_config, package_manager: "bundler") }

  let(:update_job) do
    FactoryBot.create(:update_job, :processing, update_config: update_config)
  end

  describe "#allowed?" do
    context "when the package manager is missing" do
      it "ensures every package manager in PackageManagers::ALL has an allowed pattern" do
        PackageManagers::ALL.each do |package_manager|
          expect do
            allowlist = described_class.new(update_job)
            allowlist.send(:allowed_patterns)
          end.not_to raise_error, "allowed_patterns not defined for package manager: #{package_manager}"
        end
      end
    end

    context "when the package manager is bundler" do
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid bundler manifest files" do
        matching_files = [
          "Gemfile",
          "Gemfile.lock",
          "gems.rb",
          "gems.locked",
          "some_project.gemspec",
          "vendor/cache/business-1.5.0.gem",
          "backend/Gemfile",
          "backend/Gemfile.lock",
          "backend/gems.rb",
          "backend/gems.locked",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is cargo" do
      let(:update_config) { create(:update_config, package_manager: "cargo") }

      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid cargo manifest files" do
        matching_files = [
          "Cargo.toml",
          "Cargo.lock",
          "some_project/Cargo.toml",
          "some_project/Cargo.lock",
          "some_project/subdir/Cargo.toml",
          "some_project/subdir/Cargo.lock",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is composer" do
      let(:update_config) { create(:update_config, package_manager: "composer") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid composer manifest files" do
        matching_files = [
          "composer.json",
          "composer.lock",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is devcontainers" do
      let(:update_config) { create(:update_config, package_manager: "devcontainers") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid devcontainers manifest files" do
        matching_files = [
          ".devcontainer/devcontainer.json",
          ".devcontainer/devcontainer-lock.json",
          "devcontainer.json",
          "devcontainer-lock.json",
          ".devcontainer.json",
          ".devcontainer-lock.json",
          "foo/bar/.devcontainer.json",
          "foo/bar/.devcontainer-lock.json",

        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is docker" do
      let(:update_config) { create(:update_config, package_manager: "docker") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid docker manifest files" do
        matching_files = [
          "Dockerfile",
          "dockerfile",
          "my_dockerfile",
          "myapp.yaml",
          "config.yml",
          "service.yaml",
          "v1_tag.yaml",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is docker compose" do
      let(:update_config) { create(:update_config, package_manager: "docker_compose") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for valid docker compose manifest files" do
        matching_files = [
          "docker-compose.yml",
          "docker-compose.yaml",
          "docker-compose.local.yml",
          "docker-compose.local.yaml",
          "compose.yml",
          "compose.yaml",
          "compose.local.yaml",
          "compose-dev.yaml",
          "irrelevant/docker-compose.yml",
          "irrelevant/irrelevant/docker-compose.yml",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "Dockerfile",
          "package.json",
          "package-lock.json",
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is dotnet_sdk" do
      let(:update_config) { create(:update_config, package_manager: "dotnet_sdk") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid dotnet_sdk manifest files" do
        matching_files = [
          "global.json",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is elm" do
      let(:update_config) { create(:update_config, package_manager: "elm") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid elm manifest files" do
        matching_files = [
          "elm.json",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is git_submodules" do
      let(:update_config) { create(:update_config, package_manager: "submodules") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid git_submodules manifest files" do
        matching_files = [
          ".gitmodules",
          "submodule/.git",
          ".git/modules/submodule/config",
          ".git/modules/another/config",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end
    end

    context "when the package manager is github_actions" do
      let(:update_config) { create(:update_config, package_manager: "github_actions") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid GitHub Actions workflow file" do
        matching_files = [
          "action.yml",
          "action.yaml",
          "foo/bar/action.yml",
          "foo/bar/action.yaml",
          ".github/workflows/main.yml",
          ".github/workflows/ci-test.yaml",
          ".github/workflows/action.yml",
          ".github/workflows/123-foo.yml",
          "/.github/workflows/workflow.yml",
          "/.github/workflows/123-foo-bar.yml",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is go_modules" do
      let(:update_config) { create(:update_config, package_manager: "go_modules") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid go_modules manifest files" do
        matching_files = [
          "go.mod",
          "go.sum",
          "vendor/modules.txt",
          "vendor/github.com/example/package/package.go",
          "vendor/golang.org/x/text/unicode.go",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    # rubocop:disable RSpec/ExampleLength
    context "when the package manager is gradle" do
      let(:update_config) { create(:update_config, package_manager: "gradle") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid gradle manifest files" do
        matching_files = [
          "build.gradle",
          "build.gradle.kts",
          "settings.gradle",
          "settings.gradle.kts",
          "subproject/build.gradle",
          "subproject/build.gradle.kts",
          "subproject/settings.gradle",
          "subproject/settings.gradle.kts",
          "gradle/libs.versions.toml",
          "subproject/gradle/libs.versions.toml",
          "dependencies.gradle",
          "dependencies.manifest",
          "subproject/dependencies.gradle",
          "dependencies-mdb.gradle",
          "dependencies-mdb.manifest",
          "subproject/dependencies-mdb.gradle",
          "subproject/dependencies-mdb.manifest",
          "gradlew",
          "gradlew.bat",
          "gradle/wrapper/gradle-wrapper.jar",
          "gradle/wrapper/gradle-wrapper.properties",
          "subproject/gradlew",
          "subproject/gradlew.bat",
          "subproject/gradle/wrapper/gradle-wrapper.jar",
          "subproject/gradle/wrapper/gradle-wrapper.properties",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end
    # rubocop:enable RSpec/ExampleLength

    context "when the package manager is hex" do
      let(:update_config) { create(:update_config, package_manager: "hex") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid hex manifest files" do
        matching_files = [
          "mix.exs",
          "mix.lock",
          "apps/dependabot_business/mix.exs",
          "apps/dependabot_web/mix.exs",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is maven" do
      let(:update_config) { create(:update_config, package_manager: "maven") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid maven manifest files" do
        matching_files = [
          "pom.xml",
          "subproject/pom.xml",
          "extensions.xml",
          "subproject/extensions.xml",
          "somefile.xml",
          "subproject/somefile.xml",
          "configs/pom.xml",
          "configs/somefile.xml",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    # rubocop:disable RSpec/ExampleLength
    context "when the package manager is npm_and_yarn" do
      let(:update_config) { create(:update_config, package_manager: "npm_and_yarn") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid npm and yarn manifest files" do
        matching_files = [
          "package.json",
          "package-lock.json",
          "npm-shrinkwrap.json",
          "yarn.lock",
          "pnpm-lock.yaml",
          "pnpm-workspace.yaml",
          "subdirectory/package.json",
          "subdirectory/package-lock.json",
          "subdirectory/npm-shrinkwrap.json",
          "subdirectory/yarn.lock",
          "subdirectory/pnpm-lock.yaml",
          "apps/dependabot_business/package.json",
          "packages/package1/package.json",
          "packages/package2/yarn.lock",
          ".yarn/install-state.gz",
          ".yarn/cache/@es-test-npm-0.46.0-d544b36047-96010ece49.zip",
          ".pnp.js",
          ".pnp.cjs",
          "bun.lock",
          "subdirectory/bun.lock",
          "bun.lockb",
          "subdirectory/bun.lockb",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "Gemfile",
          "Gemfile.lock",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is bun" do
      let(:update_config) { create(:update_config, package_manager: "bun") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid bun manifest files" do
        matching_files = [
          "package.json",
          "subdirectory/package.json",
          "apps/dependabot_business/package.json",
          "packages/package1/package.json",
          "bun.lock",
          "subdirectory/bun.lock",
          "bunfig.toml",
          "subdirectory/bunfig.toml",
          "bun.lockb",
          "subdirectory/bun.lockb",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "Gemfile",
          "Gemfile.lock",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is nuget" do
      let(:update_config) { create(:update_config, package_manager: "nuget") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid nuget manifest files" do
        matching_files = [
          "project.csproj",
          "library.fsproj",
          "app.vbproj",
          "packages.config",
          "app.config",
          "web.config",
          "global.json",
          "dotnet-tools.json",
          "Directory.Build.props",
          "Source/Directory.Build.props",
          "Directory.targets",
          "src/Directory.targets",
          "Directory.Build.targets",
          "Directory.Packages.props",
          "Source/Directory.Packages.props",
          "Packages.props",
          "Proj1/Proj1/Proj1.csproj",
          ".config/dotnet-tools.json",
          ".nuspec",
          "subdirectory/.nuspec",
          "Service/Contract/packages.config",
          "../eng/CodeAnalysis.props",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
          "Gemfile",
          "Gemfile.lock",
          "NuGet.Config",
          "nuget.config",
          "Proj1/Proj1/NuGet.Config",
          "Proj1/Proj1/test/nuGet.config",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end
    # rubocop:enable RSpec/ExampleLength

    context "when the package manager is pub" do
      let(:update_config) { create(:update_config, package_manager: "pub") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid pub manifest files" do
        matching_files = [
          "pubspec.yaml",
          "pubspec.lock",
          "packages/foo_bar/pubspec.yaml",
          "packages/foo_bar/pubspec.lock",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
          "Gemfile",
          "Gemfile.lock",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    # rubocop:disable RSpec/ExampleLength
    context "when the package manager is pip" do
      let(:update_config) { create(:update_config, package_manager: "pip") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid pip manifest files" do
        matching_files = [
          "Pipfile",
          "Pipfile.lock",
          "requirements.txt",
          "constraints.txt",
          "some_dependency.in",
          "setup.py",
          "setup.cfg",
          "pyproject.toml",
          "pyproject.lock",
          "poetry.lock",
          "subdirectory/Pipfile",
          "subdirectory/requirements.txt",
          "requirements/test.in",
          "requirements/test.txt",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "package-lock.json",
          "package.json",
          "Gemfile",
          "Gemfile.lock",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end
    # rubocop:enable RSpec/ExampleLength

    context "when the package manager is rust-toolchain" do
      let(:update_config) { create(:update_config, package_manager: "rust_toolchain") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid rust-toolchain manifest files" do
        matching_files = [
          "rust-toolchain",
          "rust-toolchain.toml",
          "subdirectory/rust-toolchain",
          "subdirectory/rust-toolchain.toml",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is swift" do
      let(:update_config) { create(:update_config, package_manager: "swift") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid swift manifest files" do
        matching_files = [
          "Package.swift",
          "Package@swift-5.swift",
          "Package@swift-5.0.swift",
          "Package@swift-5.0.1.swift",
          "Package.resolved",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "package-lock.json",
          "package.json",
          "Gemfile",
          "Gemfile.lock",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    # rubocop:disable RSpec/ExampleLength
    context "when the package manager is terraform" do
      let(:update_config) { create(:update_config, package_manager: "terraform") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid terraform manifest files" do
        matching_files = [
          "main.tf",
          "variables.tf",
          "outputs.tf",
          "config.hcl",
          "nested/directory/main.tf",
          "nested/directory/config.hcl",
          "terraform/main.tf",
          "submodules/terraform/config.hcl",
          "hashicorp/consul/aws/main.tf",
          "hashicorp/consul/aws/config.hcl",
          "terraform-aws-modules/iam/aws/main.tf",
          "terraform-aws-modules/iam/aws/config.hcl",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "package-lock.json",
          "package.json",
          "Gemfile",
          "Gemfile.lock",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end
    # rubocop:enable RSpec/ExampleLength

    context "when the package manager is uv" do
      let(:update_config) { create(:update_config, package_manager: "uv") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid uv manifest files" do
        matching_files = [
          "requirements.txt",
          "constraints.txt",
          "some_dependency.in",
          "pyproject.toml",
          "uv.lock",
          "subdirectory/requirements.txt",
          "requirements/test.in",
          "requirements/test.txt",
          "subdirectory/uv.lock",
          "subdirectory/pyproject.toml",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do # rubocop:disable RSpec/ExampleLength
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "package-lock.json",
          "package.json",
          "Gemfile",
          "Gemfile.lock",
          "Pipfile",
          "Pipfile.lock",
          "setup.py",
          "setup.cfg",
          "pyproject.lock",
          "poetry.lock",
          "subdirectory/Pipfile",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is vcpkg" do
      let(:update_config) { create(:update_config, package_manager: "vcpkg") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid vcpkg manifest files" do
        matching_files = [
          "vcpkg.json",
          "vcpkg-configuration.json",
          "subdirectory/vcpkg.json",
          "subdirectory/vcpkg-configuration.json",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is helm" do
      let(:update_config) { create(:update_config, package_manager: "helm") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid helm manifest files" do
        matching_files = [
          "Chart.yaml",
          "Chart.yml",
          "chart.yaml",
          "values.yaml",
          "subdir/values.yaml",
          "subdir/dev.values.yaml",
          "Values.yml",
          "Chart.lock",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do # rubocop:disable RSpec/ExampleLength
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "package-lock.json",
          "package.json",
          "Gemfile",
          "Gemfile.lock",
          "Pipfile",
          "Pipfile.lock",
          "setup.py",
          "setup.cfg",
          "pyproject.lock",
          "poetry.lock",
          "subdirectory/Pipfile",
          "subdir/Chart.yaml",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is conda" do
      let(:update_config) { create(:update_config, package_manager: "conda") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for a valid conda environment files" do
        matching_files = [
          "environment.yaml",
          "environment.yml",
          "subdirectory/environment.yaml",
          "subdirectory/environment.yml",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do # rubocop:disable RSpec/ExampleLength
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "package-lock.json",
          "package.json",
          "Gemfile",
          "Gemfile.lock",
          "Pipfile",
          "Pipfile.lock",
          "setup.py",
          "setup.cfg",
          "pyproject.lock",
          "poetry.lock",
          "subdirectory/Pipfile",
          "subdir/Chart.yaml",
          "requirements.txt",
          "subdirectory/not-conda-env.yml",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is julia" do
      let(:update_config) { create(:update_config, package_manager: "julia") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for valid julia environment files" do
        matching_files = [
          "Project.toml",
          "Manifest.toml",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do # rubocop:disable RSpec/ExampleLength
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "package-lock.json",
          "package.json",
          "Gemfile",
          "Gemfile.lock",
          "Pipfile",
          "Pipfile.lock",
          "setup.py",
          "setup.cfg",
          "pyproject.lock",
          "poetry.lock",
          "subdirectory/Pipfile",
          "subdir/Chart.yaml",
          "requirements.txt",
          "subdirectory/not-conda-env.yml",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is bazel" do
      let(:update_config) { create(:update_config, package_manager: "bazel") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for valid bazel files" do # rubocop:disable RSpec/ExampleLength
        matching_files = [
          "WORKSPACE",
          "WORKSPACE.bazel",
          "MODULE.bazel",
          "deps.MODULE.bazel",
          "external.MODULE.bazel",
          "BUILD",
          "BUILD.bazel",
          ".bazelrc",
          "MODULE.bazel.lock",
          "subdirectory/WORKSPACE",
          "subdirectory/WORKSPACE.bazel",
          "subdirectory/MODULE.bazel",
          "subdirectory/BUILD",
          "subdirectory/BUILD.bazel",
          "subdirectory/.bazelrc",
          "subdirectory/MODULE.bazel.lock",
          "foo/bar/BUILD.bazel",
          "foo/bar/BUILD",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do # rubocop:disable RSpec/ExampleLength
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "package-lock.json",
          "package.json",
          "Gemfile",
          "Gemfile.lock",
          "Pipfile",
          "Pipfile.lock",
          "setup.py",
          "setup.cfg",
          "pyproject.lock",
          "poetry.lock",
          "subdirectory/Pipfile",
          "subdir/Chart.yaml",
          "requirements.txt",
          "WORKSPACE.txt",
          "BUILD.txt",
          "my_build_file.txt",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end

    context "when the package manager is opentofu" do
      let(:update_config) { create(:update_config, package_manager: "opentofu") }
      let(:allowlist) { described_class.new(update_job) }

      it "returns true for valid opentofu files" do
        matching_files = [
          "main.tf",
          "variables.tf",
          "outputs.tf",
          "main.tofu",
          "variables.tofu",
          "outputs.tofu",
          "subdirectory/main.tf",
          "subdirectory/main.tofu",
          "foo/bar/main.tf",
          "foo/bar/main.tofu",
        ]

        matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(true)
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "package-lock.json",
          "package.json",
          "Gemfile",
          "Gemfile.lock",
          "Pipfile",
          "Pipfile.lock",
        ]

        non_matching_files.each do |file_name|
          expect(allowlist.allowed?(file_name)).to eq(false)
        end
      end
    end
  end
end
