# typed: true
# frozen_string_literal: true

require "test_helper"

class DependencyManifestFileTest < GitHub::TestCase

  TEST_PATHS = {
    "Gemfile" => {
      manifest_type: :gemfile,
      package_manager: :rubygems,
    },
    "Gemfile.lock" => {
      manifest_type: :gemfile_lock,
      package_manager: :rubygems,
    },
    "foo-bar.gemspec" => {
      manifest_type: :gemspec,
      package_manager:  :rubygems,
    },
    "http_parser.rb.gemspec" => {
      manifest_type: :gemspec,
      package_manager:  :rubygems,
    },
    "gems.rb" => {
      manifest_type: :gemfile,
      package_manager:  :rubygems,
    },
    "gems.locked" => {
      manifest_type: :gemfile_lock,
      package_manager:  :rubygems,
    },
    "package.json" => {
      manifest_type: :package_json,
      package_manager:  :npm,
    },
    "package-lock.json" => {
      manifest_type: :package_lock_json,
      package_manager:  :npm,
    },
    "yarn.lock" => {
      manifest_type: :yarn_lock,
      package_manager:  :npm,
    },
    "pnpm-lock.yaml" => {
      manifest_type: :pnpm_lock,
      package_manager:  :npm,
    },
    "setup.py" => {
      manifest_type: :setup_py,
      package_manager:  :pip,
    },
    "Pipfile" => {
      manifest_type: :pipfile,
      package_manager:  :pip,
    },
    "Pipfile.lock" => {
      manifest_type: :pipfile_lock,
      package_manager:  :pip,
    },
    "requirements.txt" => {
      manifest_type: :requirements_txt,
      package_manager:  :pip,
    },
    "requirements/production.txt" => {
      manifest_type: :requirements_txt,
      package_manager:  :pip,
    },
    "require.txt" => {
      manifest_type: :requirements_txt,
      package_manager:  :pip,
    },
    "require-test.txt" => {
      manifest_type: :requirements_txt,
      package_manager:  :pip,
    },
    "pyproject.toml" => {
      manifest_type: :project_toml,
      package_manager:  :pip,
    },
    "src/pyproject.toml" => {
      manifest_type: :project_toml,
      package_manager:  :pip,
    },
    "poetry.lock" => {
      manifest_type: :poetry_lock,
      package_manager:  :pip,
    },
    "src/poetry.lock" => {
      manifest_type: :poetry_lock,
      package_manager:  :pip,
    },
    "pom.xml" => {
      manifest_type: :pom_xml,
      package_manager:  :maven,
    },
    "something.nuspec" => {
      manifest_type: :nuspec,
      package_manager:  :nuget,
    },
    ".nuspec" => {
      manifest_type: :nuspec,
      package_manager:  :nuget,
    },
    ".nuspec/something.nuspec" => {
      manifest_type: :nuspec,
      package_manager:  :nuget,
    },
    "manifests/something.nuspec" => {
      manifest_type: :nuspec,
      package_manager:  :nuget,
    },
    ".csproj" => {
      manifest_type: :csproj,
      package_manager:  :nuget,
    },
    "src/home.csproj" => {
      manifest_type: :csproj,
      package_manager:  :nuget,
    },
    "home.csproj" => {
      manifest_type: :csproj,
      package_manager:  :nuget,
    },
    ".vbproj" => {
      manifest_type: :vbproj,
      package_manager:  :nuget,
    },
    "src/home.vbproj" => {
      manifest_type: :vbproj,
      package_manager:  :nuget,
    },
    "home.vbproj" => {
      manifest_type: :vbproj,
      package_manager:  :nuget,
    },
    ".vcxproj" => {
      manifest_type: :vcxproj,
      package_manager:  :nuget,
    },
    "src.vcxproj" => {
      manifest_type: :vcxproj,
      package_manager:  :nuget,
    },
    "sample/test.vcxproj" => {
      manifest_type: :vcxproj,
      package_manager:  :nuget,
    },
    ".fsproj" => {
      manifest_type: :fsproj,
      package_manager:  :nuget,
    },
    "src.fsproj" => {
      manifest_type: :fsproj,
      package_manager:  :nuget,
    },
    "sample/test.fsproj" => {
      manifest_type: :fsproj,
      package_manager:  :nuget,
    },
    "packages.config" => {
      manifest_type: :package_config,
      package_manager:  :nuget,
    },
    "src/composer.json" => {
      manifest_type: :composer_json,
      package_manager:  :composer,
    },
    "composer.json" => {
      manifest_type: :composer_json,
      package_manager:  :composer,
    },
    "src/composer.lock" => {
      manifest_type: :composer_lock,
      package_manager:  :composer,
    },
    "composer.lock" => {
      manifest_type: :composer_lock,
      package_manager:  :composer,
    },
    "src/go.mod" => {
      manifest_type: :go_mod,
      package_manager:  :go,
    },
    "go.mod" => {
      manifest_type: :go_mod,
      package_manager:  :go,
    },
    ".github/workflows/stuff.yaml" => {
      manifest_type: :actions_workflow,
      package_manager:  :actions,
    },
    ".github/workflows/more-stuff.yml" => {
      manifest_type: :actions_workflow,
      package_manager:  :actions,
    },
    ".github/workflows/more-----dashes.yaml" => {
      manifest_type: :actions_workflow,
      package_manager:  :actions,
    },
    ".github/workflows/package-lock.json" => {
      manifest_type: :package_lock_json,
      package_manager:  :npm, # verifies we don't consider this manifest as vendored
    },
    ".github/workflows/package.json" => {
      manifest_type: :package_json,
      package_manager:  :npm,
    },
    "src/cargo.toml" => {
      manifest_type: :cargo_toml,
      package_manager:  :cargo,
    },
    "cargo.toml" => {
      manifest_type: :cargo_toml,
      package_manager:  :cargo,
    },
    "src/cargo.lock" => {
      manifest_type: :cargo_lock,
      package_manager:  :cargo,
    },
    "cargo.lock" => {
      manifest_type: :cargo_lock,
      package_manager:  :cargo,
    },
    "src/pubspec.yaml" => {
      manifest_type: :pubspec_yaml,
      package_manager:  :dart,
    },
    "pubspec.yaml" => {
      manifest_type: :pubspec_yaml,
      package_manager:  :dart,
    },
    "src/pubspec.yml" => {
      manifest_type: :pubspec_yaml,
      package_manager:  :dart,
    },
    "pubspec.yml" => {
      manifest_type: :pubspec_yaml,
      package_manager:  :dart,
    },
    "src/pubspec.lock" => {
      manifest_type: :pubspec_lock,
      package_manager:  :dart,
    },
    "pubspec.lock" => {
      manifest_type: :pubspec_lock,
      package_manager:  :dart,
    },
    "src/Package.resolved" => {
      manifest_type: :package_resolved,
      package_manager:  :swift,
    },
    "Package.resolved" => {
      manifest_type: :package_resolved,
      package_manager:  :swift,
    },
  }

  context ".recognized_path?" do
    test "it recognizes valid files" do
      TEST_PATHS.each do |file, type|
        assert(DependencyManifestFile.recognized_path?(path: file), "#{file} expects to be recognized")

        package_type = type[:package_manager]
        if package_type != :actions # only package manager with explicit path requirements
          subdir_file = "subdir/#{file}"
          assert(DependencyManifestFile.recognized_path?(path: subdir_file), "#{subdir_file} expects to be recognized")
        end

        case_insensitive_file = file.swapcase
        assert(DependencyManifestFile.recognized_path?(path: case_insensitive_file), "#{case_insensitive_file} expects to be recognized")
      end
    end

    test "does not recognize invalid files" do
      non_manifest_paths = %w[
        README
        README.md
        not-a-Gemfile
        old.package.json
        nested/old.package.json
        Gemfile.lock.bak
        gems.lock
        jquery.js
        workflow.yaml
        lgithub/workflows/stuff.yaml
        .github/workflows/sub-dir-not-allowed/does-stuff.yml
        Cargo.tom
        Cargo.locks
        notcargo.toml
        notcargo.lock
        sillypubspec.yaml
        closingpubspec.lock
        pubspec.y
        pubspec.lockness
        package.resolve
        packages.resolved
        node_modules/package.json
        dependencies/package.json
        dependencies/package-lock.json
      ]

      non_manifest_paths.each do |file|
        refute(DependencyManifestFile.recognized_path?(path: file), "expected to not recognize #{file}")
      end

      refute(DependencyManifestFile.recognized_path?(path: "vendor/Gemfile"), "should not recognized vendored files")
      refute(DependencyManifestFile.recognized_path?(path: "node_modules/react/package.json"), "should not recognize node_modules files")
    end
  end

  context ".supported_by_dependabot?" do
    test "dependabot supports valid files" do
      dependabot_exclusions = [:gemfile]
      TEST_PATHS.each do |file, type|
        next if dependabot_exclusions.include?(type[:manifest_type])
        assert(DependencyManifestFile.supported_by_dependabot?(path: file), "#{file} should be supported by dependabot")
      end
    end
  end

  context ".corresponding_package_type" do
    test "it recognizes files as correct package types" do
      TEST_PATHS.each do |file, type|
        package_manager = type[:package_manager]
        assert_equal(package_manager, DependencyManifestFile.corresponding_package_type(path: file), "#{file} expects #{package_manager}")
      end
    end
  end

  context ".corresponding_manifest_file" do
    test "returns correct manifest file for manager" do
      package_managers = {
        "MAVEN" => "pom.xml",
        "NPM" => "package.json",
        "NUGET" => ".nuspec",
        "PIP" => "requirements.txt",
        "RUBYGEMS" => "Gemfile",
        "COMPOSER" => "composer.json",
        "GO" => "go.mod",
        "ACTIONS" => ".github/workflows/*/*.y[a]ml",
        "CARGO" => "Cargo.toml",
        "PUB" => "pubspec.yaml",
        "SWIFT" => "Package.resolved",
        "BOGUS" => "package manager", # unrecognized package manager
      }
      package_managers.each do |manager, file|
        assert_equal(file, DependencyManifestFile.corresponding_manifest_file(package_manager: manager), "#{manager} expects #{file}")
      end
    end
  end

  context ".corresponding_manifest_type" do
    test "it recognizes files as correct manifest types" do
      TEST_PATHS.each do |file, type|
        manifest_type = type[:manifest_type]
        assert_equal(manifest_type, DependencyManifestFile.corresponding_manifest_type(path: file), "#{file} expects #{manifest_type}")
      end
    end
  end
end
