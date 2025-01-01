# typed: true
# frozen_string_literal: true

module Elastomer

  # This mondule contains the configuration settings for the analyzers
  # used across several of our indices.
  module Analyzers
    extend self
    extend T::Sig

    TEXTY_TOKEN_FILTERS = %w[standard lowercase asciifolding keyword_repeat kstem texty_unique_words texty_words]
    TEXTY_SEARCH_TOKEN_FILTERS = %w[standard lowercase asciifolding]

    # Add the texty analyzer to the index settings. This analyzer is suitable
    # for general English text tokenization.
    #
    # settings - The index settings Hash
    #
    # Returns the index settings Hash passed in.
    sig do
      params(
        settings: T::Hash[T.untyped, T.untyped],
        force_es_5: T::Boolean
      )
      .returns(T::Hash[T.untyped, T.untyped])
    end
    def configure_texty(settings, force_es_5: false)
      analysis = settings[:analysis] ||= {}

      analyzer = analysis[:analyzer] ||= {}
      analyzer.merge!({
        texty: {
          tokenizer: "standard",
          filter: token_filters(TEXTY_TOKEN_FILTERS, force_es_5),
        },
        texty_search: {
          tokenizer: "standard",
          filter: token_filters(TEXTY_SEARCH_TOKEN_FILTERS, force_es_5),
        },
        publisher_search: {
          tokenizer: "keyword",
          filter: "lowercase"
        }
      })

      filter = analysis[:filter] ||= {}
      filter.merge!({
        texty_unique_words: {
          type: "unique",
          only_on_same_position: true,
        },
        texty_words: {
          type: "word_delimiter",
          generate_word_parts: true,   # If true causes parts of words to be generated: “PowerShot” => “Power” “Shot”. Defaults to true.
          generate_number_parts: true,   # If true causes number subwords to be generated: “500-42” => “500” “42”. Defaults to true.
          catenate_words: false,  # If true causes maximum runs of word parts to be catenated: “wi-fi” => “wifi”. Defaults to false.
          catenate_numbers: false,  # If true causes maximum runs of number parts to be catenated: “500-42” => “50042”. Defaults to false.
          catenate_all: false,  # If true causes all subword parts to be catenated: “wi-fi-4000” => “wifi4000”. Defaults to false.
          split_on_case_change: false,  # If true causes “PowerShot” to be two tokens; (“Power-Shot” remains two parts regards). Defaults to true.
          preserve_original: true,   # If true includes original words in subwords: “500-42” => “500” “42” “500-42”. Defaults to false.
          split_on_numerics: false,  # If true causes “j2se” to be three tokens; “j” “2” “se”. Defaults to true.
          stem_english_possessive: false,   # If true causes trailing “’s” to be removed for each subword: “O’Neil’s” => “O”, “Neil”. Defaults to true.
        },
      })

      settings
    end

    # ES8-COMPATIBILITY: standard token filter is deprecated, but we need to keep this until
    # we upgrade ES8 on GHES or until RMS Packages gets a repair job
    private def token_filters(filters, force_es_5)
      if !force_es_5
        filters.reject { |f| f == "standard" }
      else
        filters
      end
    end

    # Add the code and code_search analyzers to the index settings. These
    # analyzers are for source code tokenization.
    #
    # settings - The index settings Hash
    #
    # Returns the index settings Hash passed in.
    def configure_code(settings)
      analysis = settings[:analysis] ||= {}

      analyzer = analysis[:analyzer] ||= {}
      analyzer.merge!({
        filename: {
          type: "custom",
          tokenizer: "keyword",
          filter: %w[code lowercase],
        },
        code: {
          type: "custom",
          tokenizer: "code",
          filter: %w[code lowercase skipsize],
        },
        code_search: {
          type: "custom",
          tokenizer: "code",
          filter: %w[lowercase skipsize],
        },
      })

      tokenizer = analysis[:tokenizer] ||= {}
      tokenizer[:code] = {
        type: "pattern",
        pattern: %q_[.,:;/\\\\`'"=*!@?#$&+^|~<>(){}\[\]\s]_,
        # here are the characters we are splitting on in non-regex form
        # . , : ; / \ ` ' " = * ! @ ? # $ & + ^ | ~ < > ( ) { } [ ] [:space:]
      }

      filter = analysis[:filter] ||= {}
      filter.merge!({
        code: {
          type: "word_delimiter",
          generate_word_parts: true,
          generate_number_parts: true,
          catenate_words: false,
          catenate_numbers: false,
          catenate_all: false,
          split_on_case_change: true,
          preserve_original: true,
          split_on_numerics: false,
          stem_english_possessive: false,
        },
        skipsize: {
          type: "length",
          min: 2,
          max: 128,
        },
      })

      settings
    end
  end
end
