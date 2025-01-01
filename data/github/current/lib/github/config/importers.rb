# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Importers
      # The largest payload that the API will accept.
      def issue_import_max_json_bytes
        @issue_import_max_json_bytes ||= 1.megabyte
      end
      attr_writer :issue_import_max_json_bytes

      # The backend for the issue import API.
      def issue_importer
        @issue_importer ||= GitHub::Importer2::Issues.new
      end
      attr_writer :issue_importer
    end
  end

  extend Config::Importers
end
