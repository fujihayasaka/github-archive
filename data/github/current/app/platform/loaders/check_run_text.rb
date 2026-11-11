# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class CheckRunText < Platform::Loader

      SUPPORTED_COLUMNS = [:text, :summary].freeze

      def self.load(check_run_id, column: :text, repository_id: nil)
        raise Platform::Errors::InvalidValue, "unsupported column '#{column}'" unless SUPPORTED_COLUMNS.include?(column)
        self.for(column, repository_id).load(check_run_id)
      end

      attr_reader :column, :repository_id

      def initialize(column, repository_id)
        @column = column
        @repository_id = repository_id
      end

      def fetch(ids)
        CheckRun.where(id: ids, repository_id: repository_id).pluck(:id, column).to_h
      end
    end
  end
end
