# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ProjectItemsForContent < Platform::Loader
      def self.load(repository:, content_type:, content_id:, include_archived: true)
        self.for(repository, content_type, include_archived).load(content_id)
      end

      attr_reader :repository, :content_type, :include_archived

      def initialize(repository, content_type, include_archived)
        @repository = repository
        @content_type = content_type
        @include_archived = include_archived
      end

      def fetch(content_ids)
        scope = ::MemexProjectItem.where(
          content_type: content_type,
          content_id: content_ids,
          repository_id: repository.id
        )

        scope = scope.not_archived unless include_archived
        scope = scope.preload(memex_project: :owner)
        scope.group_by(&:content_id)
      end
    end
  end
end
