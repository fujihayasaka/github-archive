# typed: false
# frozen_string_literal: true

module ApplicationRecord
  module UTCRecord
    extend ActiveSupport::Concern

    class_methods do
      # Newsies models must set their datetime columns as
      # being utc:
      #
      # class MyModel
      #   attribute :created_at, ApplicationRecord::UTCTimeType.new
      # end
      #
      def utc_datetime_columns
        @utc_datetime_columns ||= []
      end

      def utc_datetime_columns=(columns)
        @utc_datetime_columns = (@utc_datetime_columns || []) + columns
        @utc_datetime_columns.each do |column|
          attribute column, UTCTimeType.new
        end
      end

      def default_github_sql_options
        { force_timezone: :utc }
      end
    end
  end
end
