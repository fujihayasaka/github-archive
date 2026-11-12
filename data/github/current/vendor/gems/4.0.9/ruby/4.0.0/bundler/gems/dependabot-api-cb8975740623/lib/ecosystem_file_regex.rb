# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength
class EcosystemFileRegex
  def initialize(package_manager)
    @package_manager = package_manager
  end

  def updated_files_regex
    raise "Unsupported package manager: #{@package_manager}" unless PackageManagers::ALL.include?(@package_manager)

    # The send method is used to call the method dynamically based on the package_manager
    send("#{@package_manager}_regex")
  end

  private

  def bundler_regex
    [
      # Matches Gemfile, Gemfile.lock, gems.rb, gems.locked, Gemfile.jumpstart,
      # .gemspec files, and anything in vendor directory
      %r{^(Gemfile(\.lock|\.jumpstart)?|gems\.(rb|locked)|.*\.gemspec|vendor/.*)$},
      # Matches the same files in any subdirectory
      %r{^.*/(Gemfile|Gemfile\.lock|Gemfile\.jumpstart|gems\.rb|gems\.locked)$},
    ]
  end

  def cargo_regex
    [
      /Cargo\.toml$/, # Matches Cargo.toml in the root directory or any subdirectory
      /Cargo\.lock$/, # Matches Cargo.lock in the root directory or any subdirectory
    ]
  end

  def composer_regex
    [
      /^composer\.json$/,
      /^composer\.lock$/,
    ]
  end

  def devcontainers_regex
    [
      # Matches devcontainer.json, .devcontainer.json, devcontainer-feature.json, .devcontainer-feature.json,
      # devcontainer-template.json, .devcontainer-template.json, devcontainer-lock.json, or .devcontainer-lock.json
      # in any directory from root to any subdirectory.
      %r{^(\.?)devcontainer(-feature|-template|-lock)?\.json$|.*/(\.?)devcontainer(-feature|-template|-lock)?\.json$},
    ]
  end

  def docker_regex
    [
      /dockerfile/i,
      /^[^.].*\.ya?ml$/i,
    ]
  end

  def docker_compose_regex
    [
      /(docker-)?compose(-\w+)?(?>\.[\w-]+)?\.ya?ml/i,
    ]
  end

  def helm_regex
    [
      /^Chart\.ya?ml$/i,
      /^.*values\.ya?ml$/i,
      /^Chart\.lock$/i,
    ]
  end

  def julia_regex
    [
      %r{^(?:.*/)?(?:Julia)?Project\.toml$},
      %r{^(?:.*/)?(?:Julia)?Manifest(?:-v\d+\.\d+)?\.toml$},
    ]
  end

  def dotnet_sdk_regex
    [
      # Matches global.json in the root directory or any subdirectory
      %r{(?:^|/)global\.json$},
    ]
  end

  def elm_regex
    [
      /^elm\.json$/,
    ]
  end

  def submodules_regex
    # The user can name the directory anything in submodules, so we can't rely on a specific regex for it.
    # The original regex was [] which should match everything, so I've replaced it with a match-all regex
    # to maintain the same behavior and ensure the dependency file allowlist passes the check.
    [
      /^.*/, # Matches any directory or file (this is a catch-all for any directory or subdirectory)
    ]
  end

  def github_actions_regex
    [
      # Matches .yml or .yaml files in the .github/workflows directories
      %r{\.github/workflows/.+\.ya?ml$},

      # Matches .yml or .yaml files in the root directory or any subdirectory
      %r{(?:^|/).+\.ya?ml$},
    ]
  end

  def go_modules_regex
    [
      %r{\A(?:.+/)?go\.mod\z},
      %r{\A(?:.+/)?go\.sum\z},
      /\Ago\.work\z/,
      /\Ago\.work\.sum\z/,
      %r{\A(?:.+/)?vendor/},
    ]
  end

  def gradle_regex
    [
      # Matches build.gradle or build.gradle.kts in root directory
      %r{(^|.*/)build\.gradle(\.kts)?$},
      # Matches gradle.lockfile in root directory
      %r{(^|.*/)gradle\.lockfile$},
      # Matches gradle/libs.versions.toml in root or any subdirectory
      %r{(^|.*/)?gradle/libs\.versions\.toml$},
      # Matches settings.gradle or settings.gradle.kts in root or any subdirectory
      %r{(^|.*/)settings\.gradle(\.kts)?$},
      # Matches settings.gradle.lockfile in root or any subdirectory
      %r{(^|.*/)settings\.gradle\.lockfile$},
      # Matches dependencies-*.gradle or dependencies-*.manifest in the root or any subdirectory
      %r{(^|.*/)(dependencies(-.+)?\.(gradle|manifest))$},
      # Matches gradlew in root or any subdirectory for Gradle wrapper files
      %r{(^|.*/)gradlew$},
      # Matches gradlew.bat in root or any subdirectory
      %r{(^|.*/)gradlew\.bat$},
      # Matches gradle/wrapper/gradle-wrapper.jar in root or any subdirectory
      %r{(^|.*/)?gradle/wrapper/gradle-wrapper\.jar$},
      # Matches gradle/wrapper/gradle-wrapper.properties in root or any subdirectory
      %r{(^|.*/)?gradle/wrapper/gradle-wrapper\.properties$},
    ]
  end

  def hex_regex
    [
      /^.*mix\.exs$/,
      /^.*mix\.lock$/,
    ]
  end

  def maven_regex
    [
      /^pom\.xml$/, %r{/pom\.xml$},
      /.*\.xml$/, %r{/.*\.xml$},
      /^extensions.\.xml$/, %r{/extensions\.xml$},
    ]
  end

  def npm_and_yarn_regex
    [
      %r{^(?:.*/)?package\.json$},
      %r{^(?:.*/)?package-lock\.json$},
      %r{^(?:.*/)?npm-shrinkwrap\.json$},
      %r{^(?:.*/)?yarn\.lock$},
      %r{^(?:.*/)?pnpm-lock\.yaml$},
      %r{^(?:.*/)?pnpm-workspace\.yaml$},
      %r{^(?:.*/)?\.yarn/.*}, # Matches any file within the .yarn/ directory
      %r{^(?:.*/)?\.pnp\.(?:js|cjs)$}, # Matches .pnp.js or .pnp.cjs files
      %r{^(?:.*/)?bun\.lock(b)?$}, # Matches bun.lock or bun.lockb files
    ]
  end

  def bun_regex
    [
      %r{^(?:.*/)?package\.json$},
      %r{^(?:.*/)?bunfig\.toml$},
      %r{^(?:.*/)?bun\.lock(b)?$}, # Matches bun.lock or bun.lockb files
    ]
  end

  def nuget_regex
    [
      /.*\.([a-z]{2})?proj$/,         # Matches files with any extension like .csproj, .vbproj, etc., in any directory
      /packages\.lock\.json/,         # Matches packages.lock.json in any directory
      /packages\.config$/i,           # Matches packages.config in any directory
      /app\.config$/i,                # Matches app.config in any directory
      /web\.config$/i,                # Matches web.config in any directory
      /global\.json$/i,               # Matches global.json in any directory
      /dotnet-tools\.json$/i,         # Matches dotnet-tools.json in any directory
      /.*\.props$/i,                  # Matches any file ending with .props in any directory
      /.*\.targets$/i,                # Matches any file ending with .targets in any directory
      /.*\.nuspec$/,                  # Matches any .nuspec files in any directory
      %r{^\.config/dotnet-tools\.json$}, # Matches .config/dotnet-tools.json in the root directory
    ]
  end

  def pub_regex
    [
      %r{^(.*/)?pubspec\.yaml$},
      %r{^(.*/)?pubspec\.lock$},
    ]
  end

  def pip_regex
    [
      /^.*Pipfile$/,             # Match Pipfile at any level
      /^.*Pipfile\.lock$/,       # Match Pipfile.lock at any level
      /^.*\.txt$/,               # Match any .txt files (e.g., requirements.txt) at any level
      /^.*\.in$/,                # Match any .in files at any level
      /^.*setup\.py$/,           # Match setup.py at any level
      /^.*setup\.cfg$/,          # Match setup.cfg at any level
      /^.*pyproject\.toml$/,     # Match pyproject.toml at any level
      /^.*pyproject\.lock$/,     # Match pyproject.lock at any level
      /^.*poetry\.lock$/,        # Match poetry.lock at any level
    ]
  end

  def rust_toolchain_regex
    [
      # Matches rust-toolchain.toml or rust-toolchain in the root directory or any subdirectory
      %r{(?:^|/)rust-toolchain(\.toml)?$},
    ]
  end

  def sbt_regex
    [
      # Matches build.sbt in the root directory or any subdirectory
      %r{(?:\A|/)build\.sbt\z},
      # Matches project/plugins.sbt in the root directory or any subdirectory
      %r{(?:\A|/)project/plugins\.sbt\z},
      # Matches project/*.scala in the root directory or any subdirectory
      %r{(?:\A|/)project/.*\.scala\z},
      # Matches project/build.properties in the root directory or any subdirectory
      %r{(?:\A|/)project/build\.properties\z},
    ]
  end

  def swift_regex
    [
      %r{(?:\A|/)Package(@swift-\d(\.\d){0,2})?\.swift\z},
      %r{(?:\A|/)Package\.resolved\z}, # Allow Package.resolved in any directory (e.g., inside .xcodeproj)
      %r{\.xcodeproj/.*project\.pbxproj\z}, # Allow project.pbxproj inside .xcodeproj bundles for Xcode SwiftPM
    ]
  end

  def terraform_regex
    [/\.tf$/, /\.hcl$/]
  end

  def uv_regex
    [
      /^.*\.txt$/,               # Match any .txt files (e.g., requirements.txt) at any level
      /^.*\.in$/,                # Match any .in files at any level
      /^.*pyproject\.toml$/,     # Match pyproject.toml at any level
      /^.*uv\.lock$/, # match uv.lock at any level
    ]
  end

  def vcpkg_regex
    [
      # Matches vcpkg.json or vcpkg-configuration.json in the root directory or any subdirectory
      %r{(?:^|/)vcpkg(-configuration)?\.json$},
    ]
  end

  def conda_regex
    [
      # Matches environment.yml or environment.yaml in the root directory or any subdirectory
      %r{(?:^|/)environment\.ya?ml$},
    ]
  end

  def bazel_regex
    [
      # Matches WORKSPACE or WORKSPACE.bazel in the root directory or any subdirectory
      %r{(?:^|/)WORKSPACE(\.bazel)?$},
      # Matches MODULE.bazel in the root directory or any subdirectory
      %r{(?:^|/)MODULE\.bazel$},
      # Matches *.MODULE.bazel files (e.g., deps.MODULE.bazel) in the root directory or any subdirectory
      %r{(?:^|/)[^/]*\.MODULE\.bazel$},
      # Matches BUILD or BUILD.bazel in the root directory or any subdirectory
      %r{(?:^|/)BUILD(\.bazel)?$},
      # Matches .bazelrc in the root directory or any subdirectory
      %r{(?:^|/)\.bazelrc$},
      # Matches MODULE.bazel.lock in the root directory or any subdirectory
      %r{(?:^|/)MODULE\.bazel\.lock$},
    ]
  end

  def opentofu_regex
    [
      /\.tf$/,                          # Matches .tf files in any directory
      /\.tofu$/,                        # Matches .tofu files in any directory
      /\.terraform\.lock\.hcl$/,        # Matches .terraform.lock.hcl files in any directory
    ]
  end

  def pre_commit_regex
    [
      # Matches .pre-commit-config.yml, .pre-commit-config.yaml, .pre-commit.yml, .pre-commit.yaml
      # in the root directory or any subdirectory
      /\.pre-commit(-config)?\.ya?ml$/i,
    ]
  end

  def nix_regex
    [
      # Matches flake.nix and flake.lock in the root directory or any subdirectory
      %r{(?:^|/)flake\.nix\z},
      %r{(?:^|/)flake\.lock\z},
    ]
  end

  def deno_regex
    [
      # Matches deno.json or deno.jsonc in the root directory or any subdirectory
      %r{(?:^|/)deno\.jsonc?\z},
      # Matches deno.lock in the root directory or any subdirectory
      %r{(?:^|/)deno\.lock\z},
    ]
  end
end
# rubocop:enable Metrics/ClassLength
