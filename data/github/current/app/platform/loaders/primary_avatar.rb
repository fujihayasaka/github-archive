# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PrimaryAvatar < Platform::Loader
      def self.load(owner)
        self.for(owner.class.base_class.name).load(owner.id)
      end

      def initialize(owner_type)
        @owner_type = owner_type
      end

      def fetch(owner_ids)
        ::PrimaryAvatar.where(owner_id: owner_ids, owner_type: @owner_type).index_by(&:owner_id)
      end
    end
  end
end
