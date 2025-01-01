# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Base class for input and text filters. See InputFilter and TextFilter for
  # further details.
  #
  # The context Hash passes options to filters and should not be changed in
  # place.  A Result Hash allows filters to make extracted information
  # available to the caller and is mutable.  A Scratch Hash allows passing
  # information between filters but is not exposed to callers.
  #
  # Each filter may define additional options and output values. See the class
  # docs for more info.
  class Filter
    def initialize(context = nil, result = nil, scratch = nil)
      @context = context || {}
      @result = result || {}
      @scratch = scratch || {}
    end

    # Public: Returns an array of feature flag symbols and is used to preload
    # feature flags when a pipeline is executed.
    def self.feature_flags
      []
    end

    # Public: Returns whether the filter should be used. Typically queries the
    # context hash and application configuration to decide.
    def self.enabled?(context)
      true
    end

    # Public: Returns the cache key for the filter which can be altered based on
    # the passed context object.
    def self.cache_key(context)
      false
    end

    def self.dogstats_key
      @dogstats_key ||= name_to_dogstats_key(name)
    end

    def self.name_to_dogstats_key(name)
      name.gsub(/#{GitHub::Goomba.name}(::)?/, "").gsub("::", "/")
    end

    # Public: Returns a simple Hash used to pass extra information into filters
    # and also to allow filters to make extracted information available to the
    # caller.
    attr_reader :context

    # Public: Returns a Hash used to allow filters to pass back information
    # to callers of the various Pipelines.  This can be used for
    # #mentioned_users, for example.
    attr_reader :result

    # Internal: Returns a Hash used to pass information between filters.
    attr_reader :scratch

    # Public: Returns the entity within the context, or nil.
    def entity
      context[:entity]
    end

    # Public: Returns the entity within the context if it's a Repository object.
    def repository
      if entity.is_a? GitHub::Unsullied::Wiki
        return entity.repository if entity.repository.present?
      end
      entity if entity.is_a? Repository
    end

    private

    # Returns a safe HTML String if the result Hash indicates that the HTML has been previously sanitized.
    # When HTML has not been sanitized the string will be HTML escaped and shown to users as text content
    # rather than HTML elements by Rails helpers and ERB interpolation.
    def safe_html_if_sanitized(html)
      return html unless result[:html_safe]
      html.html_safe # rubocop:disable Rails/OutputSafety
    end
  end
end
