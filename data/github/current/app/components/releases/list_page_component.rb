# typed: true
# frozen_string_literal: true

module Releases
  class ListPageComponent < ApplicationComponent
    include GitHub::Memoizer

    def initialize(results, current_repository, current_user, filter_phrase, page_title: "", expand_all: false)
      @results = results
      @current_user = current_user
      @current_repository = current_repository
      @filter_phrase = filter_phrase
      @page_title = page_title
      @expand_all = expand_all
    end

    attr_reader :releases, :current_repository, :current_user, :results, :filter_phrase, :expand_all, :page_title

    def writable?
      @writable if defined?(@writable)
      @writable = @current_repository.writable? && @current_repository.pushable_by?(@current_user)
    end

    def latest_release
      @latest_release if defined?(@latest_release)
      @latest_release = Releases::Public.latest_for_repository(@current_repository, @current_user)
    end

    def releases_found?
      filter_phrase.present? && !results.empty?
    end

    memoize def screen_reader_search_results
      # We will use aria live to announce the search results but only if a query parameter is present
      if filter_phrase.present?
        if releases_found?
          "#{@results.count} #{'release'.pluralize(@results.count)} found"
        else
          "no releases found"
        end
      else
        nil
      end
    end
  end
end
