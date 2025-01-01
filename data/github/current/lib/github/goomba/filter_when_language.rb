# typed: true
# frozen_string_literal: true

require "linguist"

module GitHub::Goomba
  class FilterWhenLanguage
    def self.dogstats_key
      @dogstats_key ||= GitHub::Goomba::Filter.name_to_dogstats_key(name)
    end

    def initialize(language, filter)
      @language = language
      @filter = filter
    end

    def feature_flags
      @filter.feature_flags
    end

    def enabled?(context)
      return false unless @filter.enabled?(context)
      path = context[:name] || context[:path]
      return false if path.nil? || path.empty?
      languages = Linguist::Language.find_by_filename(path)
      languages = Linguist::Language.find_by_extension(path) if languages.empty?
      languages.any? { |l| l.name == @language }
    end

    def new(*args)
      @filter.new(*args)
    end
  end
end
