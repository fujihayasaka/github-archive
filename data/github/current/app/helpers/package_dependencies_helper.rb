# typed: true
# frozen_string_literal: true

module PackageDependenciesHelper
  # Define a human-readable label for each package ecosystem and a relevant color to be displayed on the Packages Dashboard.
  # This should match the types defined in github/dependency-graph-api/app/models/types.rb
  #
  ECOSYSTEMS = {
    MAVEN: { color: Linguist::Language.find_by_name("Java").color, label: "Maven" },
    NPM: { color: Linguist::Language.find_by_name("Javascript").color, label: "npm" },
    NUGET: { color: "#2B9CDF", label: "NuGet" }, # Color is from Nuget logo - https://commons.wikimedia.org/wiki/File:NuGet_project_logo.svg
    PIP: { color: Linguist::Language.find_by_name("Python").color, label: "pip" },
    RUBYGEMS: { color: Linguist::Language.find_by_name("Ruby").color, label: "RubyGems" },
    COMPOSER: { color: Linguist::Language.find_by_name("PHP").color, label: "Composer" },
    GO: { color: Linguist::Language.find_by_name("Go").color, label: "Go" },
    ACTIONS: { color: "#0366D6", label: "GitHub Actions" }, # color is predominately used in Actions UI - see app/models/repository_action.rb for example
    RUST: { color: Linguist::Language.find_by_name("Rust").color, label: "Cargo" },
    PUB: { color: Linguist::Language.find_by_name("Dart").color, label: "Pub" },
    SWIFT: { color: Linguist::Language.find_by_name("Swift").color, label: "Swift" },
  }.freeze

  def ecosystems(&block)
    ECOSYSTEMS.keys.sort.each(&block)
  end

  # Public: Return human-readable label for a package manager
  #
  def ecosystem_label(ecosystem)
    ECOSYSTEMS.dig(ecosystem.to_sym, :label) ||
      Linguist::Language.find_by_name(ecosystem.to_s)&.name ||
      ecosystem.to_s.humanize
  end

  # Public: Return a hex color for a package manager
  #
  def ecosystem_color(ecosystem)
    ECOSYSTEMS.dig(ecosystem.to_sym, :color) ||
      Linguist::Language.find_by_name(ecosystem.to_s)&.color ||
      "#6A737D" # --color-scale-gray-5
  end

  # Helper to get the readme to render for a manifest.
  # Defaults to the readme in the directory that the manifest is in and falls
  # back to the repository's preferred readme.
  #
  def manifest_readme(repository, manifest_path = nil)
    if manifest_path.present?
      directory_path = File.dirname(manifest_path)
      if directory_path != "." && repository.includes_directory?(directory_path)
        directory = repository.directory(repository.default_oid, directory_path)
      end
    end

    directory&.preferred_readme || repository.preferred_readme
  end
end
