# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PushById < Platform::Loader

      def self.load(push_id)
        self.for.load(push_id)
      end

      def fetch(push_ids)
        Repositories.domain.pushes.by_ids(ids: push_ids).index_by(&:id)
      end
    end
  end
end
