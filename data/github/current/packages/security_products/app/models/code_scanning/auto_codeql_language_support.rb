# typed: strict
# frozen_string_literal: true

module CodeScanning
  class AutoCodeqlLanguageSupport
    extend T::Sig

    sig { returns(Repository) }
    attr_reader :repository

    sig do
      params(
        repository: ::Repository
      ).void
    end
    def initialize(repository)
      @repository = repository
      @repo_detected_languages = T.let(repository.detected_languages, T::Array[String])
      @supported_languages_internal = T.let(nil, T.nilable(T::Array[T::untyped]))
    end

    sig { returns(T::Array[String]) }
    def supported_languages
      supported_languages_internal.map { |language| language.fetch(:canonical_name) }
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
        canonical_names.push(lang_obj.fetch(:canonical_name)) if lang_obj
      end
    end

    sig { returns(T::Hash[String, T::Array[String]]) }
    def display_names
      # Each canonical language can potentially be associated to more than one display name,
      # e.g. if the repo contains both Java and Kotlin.
      @repo_detected_languages.each_with_object({}) do |name, display_names|
        language = get_language(name.downcase)
        next if language.nil? # Skip if language is not supported by Default Setup

        canonical_language = language[:canonical_name]
        display_names[canonical_language] ||= []
        display_names[canonical_language] << name
      end
    end

    sig { returns(T::Boolean) }
    def has_kotlin?
      @repo_detected_languages.include?("Kotlin")
    end

    private

    LANGUAGE_DATA = T.let([
      { canonical_name: "c-cpp", variants: ["c-cpp", "c", "cpp", "c++"] },
      { canonical_name: "csharp", variants: ["csharp", "c#"] },
      { canonical_name: "go", variants: ["go"] },
      { canonical_name: "java-kotlin", variants: %w[java-kotlin java kotlin] },
      { canonical_name: "javascript-typescript", variants: %w[javascript-typescript javascript typescript] },
      { canonical_name: "python", variants: ["python"] },
      { canonical_name: "ruby", variants: ["ruby"] },
      { canonical_name: "swift", variants: ["swift"] },
    ].freeze, T::Array[T::untyped])

    sig { returns(T::Array[T.untyped]) }
    def language_data
      LANGUAGE_DATA
    end

    sig do
      params(
        language_name: ::String
      ).returns(T::untyped)
    end
    def get_language(language_name)
      language_data.find { |language| language.fetch(:variants).include?(language_name) }
    end

    sig { returns(T::Array[T::untyped]) }
    def supported_languages_internal
      @supported_languages_internal ||= @repo_detected_languages.each_with_object([]) do |language, out|
        lang_obj = get_language(language.downcase)
        next if lang_obj.nil? # Skip if language is not supported by Default Setup
        out.push(lang_obj) unless out.include?(lang_obj)
      end
    end
  end
end
