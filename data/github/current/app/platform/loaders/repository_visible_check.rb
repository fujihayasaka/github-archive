# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RepositoryVisibleCheck < Platform::Loader
      def self.load(viewer, repository_id, resource: nil, cap_filter: nil)
        self.for(viewer, resource, cap_filter).load(repository_id)
      end

      def initialize(viewer, resource, cap_filter)
        @viewer = viewer
        @resource = resource
        @cap_filter = cap_filter
      end

      def fetch(repository_ids)
        public_repository_ids = []
        private_repository_ids = []

        scope = Repository.
          where(id: repository_ids).
          active.
          filter_spam_and_disabled_for(@viewer)

        if @cap_filter
          @cap_filter.authorized_resources(scope).each do |repo|
            if repo.public?
              public_repository_ids << repo.id
            else
              private_repository_ids << repo.id
            end
          end
        else
          scope.pluck(:id, :public).each do |id, public|
            if public
              public_repository_ids << id
            else
              private_repository_ids << id
            end
          end
        end

        # TODO: Allow `Bot` users to also access private repositories.
        if @viewer && !@viewer.bot? && private_repository_ids.any?
          public_repository_ids.concat(@viewer.associated_repository_ids(repository_ids: private_repository_ids, resource: @resource))
        end

        public_repository_ids.each_with_object(Hash.new(false)) do |repository_id, result|
          result[repository_id] = true
        end
      end
    end
  end
end
