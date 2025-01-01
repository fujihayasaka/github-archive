# typed: true
# frozen_string_literal: true

module Api::Serializer
  class LegacySearchOptions
    def self.from(options)
      legacy_options.from(options)
    end

    def self.fill(options)
      legacy_options.fill(options)
    end

    def self.legacy_options
      @legacy_options ||= GitHub::Options.new(:search_hit, :score, :accept_mime_types, :global_id_selection, :api_version) do
        include Api::SerializerOptionsMimeTypes
      end
    end

    def self.score
      @score ||= legacy_options[:score].to_f
    end

    def self.search_hit
      legacy_options[:search_hit] ||= {}
    end
  end
end
