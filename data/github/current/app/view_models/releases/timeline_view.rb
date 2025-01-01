# typed: true
# frozen_string_literal: true

module Releases
  class TimelineView < Releases::View
    extend T::Sig

    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::UrlHelper

    attr_reader :releases, :drafts

    # Imposing limit on draft releases displayed in timeline.
    # See https://github.com/github/github/issues/90260#issuecomment-566805354
    DRAFT_RELEASE_DISPLAY_LIMIT = 30

    # releases - Releases with Tags to show for the page.
    # drafts   - Releases in draft state, prepended to beginning of timeline.
    sig do
      params(
        repository: Repository,
        current_user: T.nilable(User),
        releases: T.nilable(T::Array[Release]),
        drafts: T.nilable(T::Array[Release])
      ).void
    end
    def initialize(repository, current_user, releases, drafts = nil)
      super(repository, current_user)
      @drafts = Array(drafts)
      @releases = @drafts.take(DRAFT_RELEASE_DISPLAY_LIMIT) + Array(releases)
      prefill_releases
    end

    # A timeline that groups events by some heuristics:
    #
    # - Group tags in between major Releases with notes shown.
    # - Collapse tags along history timeline if there are more than 3 in a row.
    # - Collapse tags before the last major release
    #
    # End result is an Array of Hashes representing the timeline chunks:
    # {
    #   :type => 'tags',
    #   :style => 'collapsed',
    #   :items => [Release, Release, Release, Release]
    # }
    # {
    #   :type => 'tags',
    #   :style => 'expanded',
    #   :items => [Release, Release]
    # }
    # {
    #   :type => 'release',
    #   :style => 'latest',
    #   :item => Release
    # }
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def timeline
      @timeline ||= build_timeline
    end

    sig { params(release: Release).returns(T::Array[ReleaseAsset]) }
    def downloads_for(release)
      Array(all_release_assets[release.id])
    end

    sig { params(release: Release).returns(T::Boolean) }
    def has_downloads?(release)
      all_release_assets[release.id].present?
    end

    # returns the latest previous published release, if one is found.
    # this method first looks within the loaded releases and if no matching
    # release is found, we ask the database to find it.
    # nb: this method relies on the sort order of releases
    sig { params(target_release: Release).returns(T.untyped) }
    def previous_release_for(target_release)
      return nil if target_release.draft?

      published_releases = releases.select { |r| r.published? && r.persisted? }
      target_release_index = published_releases.index { |r| r.id == target_release.id }
      previous_release = published_releases[target_release_index + 1]

      return previous_release if previous_release

      target_release.previous_release
    end

    sig { params(release: Release).returns(T::Boolean) }
    def expander?(release)
      return false unless target = release.tag_target
      target.message_body_html? || target.short_message_html != release.tag_name
    end

    sig { returns(T::Boolean) }
    def show_limited_draft_releases_message?
      drafts.count > DRAFT_RELEASE_DISPLAY_LIMIT
    end

    private

    # Actually build the timeline object.
    #
    # Returns an Array of Hashes.
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def build_timeline
      result = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
      return result if releases.empty?

      current_chunk = T.let(nil, T.untyped)
      releases.each do |release|

        template = build_chunk_template(release)

        # We need to start a new chunk!
        if current_chunk.nil? || current_chunk[:type] != template[:type] || current_chunk[:type] == "release"
          result << finalize_chunk(current_chunk) unless current_chunk.nil?
          current_chunk = template
        end

        case current_chunk[:type]
        when "tags"
          current_chunk[:items] << release
        when "release"
          current_chunk[:item] = release
        end
      end

      result << finalize_chunk(current_chunk)
      if first_result = result.first
        # There's one tag for the first chunk
        if first_result[:type] == "tags" && first_result[:items].size == 1
          first_result[:style] = "expanded"

        # There's only tags in this list
        elsif first_result[:type] == "tags" && result.size == 1
          first_result[:style] = "expanded"

        # The first chunk is many tags
        elsif first_result[:type] == "tags"
          first_result[:style] = "all-collapsed"
        end
      end

      result
    end

    sig { returns(T::Hash[T.nilable(Integer), T::Array[ReleaseAsset]]) }
    def all_release_assets
      @all_release_assets ||= ::ReleaseAsset.for(@repository, @releases).
        group_by { |asset| asset.release_id }
    end

    # Build a Hash template for the chunk given the current item in iteration.
    #
    # Returns a Hash.
    sig { params(release: Release).returns(T::Hash[Symbol, T.untyped]) }
    def build_chunk_template(release)
      if release.viewable?
        {
          type: "release",
          style: label(release),
          item: nil,
        }
      else
        {
          type: "tags",
          style: "expanded",
          items: [],
        }
      end
    end

    sig { params(release: Release).returns(T.nilable(String)) }
    def label(release)
      "prerelease" if release.prerelease?
    end

    # Does any finalizations neccecary per chunk. Responsible for knowing when
    # to collapse chunks up.
    #
    # Returns a Hash
    sig { params(chunk: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def finalize_chunk(chunk)
      return chunk unless chunk[:type] == "tags"
      if chunk[:items].size > 3
        chunk[:style] = "collapsed"
      end
      chunk
    end

    sig { void }
    def prefill_releases
      assets = all_release_assets.values.flatten
      Release.prefill_releases_and_assets(@repository, @releases, assets, prefill_assets_downloads_counters: false)
    end
  end
end
