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
    return "nextjs" if has_nextjs_indicators?(repository)
    return "nuxtjs" if has_nuxtjs_indicators?(repository)
    return "gatsby" if has_gatsby_indicators?(repository)
    return "eleventy" if has_eleventy_indicators?(repository)
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
    repository_has_file?(repository, "vite.config.js") ||
      repository_has_file?(repository, "vite.config.ts") ||
      repository_has_file?(repository, "vite.config.mjs")
  end

  sig { params(repository: T.untyped).returns(T::Boolean) }
  def has_astro_indicators?(repository)
    repository_has_file?(repository, "astro.config.mjs") ||
      repository_has_file?(repository, "astro.config.js") ||
      repository_has_file?(repository, "astro.config.ts")
  end

  sig { params(repository: T.untyped).returns(T::Boolean) }
  def has_nextjs_indicators?(repository)
    repository_has_file?(repository, "next.config.js") ||
      repository_has_file?(repository, "next.config.mjs") ||
      repository_has_file?(repository, "next.config.ts")
  end

  sig { params(repository: T.untyped).returns(T::Boolean) }
  def has_nuxtjs_indicators?(repository)
    repository_has_file?(repository, "nuxt.config.js") ||
      repository_has_file?(repository, "nuxt.config.mjs") ||
      repository_has_file?(repository, "nuxt.config.ts")
  end

  sig { params(repository: T.untyped).returns(T::Boolean) }
  def has_gatsby_indicators?(repository)
    repository_has_file?(repository, "gatsby-config.js") ||
      repository_has_file?(repository, "gatsby-config.mjs") ||
      repository_has_file?(repository, "gatsby-config.ts")
  end

  sig { params(repository: T.untyped).returns(T::Boolean) }
  def has_eleventy_indicators?(repository)
    repository_has_file?(repository, ".eleventy.js") ||
      repository_has_file?(repository, "eleventy.config.js") ||
      repository_has_file?(repository, "eleventy.config.mjs") ||
      repository_has_file?(repository, "eleventy.config.cjs")
  end

  sig { params(repository: T.untyped, filename: String).returns(T::Boolean) }
  def repository_has_file?(repository, filename)
    repository.includes_file?(filename)
  rescue GitRPC::Error, Rugged::Error
    false
  end
end
