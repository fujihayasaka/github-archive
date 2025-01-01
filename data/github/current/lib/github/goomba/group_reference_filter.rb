# typed: false
# frozen_string_literal: true

module GitHub::Goomba
  class GroupReferenceFilter < GithubReferenceFilter
    REFERENCE_FILTERS_HASH = Hash[
      GitHub::Goomba::WarpPipe::REFERENCE_FILTERS.map { |fc| [fc::SELECTOR, fc] }
    ].freeze

    REFERENCE_FILTERS = REFERENCE_FILTERS_HASH.values

    def self.filters_hash
      REFERENCE_FILTERS_HASH
    end

    def self.filters
      REFERENCE_FILTERS
    end
  end
end
