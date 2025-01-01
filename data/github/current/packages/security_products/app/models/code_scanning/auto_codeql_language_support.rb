# typed: strict
# frozen_string_literal: true

module CodeScanning
  # AutoCodeqlLanguageSupport provides a way to determine which languages are supported by CodeQL for a given repository.
  # It is primarily used by Default setup to determine which languages to enable CodeQL analysis for, but
  # we also use it to determine which languages to use when generating a new workflow file for CodeQL.
  class AutoCodeqlLanguageSupport
    sig { returns(Repository) }
    attr_reader :repository

    sig do
      params(
        repository: ::Repository
      ).void
    end
    def initialize(repository)
      @repository = repository
      # We intentionally use `language_analysis` here rather than `repository.language_percentages` directly.
      # This is because `repository.language_percentages` has caching issues that cause the reported languages to be incorrect,
      # particularly locally and on GitHub Enterprise.
      @repo_detected_languages = T.let(repository.language_analysis.language_percentages.map(&:first), T::Array[String])

      # Linguist doesn't detect Actions code, so we need to check for it separately.
      if has_actions?
        @repo_detected_languages.append("actions")
      end
      @supported_languages_internal = T.let(nil, T.nilable(T::Array[T::untyped]))
    end

    # supported_languages returns the languages that are supported by CodeQL for this repository.
    sig { returns(T::Array[String]) }
    def supported_languages
      supported_languages_internal.map(&:canonical_name)
    end

    sig do
      params(
        language_list: T::Array[String],
      ).returns(T::Boolean)
    end
    def non_repo_languages_present?(language_list)
      language_list.any? do |language|
        lang_obj = get_language(language)
        supported_languages_internal.exclude?(lang_obj)
      end
    end

    sig do
      params(
        language_list: T::Array[String],
      ).returns(T::Array[String])
    end
    def canonical_names(language_list)
      language_list.each_with_object([]) do |language, canonical_names|
        lang_obj = get_language(language)
        canonical_names.push(lang_obj.canonical_name) if lang_obj
      end
    end

    sig { returns(T::Hash[String, T::Array[String]]) }
    def display_names
      # Each canonical language can potentially be associated to more than one display name,
      # e.g. if the repo contains both Java and Kotlin.
      @repo_detected_languages.each_with_object({}) do |name, display_names|
        language = get_language(name.downcase)
        next if language.nil? # Skip if language is not supported by Default Setup

        canonical_language = language.canonical_name
        display_names[canonical_language] ||= []
        display_names[canonical_language] << name
      end
    end

    sig { returns(T::Boolean) }
    def has_kotlin?
      @repo_detected_languages.include?("Kotlin")
    end

    # detected_codeql_languages_build_mapping returns a mapping of languages to their build mode.
    # This is used to generate the `$codeql-languages-matrix` in a CodeQL workflow file.
    sig { returns(T::Hash[Symbol, String]) }
    def detected_codeql_languages_build_mapping
      matrix = {}
      supported_languages_internal.each do |l|
        matrix[l.canonical_name.to_sym] = l.build_mode
      end

      # Build mode none is not supported for Kotlin, so we need to disambiguate the Java and not Kotlin case.
      if matrix[:"java-kotlin"] && !has_kotlin?
        matrix[:"java-kotlin"] = "none # This mode only analyzes Java. Set this to 'autobuild' or 'manual' to analyze Kotlin too."
      end
      matrix
    end

    # detected_codeql_languages_string returns a string of supported languages.
    # This is used to generate the `detected-codeql-languages` in a CodeQL workflow file.
    sig { returns(String) }
    def detected_codeql_languages_string
      supported_languages.sort.map { |lang| "'#{lang}'" }.join(", ")
    end

    # all_codeql_languages_string returns a string of ALL languages CodeQL understand, independently of whether they appear in the repo.
    # This is used to generate the `detected-codeql-languages` in a CodeQL workflow file.
    sig { returns(String) }
    def all_codeql_languages_string
      all_codeql_languages.map { |lang| "'#{lang}'" }.join(", ")
    end

    sig { returns(T::Array[String]) }
    def all_codeql_languages
      LANGUAGE_DATA.
        reject { |lang| lang.canonical_name == "rust" && !feature_enabled?(:codeql_action_rust_analysis) }.
        sort_by(&:canonical_name).map(&:canonical_name)
    end

    private

    class CodeqlLanguageEntry < T::Struct
      const :canonical_name, String
      const :variants, T::Array[String]
      const :build_mode, String
    end

    LANGUAGE_DATA = T.let([
      CodeqlLanguageEntry.new(canonical_name: "actions", variants: ["actions"], build_mode: "none"),
      CodeqlLanguageEntry.new(canonical_name: "c-cpp", variants: ["c-cpp", "c", "cpp", "c++"], build_mode: "autobuild"),
      CodeqlLanguageEntry.new(canonical_name: "csharp", variants: ["csharp", "c#"], build_mode: "none"),
      CodeqlLanguageEntry.new(canonical_name: "go", variants: ["go"], build_mode: "autobuild"),
      CodeqlLanguageEntry.new(canonical_name: "java-kotlin", variants: %w[java-kotlin java kotlin], build_mode: "autobuild"),
      CodeqlLanguageEntry.new(canonical_name: "javascript-typescript", variants: %w[javascript-typescript javascript typescript], build_mode: "none"),
      CodeqlLanguageEntry.new(canonical_name: "python", variants: ["python"], build_mode: "none"),
      CodeqlLanguageEntry.new(canonical_name: "ruby", variants: ["ruby"], build_mode: "none"),
      CodeqlLanguageEntry.new(canonical_name: "rust", variants: ["rust"], build_mode: "none"),
      CodeqlLanguageEntry.new(canonical_name: "swift", variants: ["swift"], build_mode: "autobuild"),
    ].freeze, T::Array[CodeqlLanguageEntry])

    sig { returns(T::Boolean) }
    def has_actions?
      repository.workflows.map(&:present_in_default_branch).any?
    end

    sig { params(feature_name: Symbol).returns(T::Boolean) }
    def feature_enabled?(feature_name)
      repository.feature_flag_enabled?(feature_name, default: false) || !!repository.owner&.feature_flag_enabled?(feature_name, default: false)
    end

    sig do
      params(
      language_name: ::String
      ).returns(T.nilable(CodeqlLanguageEntry))
    end
    def get_language(language_name)
      LANGUAGE_DATA.find do |language|
        language.variants.include?(language_name) &&
          # only consider rust if the feature flag is enabled
          (language.canonical_name != "rust" || feature_enabled?(:codeql_action_rust_analysis))
      end
    end

    sig { returns(T::Array[CodeqlLanguageEntry]) }
    def supported_languages_internal
      @supported_languages_internal ||= @repo_detected_languages.each_with_object([]) do |language, out|
        lang_obj = get_language(language.downcase)
        next if lang_obj.nil? # Skip if language is not supported by CodeQL
        out.push(lang_obj) unless out.include?(lang_obj)
      end
    end
  end
end
