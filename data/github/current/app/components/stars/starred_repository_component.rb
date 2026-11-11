# typed: true
# frozen_string_literal: true

module Stars
  class StarredRepositoryComponent < ApplicationComponent
    DEFAULT_CONTEXT = :user_list
    CONTEXTS = %i[user_list].freeze

    def initialize(repository:, can_sponsor:, is_sponsoring:, context: DEFAULT_CONTEXT)
      @repository = repository
      @can_sponsor = can_sponsor
      @is_sponsoring = is_sponsoring
      @context = fetch_or_fallback(CONTEXTS, context, DEFAULT_CONTEXT)
    end

    private

    attr_reader :repository

    def render?
      repository.present?
    end

    def star_button_context
      return "user_list" if @context == :user_list
      "other"
    end

    def sponsor_button_location
      if @context == :user_list
        sponsoring? ? :USER_LIST_SPONSORING : :USER_LIST_SPONSOR
      else
        :UNKNOWN
      end
    end

    def can_sponsor?
      @can_sponsor
    end

    def sponsoring?
      @is_sponsoring
    end

    def show_sponsor_button?
      GitHub.sponsors_enabled? && can_sponsor?
    end

    delegate :owner, to: :repository

    memoize def short_description_html
      repository.short_description_html
    end
  end
end
