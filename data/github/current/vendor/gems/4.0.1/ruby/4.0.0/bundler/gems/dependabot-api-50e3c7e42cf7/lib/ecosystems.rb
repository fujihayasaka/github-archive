# frozen_string_literal: true

module Languages
  ALL = [
    BAZEL = "bazel",
    CPP = "cpp",
    DART = "dart",
    DEVCONTAINERS = "devcontainers",
    DOCKER = "docker",
    DOCKER_COMPOSE = "docker_compose",
    DOTNET_SDK = "dotnet_sdk",
    DOTNET = "dotnet",
    ELIXER = "elixir",
    ELM = "elm",
    GIT = "git",
    GITHUB_ACTIONS = "github_actions",
    GO = "go",
    JAVA = "java",
    JAVASCRIPT = "javascript",
    OPENTOFU = "opentofu",
    PHP = "php",
    PYTHON = "python",
    RUBY = "ruby",
    RUST = "rust",
    SWIFT = "swift",
    TERRAFORM = "terraform",
    HELM = "helm",
    JULIA = "julia",
    PRE_COMMIT = "pre_commit",
  ].freeze
end

module PackageManagers
  ALL = [
    BAZEL = "bazel",
    BUN = "bun",
    BUNDLER = "bundler",
    CARGO = "cargo",
    COMPOSER = "composer",
    CONDA = "conda",
    DEVCONTAINERS = "devcontainers",
    DOCKER = "docker",
    DOCKER_COMPOSE = "docker_compose",
    DOTNET_SDK = "dotnet_sdk",
    ELM = "elm",
    GITHUB_ACTIONS = "github_actions",
    GO_MODULES = "go_modules",
    GRADLE = "gradle",
    HELM = "helm",
    HEX = "hex",
    JULIA = "julia",
    MAVEN = "maven",
    NPM_AND_YARN = "npm_and_yarn",
    NUGET = "nuget",
    OPENTOFU = "opentofu",
    PIP = "pip",
    PRE_COMMIT = "pre_commit",
    PUB = "pub",
    RUST_TOOLCHAIN = "rust_toolchain",
    SUBMODULES = "submodules",
    SWIFT = "swift",
    TERRAFORM = "terraform",
    UV = "uv",
    VCPKG = "vcpkg",
  ].freeze
end

module Advisorydb
  class PackageManagerNotFoundError < StandardError; end
  class EcosystemrNotFoundError < StandardError; end

  PACKAGE_MANAGERS = {
    PackageManagers::BUNDLER => :ECOSYSTEM_RUBYGEMS,
    PackageManagers::COMPOSER => :ECOSYSTEM_COMPOSER,
    PackageManagers::NPM_AND_YARN => :ECOSYSTEM_NPM,
    PackageManagers::PIP => :ECOSYSTEM_PIP,
    PackageManagers::MAVEN => :ECOSYSTEM_MAVEN,
    PackageManagers::NUGET => :ECOSYSTEM_NUGET,
    PackageManagers::GO_MODULES => :ECOSYSTEM_GO,
    PackageManagers::CARGO => :ECOSYSTEM_RUST,
    PackageManagers::GITHUB_ACTIONS => :ECOSYSTEM_ACTIONS,
    PackageManagers::HEX => :ECOSYSTEM_ERLANG,
    PackageManagers::PUB => :ECOSYSTEM_PUB,
    PackageManagers::SWIFT => :ECOSYSTEM_SWIFT,
    PackageManagers::BUN => :ECOSYSTEM_BUN,
    PackageManagers::DOCKER_COMPOSE => :ECOSYSTEM_DOCKER_COMPOSE,
    PackageManagers::UV => :ECOSYSTEM_UV,
    PackageManagers::HELM => :ECOSYSTEM_HELM,
    PackageManagers::CONDA => :ECOSYSTEM_CONDA,
    PackageManagers::JULIA => :ECOSYSTEM_JULIA,
  }.freeze

  def self.to_advisorydb_ecosystem(package_manager)
    PACKAGE_MANAGERS.fetch(package_manager) do
      raise EcosystemrNotFoundError, "Ecosystem for package manager #{package_manager} not found"
    end
  end

  ECOSYSTEMS = PACKAGE_MANAGERS.invert.freeze

  def self.to_package_manager(ecosystem)
    ECOSYSTEMS.fetch(ecosystem.to_sym) do
      raise PackageManagerNotFoundError, "Package manager for ecosystem #{ecosystem} not found"
    end
  end
end

module Ecosystems
  class PackageManagerNotFoundError < StandardError; end

  BETA = [
    PackageManagers::PRE_COMMIT,
  ].freeze

  PACKAGE_MANAGER_LANGUAGE_MAPPING = {
    PackageManagers::BAZEL => Languages::BAZEL,
    PackageManagers::BUN => Languages::JAVASCRIPT,
    PackageManagers::BUNDLER => Languages::RUBY,
    PackageManagers::CARGO => Languages::RUST,
    PackageManagers::COMPOSER => Languages::PHP,
    PackageManagers::CONDA => Languages::PYTHON,
    PackageManagers::DEVCONTAINERS => Languages::DEVCONTAINERS,
    PackageManagers::DOCKER => Languages::DOCKER,
    PackageManagers::DOCKER_COMPOSE => Languages::DOCKER_COMPOSE,
    PackageManagers::DOTNET_SDK => Languages::DOTNET_SDK,
    PackageManagers::ELM => Languages::ELM,
    PackageManagers::GITHUB_ACTIONS => Languages::GITHUB_ACTIONS,
    PackageManagers::GO_MODULES => Languages::GO,
    PackageManagers::GRADLE => Languages::JAVA,
    PackageManagers::HELM => Languages::HELM,
    PackageManagers::HEX => Languages::ELIXER,
    PackageManagers::JULIA => Languages::JULIA,
    PackageManagers::MAVEN => Languages::JAVA,
    PackageManagers::NPM_AND_YARN => Languages::JAVASCRIPT,
    PackageManagers::NUGET => Languages::DOTNET,
    PackageManagers::OPENTOFU => Languages::OPENTOFU,
    PackageManagers::PIP => Languages::PYTHON,
    PackageManagers::PRE_COMMIT => Languages::PRE_COMMIT,
    PackageManagers::PUB => Languages::DART,
    PackageManagers::RUST_TOOLCHAIN => Languages::RUST,
    PackageManagers::SUBMODULES => Languages::GIT,
    PackageManagers::SWIFT => Languages::SWIFT,
    PackageManagers::TERRAFORM => Languages::TERRAFORM,
    PackageManagers::UV => Languages::PYTHON,
    PackageManagers::VCPKG => Languages::CPP,
  }.freeze

  LANGUAGE_PACKAGE_MANAGER_MAPPING = PACKAGE_MANAGER_LANGUAGE_MAPPING.each_with_object({}) do |(manager, lang), hsh|
    hsh[lang] ||= []
    hsh[lang] << manager
  end.freeze

  def self.language_for_package_manager(package_manager)
    PACKAGE_MANAGER_LANGUAGE_MAPPING.fetch(package_manager.to_s)
  end

  def self.package_managers_for_language(language)
    LANGUAGE_PACKAGE_MANAGER_MAPPING.fetch(language.to_s)
  end

  def self.beta?(package_manager)
    BETA.include?(package_manager)
  end
end
