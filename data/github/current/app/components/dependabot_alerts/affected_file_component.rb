# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class AffectedFileComponent < ApplicationComponent
    include BotHelper
    include VulnerabilityHelper
    include PackageDependenciesHelper

    def initialize(repository:, filename:, function_references:, reveal_content:)
      @repository = repository
      @filename = filename
      @function_references = function_references
      @reveal_content = reveal_content
    end

    attr_reader :repository, :filename, :function_references, :reveal_content

    def first_reference
      function_references.first
    end

    def location_hash(function_reference)
      {
        start_line: function_reference.start_line,
        end_line: function_reference.end_line,
        start_column: function_reference.start_column,
        end_column: function_reference.end_column,
      }
    end

    def get_commit(commit_oid)
      Repositories.domain.commits.by_oid(repository: repository, commit_oid: commit_oid)
    end

    def get_blob(commit_oid, blob_path)
      return {} unless commit_oid.present?

      @blob_map = {}
      # Fetch blob_oid and match it to path
      blob_oid = repository.read_blob_oid(commit_oid, blob_path, skip_bad: true)
      paths_by_oid = Hash[blob_oid, blob_path]

      # Fetch blob by blob_oid and match its to path
      raw_blob = repository.rpc.read_blobs([blob_oid])
      raw_blob.map { |blob| @blob_map = TreeEntry.new(repository, blob.merge("path" => blob_path)) }

      @blob_map
    end
  end
end
