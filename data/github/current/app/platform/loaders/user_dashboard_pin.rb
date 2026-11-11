# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class UserDashboardPin < Platform::Loader
      sig { params(viewer_id: Integer, repository_id: Integer).returns(Promise[T::Boolean]) }
      def self.load(viewer_id, repository_id)
        self.for(viewer_id).load(repository_id)
      end

      sig { params(viewer_id: Integer).void }
      def initialize(viewer_id)
        @viewer_id = viewer_id
      end

      sig { params(repository_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Boolean]) }
      def fetch(repository_ids)
        pinned = ::UserDashboardPin
          .where(pinned_item_type: "Repository", user_id: @viewer_id, pinned_item_id: repository_ids)
          .pluck(:pinned_item_id)
          .to_set

        repository_ids.index_with { |id| pinned.include?(id) }
      end
    end
  end
end
