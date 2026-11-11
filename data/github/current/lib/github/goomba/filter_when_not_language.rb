# typed: true
# frozen_string_literal: true

require "linguist"

module GitHub::Goomba
  class FilterWhenNotLanguage
    def self.dogstats_key
      @dogstats_key ||= GitHub::Goomba::Filter.name_to_dogstats_key(name)
    end

    def initialize(language, filter)
      @filter = filter
      @language = language.to_s
    end

    def feature_flags
      @filter.feature_flags
    end

    def enabled?(context)
      return false unless @filter.enabled?(context)
      path = context[:name] || context[:path]
      return true if path.blank?

      languages = Linguist::Language.find_by_filename(path)
      languages = Linguist::Language.find_by_extension(path) if languages.empty?
      if !languages.any? { |l| l.name == @language }
        true
      else
        false
      end
    end

    def new(*args)
      @filter.new(*args)
    end
  end
end
