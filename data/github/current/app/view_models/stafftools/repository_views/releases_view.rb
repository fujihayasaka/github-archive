# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class ReleasesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :repository
      attr_reader :page

      def page_title
        "#{repository.name_with_owner} - Releases"
      end

      def repo_releases
        raw_repo_releases.map { |r| ReleaseDecorator.new(r) }.paginate(page: page)
      end

      def repo_releases_count
        raw_repo_releases.count
      end

      def repo_releases_published_count
        raw_repo_releases.published.count
      end

      def repo_releases_draft_count
        raw_repo_releases.draft.count
      end

      def repo_releases_size
        raw_repo_releases.sum { |r| r.release_assets.sum(:size) }
      end

      def audit_query
        return "repo_id:#{repository.id} (action:release.*)" unless GitHub.driftwood_ade_queries_enabled?

        <<~KQL
          webevents
          | where repo_id == #{repository.id}
          | where action startswith "release."
        KQL
      end

      private

      def raw_repo_releases
        @raw_repo_releases ||=
          repository.releases.order("id DESC").includes(:release_assets)
      end

      class ReleaseDecorator
        attr_reader :release

        delegate \
          :created_at,
          :published?,
          :author,
          :release_assets,
          :published_at,
          :is_searchable?,
          to: :release

        BLOCKLIST = %w(author_id id repository_id state)

        def initialize(release)
          @release = release
        end

        def attributes
          release.attributes.except(*BLOCKLIST).sort
        end

        def name
          release.name.blank? ? release.pending_tag : release.name
        end
      end
    end
  end
end
