# typed: true
# frozen_string_literal: true

module Discussions
  class IndexHeadingComponent < ApplicationComponent
    extend T::Sig

    sig { params(repository: Repository, category_slug: T::nilable(String)).void }
    def initialize(repository:, category_slug:)
      @repository = repository
      @category_slug = category_slug
    end

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(T::nilable(String)) }
    attr_reader :category_slug

    def call
      render(Primer::Beta::Heading.new(tag: :h1, classes: "sr-only")) { heading }
    end

    private

    sig { returns(String) }
    memoize def heading
      heading_array = [
        repository.owner,
        repository.name,
        category_slug.present? ? T.must(category_slug).humanize : nil,
        "Discussions"
      ].compact
      heading_array.to_sentence(words_connector: " ", last_word_connector: " ")
    end
  end
end
