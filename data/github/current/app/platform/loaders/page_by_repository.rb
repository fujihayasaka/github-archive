# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PageByRepository < Platform::Loader
      def self.load(repository_id)
        self.for.load(repository_id)
      end

      def fetch(repository_ids)
        Page.where(repository_id: repository_ids).index_by(&:repository_id)
      end
    end
  end
end
