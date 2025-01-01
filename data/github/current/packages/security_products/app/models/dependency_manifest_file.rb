# typed: true
# frozen_string_literal: true

# Public: Encapsulates some logic related to Dependency Graph interop,
#         specifically whether a local file corresponds to a known manifest type.
class DependencyManifestFile
  extend GitHub::UTF8

  # See app/models/types.rb in github/dependency-graph-api repo for manifests understood by DG.
  #
  # These files are usually created with a specific casing, but the
  # default file systems on Microsoft Windows and Mac OS use
  # case-insensitive matching, and package managers vary in whether
  # they detect manifests case-sensitively, -insensitively, or using
  # the file system's matching, raising intriguing possibilities for
  # inconsistency.  Here, we use case-insensitive (/i) matching, which
  # may be overly broad, and let each Dependency Graph manifest
  # adaptor refine things further.
  GEMFILE_PATTERN = /(\A|\/)(?:gemfile|gems\.rb)\z/i
  GEMFILE_LOCK_PATTERN = /(\A|\/)(?:gemfile\.lock|gems\.locked)\z/i
  GEMSPEC_PATTERN = /\.gemspec\z/i
  PACKAGE_JSON_PATTERN = /(\A|\/)package\.json\z/i
  PACKAGE_LOCK_JSON_PATTERN = /(\A|\/)package-lock\.json\z/i
  PNPM_LOCK_PATTERN = /(\A|\/)pnpm-lock\.yaml\z/i
  YARN_LOCK_PATTERN = /(\A|\/)yarn\.lock\z/i
  PIPFILE_PATTERN = /(\A|\/)pipfile\z/i
  PIPFILE_LOCK_PATTERN = /(\A|\/)pipfile\.lock\z/i
  SETUP_PY_PATTERN = /(\A|\/)setup\.py\z/i
  PYPROJECT_TOML_PATTERN = /(\A|\/)pyproject\.toml\z/i
  POETRY_LOCK_PATTERN = /(\A|\/)poetry\.lock\z/i
  UV_LOCK_PATTERN = /(\A|\/)uv\.lock\z/i
  POM_XML_PATTERN = /(\A|\/)pom\.xml\z/i
  NUSPEC_PATTERN = /\.nuspec\z/i
  CSPROJ_PATTERN = /(\A|\/)(.*)?\.csproj\z/i
  VBPROJ_PATTERN = /(\A|\/)(.*)?\.vbproj\z/i
  VCXPROJ_PATTERN = /(\A|\/)(.*)?\.vcxproj\z/i
  FSPROJ_PATTERN = /(\A|\/)(.*)?\.fsproj\z/i
  PACKAGE_CONFIG_PATTERN = /(\A|\/)packages\.config\z/i
  COMPOSER_LOCK_PATTERN = /(\A|\/)composer\.lock\z/i
  COMPOSER_JSON_PATTERN = /(\A|\/)composer\.json\z/i
  GO_MOD_PATTERN = /(\A|\/)go\.mod\z/i
  ACTIONS_WORKFLOW_PATTERN = /\A\.github\/workflows\/[^\/]+\.ya?ml\z/i
  CARGO_LOCK_PATTERN = /(\A|\/)cargo\.lock\z/i
  CARGO_TOML_PATTERN = /(\A|\/)cargo\.toml\z/i
  PUBSPEC_YAML_PATTERN = /(\A|\/)pubspec\.ya?ml\z/i
  PUBSPEC_LOCK_PATTERN = /(\A|\/)pubspec\.lock\z/i
  PACKAGE_RESOLVED_PATTERN = /(\A|\/)Package\.resolved\z/i
  GRADLE_PATTERN = /(\A|\/)(?:build|settings)\.gradle(?:\.kts)?\z/i
  CONDA_YAML_PATTERN = /(\A|\/)environment\.ya?ml\z/i

  # Regex rule for detecting `requirements` string in python requirements.txt manifest name due to irregular naming:
  # Allow only a hyphen, period or underscore before requirements OR check that requirements is the beginning of the string.
  # Don't allow whitespace after requirements
  # Allow for other things after requirements, like requirements.prod.txt
  REQUIREMENTS_TXT_PATTERN = /(?:\-|\.|\_|\A|\/)requirements[^\s]*\.txt\Z/i

  # More lenient Regex rule for detecting `require` string in python requirements.txt manifest name due to irregular naming:
  # Allow anything except multiple periods OR whitespace before/after require.
  # Allow hyphen or underscore after require followed by non-period and non-whitespace characters.
  # Don't allow require to be a substring, e.g. don't allow "required.txt".
  # Requirements.txt can have a hyphen, underscore or forward slash before and after it.
  REQUIRE_TXT_PATTERN = /(?:[^\s|\.]*)require(?:(?:\-|\_|\/)[^\s|\.]*)?\.txt\Z/i

  NODE_MODULES_PATTERN = /(\A|\/)(.*)?node_modules(\z|\/)/i

  # In order to prevent Dependabot from trying to update unsupported manifests submitted
  # via the Dependency Submission API, we need a list of supported manifest file patterns:
  DEPENDABOT_SUPPORTED_MANIFEST_PATTERNS = [
    GEMFILE_LOCK_PATTERN,
    GEMSPEC_PATTERN,
    PACKAGE_JSON_PATTERN,
    PACKAGE_LOCK_JSON_PATTERN,
    YARN_LOCK_PATTERN,
    PNPM_LOCK_PATTERN,
    PIPFILE_PATTERN,
    PIPFILE_LOCK_PATTERN,
    SETUP_PY_PATTERN,
    PYPROJECT_TOML_PATTERN,
    POETRY_LOCK_PATTERN,
    UV_LOCK_PATTERN,
    POM_XML_PATTERN,
    NUSPEC_PATTERN,
    CSPROJ_PATTERN,
    VBPROJ_PATTERN,
    VCXPROJ_PATTERN,
    FSPROJ_PATTERN,
    PACKAGE_CONFIG_PATTERN,
    COMPOSER_LOCK_PATTERN,
    COMPOSER_JSON_PATTERN,
    ACTIONS_WORKFLOW_PATTERN,
    GO_MOD_PATTERN,
    CARGO_LOCK_PATTERN,
    CARGO_TOML_PATTERN,
    PUBSPEC_YAML_PATTERN,
    PUBSPEC_LOCK_PATTERN,
    REQUIREMENTS_TXT_PATTERN,
    REQUIRE_TXT_PATTERN,
    PACKAGE_RESOLVED_PATTERN,
    GRADLE_PATTERN,
    CONDA_YAML_PATTERN,
  ]

  # Public: Is this path recognized as a manifest by dependency-graph-api?
  #
  # path - A String representing a file path relative to the repository root.
  #
  # The current list of recognized manifests includes:
  #
  #    Gemfile
  #    Gemfile.lock
  #    <gem-name>.gemspec
  #    package.json
  #    package-lock.json
  #    pnpm-lock.yaml
  #    yarn.lock
  #    pipfile
  #    setup.py
  #    requirements.txt
  #    <optional-manifest-name>.nuspec
  #    project-name.csproj
  #    project-name.vbproj
  #    packages.config
  #    composer.json
  #    composer.lock
  #    go.mod
  #    Package.resolved
  #    environment.yml
  #    uv.lock
  #
  # They'll be recognized at any point in the repository directory hierarchy
  # except within vendor directories as defined by Linguist.
  #
  # Returns a boolean.
  def self.recognized_path?(path:)
    !!corresponding_manifest_type(path: path)
  end

  # Public: Is this path supported by Dependabot?
  # This method determines if we create `RepositoryDependencyUpdate` records.
  #
  # This method is separate from similar methods in this file because there are some manifests, like Gemfiles,
  # that are supported by the broader GitHub Supply Chain ecosystem that *aren't* supported by Dependabot.
  #
  # Returns a boolean.
  def self.supported_by_dependabot?(path:)
    DEPENDABOT_SUPPORTED_MANIFEST_PATTERNS.any? do |pattern|
      path.is_a?(String) && path =~ pattern
    end
  end

  # Internal: Maps a manifest file to its package type.
  #
  # path - A String representing a file path relative to the repository root.
  #
  # Compares the base file name of path against known manifest file names.
  #
  # Returns a Symbol or nil.
  def self.corresponding_package_type(path:)
    case corresponding_manifest_type(path: path)
    when :gemfile, :gemfile_lock, :gemspec then :rubygems
    when :package_json, :package_lock_json, :yarn_lock, :pnpm_lock then :npm
    when :requirements_txt, :pipfile, :pipfile_lock, :setup_py, :project_toml, :poetry_lock, :uv_lock then :pip
    when :pom_xml then :maven
    when :composer_json, :composer_lock then :composer
    when :nuspec, :csproj, :vbproj, :fsproj, :vcxproj, :package_config then :nuget
    when :go_mod then :go
    when :actions_workflow then :actions
    when :cargo_lock, :cargo_toml then :cargo
    when :pubspec_yaml, :pubspec_lock then :dart
    when :package_resolved then :swift
    when :conda_yaml then :pip
    end
  end
  # Note: When adding new ecosystem here, update DependencyReviewHelper and PackageDependenciesHelper as well

  # Returns the symbol for the manifest type, given a repository-root
  # relative file name string, or nil if unknown
  def self.corresponding_manifest_type(path:)
    path = utf8(path)

    case path

    when NODE_MODULES_PATTERN then nil

    # Actions - .github is now considered vendored in Linguist
    when ACTIONS_WORKFLOW_PATTERN then :actions_workflow

    # We want to exclude vendored paths *except* for the specific vendored
    # dependencies we support (AKA "loose files"), so this comes after the
    # vendored dependency patterns
    when DependencyGraphVendorRegex::Regex then nil

    # RubyGems
    when GEMFILE_PATTERN then :gemfile
    when GEMFILE_LOCK_PATTERN then :gemfile_lock
    when GEMSPEC_PATTERN then :gemspec

    # npm
    when PACKAGE_JSON_PATTERN then :package_json
    when PACKAGE_LOCK_JSON_PATTERN then :package_lock_json
    when YARN_LOCK_PATTERN then :yarn_lock
    when PNPM_LOCK_PATTERN then :pnpm_lock

    # pip
    when REQUIREMENTS_TXT_PATTERN then :requirements_txt
    when REQUIRE_TXT_PATTERN then :requirements_txt
    when PIPFILE_PATTERN then :pipfile
    when PIPFILE_LOCK_PATTERN then :pipfile_lock
    when SETUP_PY_PATTERN then :setup_py
    when PYPROJECT_TOML_PATTERN then :project_toml
    when POETRY_LOCK_PATTERN then :poetry_lock
    when UV_LOCK_PATTERN then :uv_lock

    # Maven
    when POM_XML_PATTERN then :pom_xml

    # NuGet
    when NUSPEC_PATTERN then :nuspec
    when CSPROJ_PATTERN then :csproj
    when VBPROJ_PATTERN then :vbproj
    when VCXPROJ_PATTERN then :vcxproj
    when FSPROJ_PATTERN then :fsproj
    when PACKAGE_CONFIG_PATTERN then :package_config

    # Composer
    when COMPOSER_JSON_PATTERN then :composer_json
    when COMPOSER_LOCK_PATTERN then :composer_lock

    # Go
    when GO_MOD_PATTERN then :go_mod

    # Cargo
    when CARGO_LOCK_PATTERN then :cargo_lock
    when CARGO_TOML_PATTERN then :cargo_toml

    # Pub
    when PUBSPEC_YAML_PATTERN then :pubspec_yaml
    when PUBSPEC_LOCK_PATTERN then :pubspec_lock

    # Swift
    when PACKAGE_RESOLVED_PATTERN then :package_resolved

    # Conda for pip
    when CONDA_YAML_PATTERN then :conda_yaml
    end
  end

  # Public: Maps a package manager to its manifest file.
  #
  # package_manager - A String representing a package manager.
  #
  # Compares the package manager against known package manager names.
  #
  # Returns a String
  def self.corresponding_manifest_file(package_manager:)
    case package_manager.to_sym
    when :MAVEN then "pom.xml"
    when :NPM then "package.json"
    when :NUGET then ".nuspec"
    when :PIP then "requirements.txt"
    when :RUBYGEMS then "Gemfile"
    when :COMPOSER then "composer.json"
    when :GO then "go.mod"
    when :ACTIONS then ".github/workflows/*/*.y[a]ml"
    when :CARGO then "Cargo.toml"
    when :PUB then "pubspec.yaml"
    when :SWIFT then "Package.resolved"
    else "package manager"
    end
  end

  # Public: Record dogstats for manifest files touched on a git push.
  #
  # repository - A Repository pushed to.
  # paths - An Enumerable of manifest path Strings.
  # default_branch - Boolean, true if the push was to the repository default
  #                  branch. Default: true.
  # initial_commit - Boolean, true if the push was an initial commit to the
  #                  branch. Default: false.
  #
  # Returns nothing.
  def self.record_repository_manifest_changed_stats(repository:, paths:, default_branch: true, initial_commit: false)
    package_types = paths.map { |p| corresponding_package_type(path: p) }.compact
    return if package_types.empty?

    tags = package_types.map { |t| "package_type:#{t}" }
    tags << "public:#{repository.public?}"
    tags << "fork:#{repository.fork?}"
    tags << "default_branch:#{default_branch}"
    tags << "initial_commit:#{initial_commit}"
    GitHub.dogstats.increment("repository.dependency_manifest_changed", tags: tags)
  end
end
