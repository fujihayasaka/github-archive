# typed: true
# frozen_string_literal: true

module StackDetectionHelper
  # Detects the stack framework and package manager for a repository
  #
  # @param repository [Repository] The repository to analyze
  # @return [Hash, nil] Hash with framework and package_manager info, or nil if no stack detected
  sig { params(repository: T.untyped).returns(T::Hash[Symbol, T.nilable(String)]) }
  def detect_stack(repository)
    { framework: detect_framework(repository), package_manager: detect_package_manager(repository) }
  end

  private

  sig { params(repository: T.untyped).returns(T.nilable(String)) }
  def detect_framework(repository)
    return "vite" if has_vite_indicators?(repository)
    return "astro" if has_astro_indicators?(repository)
    nil
  end

  sig { params(repository: T.untyped).returns(T.nilable(String)) }
  def detect_package_manager(repository)
    return "yarn" if repository_has_file?(repository, "yarn.lock")
    return "pnpm" if repository_has_file?(repository, "pnpm-lock.yaml")
    return "npm" if repository_has_file?(repository, "package.json")
    nil # No package manager detected
  end

  sig { params(repository: T.untyped).returns(T::Boolean) }
  def has_vite_indicators?(repository)
    # Strong indicators: Vite config files
    return true if repository_has_file?(repository, "vite.config.js")
    return true if repository_has_file?(repository, "vite.config.ts")
    return true if repository_has_file?(repository, "vite.config.mjs")

    # Fallback: Check package.json for vite dependency
    package_json_has_dependency?(repository, "vite")
  end

  sig { params(repository: T.untyped).returns(T::Boolean) }
  def has_astro_indicators?(repository)
    # Strong indicators: Astro config files
    return true if repository_has_file?(repository, "astro.config.mjs")
    return true if repository_has_file?(repository, "astro.config.js")
    return true if repository_has_file?(repository, "astro.config.ts")

    # Fallback: Check package.json for astro dependencies
    package_json_has_dependency?(repository, "@astrojs/")
  end

  sig { params(repository: T.untyped, filename: String).returns(T::Boolean) }
  def repository_has_file?(repository, filename)
    begin
      repository.includes_file?(filename)
    rescue GitRPC::Error, Rugged::Error
      false
    end
  end

  sig { params(repository: T.untyped, dependency_name: String).returns(T::Boolean) }
  def package_json_has_dependency?(repository, dependency_name)
    begin
      return false unless repository_has_file?(repository, "package.json")

      # TODO: This is a simplified implementation that doesn't actually parse package.json
      # For now, we rely on config file detection as the primary indicator
      # In the future, this could be enhanced to actually read and parse package.json
      # to check for dependencies like "vite" or packages starting with "@astrojs/"
      true
    rescue GitRPC::Error, Rugged::Error
      false
    end
  end
end
