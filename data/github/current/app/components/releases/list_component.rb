# typed: true
# frozen_string_literal: true

module Releases
  class ListComponent < ApplicationComponent
    # releases - release models converted from ElasticSearch results
    # These do not contain highlighting information so we need to pass
    # es_results - the ElasticSearch results containing a hash of matching query terms to highlight in release body, title and tag_name if available.
    def initialize(releases, current_repository, latest_release, filter_phrase = nil, writable:, expand_all: false, es_results: nil)
      @releases = releases
      @current_repository = current_repository
      @latest_release = latest_release
      @filter_phrase = filter_phrase
      @writable = writable
      @expand_all = expand_all
      @es_results = es_results

      tag_names = releases.filter_map { |release| release.tag&.name_for_display }
      @unqualified_name_conflicts = current_repository.refs.unqualified_name_conflicts(tag_names).to_set
    end

    attr_reader :releases, :current_repository, :filter_phrase, :expand_all, :es_results

    def writable?
      @writable
    end

    def is_latest?(release)
      release == @latest_release
    end

    def unqualified_name_conflict?(release)
      @unqualified_name_conflicts.include?(release.tag&.name_for_display)
    end

    # Get the highlight field from the matching release document hash returned from the ElasticSearch index.
    def highlights(release)
      current_result = @es_results&.find { |r| r["_id"] == release.id.to_s }
      current_result&.fetch("highlight", nil) || {}
    end

    def should_truncate_assets?(release)
      is_latest?(release) && release.uploaded_assets.size > Release::UPLOADED_ASSET_DISPLAY_LIMIT
    end
  end
end
