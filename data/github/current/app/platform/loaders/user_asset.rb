# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class UserAsset < Platform::Loader
      def self.load(guid)
        self.for.load(guid)
      end

      def fetch(guids)
        ::UserAsset.includes(:repository).where(guid: guids).index_by(&:guid)
      end
    end
  end
end
