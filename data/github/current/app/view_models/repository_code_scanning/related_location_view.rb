# typed: true
# frozen_string_literal: true

module RepositoryCodeScanning
  class RelatedLocationView < View
    attr_reader :location, :blob, :commit_oid

    def path_link_target
      blob_path(
        commit_oid: commit_oid,
        file_path: location[:file_path],
        start_line: location[:start_line],
        end_line: location[:end_line],
      )
    end

    def helper
      @helper ||= RepositoryScanning::CodeSnippetHelper.new(blob, location, context_line_count: 0, highlight_location_lines: false)
    end
  end
end
