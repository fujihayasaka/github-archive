module Types

  # See https://github.com/github/team-advisory-database/issues/1874#issuecomment-829469558
  # for an extensive list of (ecosystem, language, registry) triples, and these related
  # discussions on naming:
  # - https://github.com/github/team-advisory-database/discussions/1934
  # - https://github.com/github/hydro-schemas/pull/1771#discussion_r629646985
  #
  # For purl types, we're only covering types our system "knows" about from here:
  # https://github.com/package-url/purl-spec/blob/master/PURL-TYPES.rst#github
  #
  # "githubactions" is provisional, not yet listed in PURL-TYPES, may be subject to change
  class PackageManager
    include EnumeratedType
    include SerializedType

    declare :unknown,  id: 0, human_name: "Unknown", purl_type: "unknown", dgp_ecosystem: :ECOSYSTEM_UNKNOWN
    declare :rubygems, id: 1, human_name: "RubyGems", purl_type: "gem"
    declare :npm,      id: 2, human_name: "NPM", purl_type: "npm", dgp_ecosystem: :ECOSYSTEM_NPM, supported_by_dgp: true
    declare :pip,      id: 3, human_name: "pip", purl_type: "pypi"
    declare :maven,    id: 4, human_name: "Maven", purl_type: "maven"
    declare :nuget,    id: 5, human_name: "NuGet", purl_type: "nuget"
    declare :composer, id: 6, human_name: "Composer", purl_type: "composer"
    declare :go,       id: 7, human_name: "Go modules", purl_type: "golang"
    declare :rust,     id: 8, human_name: "Rust", purl_type: "cargo"
    declare :actions,  id: 9, human_name: "Actions", purl_type: "githubactions", allows_named_versions: true, no_sub_dependencies: true
    declare :pub,      id: 10, human_name: "Pub", purl_type: "pub"
    declare :swift,    id: 11, human_name: "Swift", purl_type: "swift"
    # todo: check on twirp proto for actions
    # Keep in sync with proto/twirp/v1/dependency_graph_api.proto!
    # Keep in sync with https://github.com/github/airflow-sources/blob/master/dags/dependency_graph/sql/dependency_graph_fill.sql

    # Examples
    #   PackageManager[:npm].to_proto
    #   => 2
    def to_proto
      self.id
    end

    # Examples
    #   Types::PackageManager.supported_by_dgp
    #   => [#<Types::PackageManager:npm>]
    def self.supported_by_dgp
      Types::PackageManager.to_a.select { |pm| pm.supported_by_dgp }
    end

    # Examples
    #   PackageManager.from_proto(:PACKAGE_MANAGER_NPM)
    #   => #<Types::PackageManager:npm>
    def self.from_proto(value)
      self.by(:id, DependencyGraphAPI::V1::PackageManager.resolve(value))
    end

    def self.allows_named_versions?(pm)
      !pm.blank? && !!self.coerce(pm).allows_named_versions
    end

    def self.no_sub_dependencies?(pm)
      !pm.blank? && !!self.coerce(pm).no_sub_dependencies
    end
  end

  class Scope
    include EnumeratedType
    include SerializedType

    declare :runtime,     id: 1
    declare :development, id: 2
  end

  class Relationship
    include EnumeratedType
    include SerializedType

    declare :unknown, id: 0, human_name: "Unknown", dgp_relationship: :RELATIONSHIP_UNKNOWN
    declare :direct, id: 1, human_name: "Direct", dgp_relationship: :RELATIONSHIP_DIRECT
    declare :transitive, id: 2, human_name: "Transitive", dgp_relationship: :RELATIONSHIP_TRANSITIVE
  end

  class Manifest
    include EnumeratedType
    include SerializedType

    declare :unknown,           id: 0, human_name: "unknown", package_manager: PackageManager[:unknown]

    # rubygems
    declare :gemfile,           id: 1, human_name: "gemfile", package_manager: PackageManager[:rubygems]
    declare :gemfile_lock,      id: 2, human_name: "gemfile.lock", supersedes: self[:gemfile], package_manager: PackageManager[:rubygems], only_contains_pinned_deps: true
    declare :gemspec,           id: 3, human_name: "gemspec", package_manager: PackageManager[:rubygems]

    # npm
    declare :package_json,      id: 4,  human_name: "package.json", package_manager: PackageManager[:npm]
    declare :package_lock_json, id: 5,  human_name: "package-lock.json", supersedes: self[:package_json], package_manager: PackageManager[:npm], only_contains_pinned_deps: true
    declare :yarn_lock,         id: 14, human_name: "yarn.lock", supersedes: self[:package_json], package_manager: PackageManager[:npm], only_contains_pinned_deps: true
    declare :pnpm_lock,         id: 28, human_name: "pnpm-lock.yaml", supersedes: self[:package_json], package_manager: PackageManager[:npm], only_contains_pinned_deps: true
    declare :vendored_javascript_dependency, id: 17, human_name: "vendored javascript dependency", supported_vendored: true, package_manager: PackageManager[:npm]

    # pip
    declare :requirements_txt,  id: 6,  human_name: "requirements.txt", package_manager: PackageManager[:pip]
    declare :pipfile,           id: 7,  human_name: "pipfile", package_manager: PackageManager[:pip]
    declare :pipfile_lock,      id: 8,  human_name: "pipfile.lock", supersedes: self[:pipfile], package_manager: PackageManager[:pip], only_contains_pinned_deps: true
    declare :setup_py,          id: 9,  human_name: "setup.py", package_manager: PackageManager[:pip]
    declare :pyproject_toml,    id: 19, human_name: "pyproject.toml", package_manager: PackageManager[:pip]
    declare :poetry_lock,       id: 23, human_name: "poetry.lock", supersedes: self[:pyproject_toml], package_manager: PackageManager[:pip], only_contains_pinned_deps: true

    # maven
    declare :pom_xml,           id: 10, human_name: "pom.xml", package_manager: PackageManager[:maven]

    # nuget
    declare :nuspec,            id: 11, human_name: "nuspec", package_manager: PackageManager[:nuget]
    declare :msbuild,           id: 12, human_name: "msbuild", package_manager: PackageManager[:nuget]
    declare :package_config,    id: 13, human_name: "package.config", package_manager: PackageManager[:nuget]

    # composer
    declare :composer_json,     id: 16, human_name: "composer.json", package_manager: PackageManager[:composer]
    declare :composer_lock,     id: 15, human_name: "composer.lock", supersedes: self[:composer_json], package_manager: PackageManager[:composer], only_contains_pinned_deps: true

    # go
    declare :go_mod,            id: 18, human_name: "go.mod", package_manager: PackageManager[:go], only_contains_pinned_deps: true
    # id:20 was reserved for "go.sum" whose support stopped in March 2023.

    # rust
    declare :cargo_toml,        id: 21, human_name: "cargo.toml", package_manager: PackageManager[:rust]
    declare :cargo_lock,        id: 22, human_name: "cargo.lock", supersedes: self[:cargo_toml], package_manager: PackageManager[:rust], only_contains_pinned_deps: true

    # actions
    declare :workflow_yaml,     id: 24, human_name: "workflow.yaml", package_manager: PackageManager[:actions]

    # pub
    declare :pubspec_yaml,      id: 25, human_name: "pubspec.yaml", package_manager: PackageManager[:pub]
    declare :pubspec_lock,      id: 26, human_name: "pubspec.lock", supersedes: self[:pubspec_yaml], package_manager: PackageManager[:pub], only_contains_pinned_deps: true

    declare :package_resolved,  id: 27, human_name: "Package.resolved", package_manager: PackageManager[:swift]

    # next id: 29

    #TODO: add a superseded_by column to manifests so we know if a manifest is eg a Gemfile
    # that's superseded by a lock.
    # Backfill data, handle all edge cases
    # Returns the manifest types that are superseded by others
    def self.superseded
      self.map(&:supersedes).compact.uniq
    end

    def supersedes?(other)
      Array(supersedes).include?(self.class.coerce(other))
    end

    def supported_vendored?
      !!supported_vendored
    end

    def self.superseding_cases
      @superseding_cases ||= Types::Manifest.filter_map do |manifest_type|
        superseded_by = Types::Manifest.filter { |m| m.supersedes == manifest_type }

        unless superseded_by.empty?
          superseded_by_ids_list = superseded_by.map(&:id)
          [manifest_type.id, superseded_by_ids_list]
        end
      end.to_h
    end
  end
end
