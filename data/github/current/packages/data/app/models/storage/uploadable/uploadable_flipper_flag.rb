# typed: true
# frozen_string_literal: true

module Storage
  module Uploadable
    class UploadableFlipperFlag
      attr_reader :flipper_id

      def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
        new(id)
      end

      def initialize(uploadable)
        migration_id = uploadable.storage_migration_id.gsub(":", "_")
        @flipper_id = "#{uploadable.class.name}:#{migration_id}"
      end

      def to_s
        @flipper_id
      end
    end
  end
end
