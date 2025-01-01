# typed: false
# frozen_string_literal: true

module Diff
  # Controls the display of blobs and annotations in a non diff entry.
  class NonDiffEntry < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include UrlHelper
    include DiffHelper

    LINE_PADDING = 3

    # The repository this non_diff_entry is from
    attr_reader :repository

    # The pull_request of this non_diff_entry
    attr_reader :pull_request

    # The annotations shown in this non_diff_entry
    attr_reader :annotations

    # The blob underlying this non_diff_entry
    attr_reader :blob


    def path
      blob.path.force_encoding("UTF-8")
    end

    def named_anchor_prefix
      "file-#{path.parameterize}-"
    end

    # Similar to DiffHelper#diff_blob_path
    def non_diff_blob_path
      "/#{repository.name_with_display_owner}/blob/#{pull_request.head_sha}/#{escape_url_branch(path)}"
    end

    # Similar to DiffHelper#diff_blob_branch_path
    def non_diff_blob_branch_path(action, params = {})
      if pull_request.head_ref_exist?
        blob_path = "/#{repository.name_with_display_owner}/#{action}/#{escape_url_branch(pull_request.head_ref_name)}/#{escape_url_branch(path)}"

        if params.empty?
          blob_path
        else
          "#{blob_path}?#{params.to_query}"
        end
      else
        non_diff_blob_path
      end
    end

    # Return an array of line numbers that encompasses all lines
    # targeted by annotations and the lines adjacent to them
    #
    # Returns an Array of integers
    def lines_to_include
      lines = []
      annotations.each do |annotation|
        start_line = annotation.start_line - LINE_PADDING
        end_line = annotation.end_line + LINE_PADDING
        lines += (start_line..end_line).to_a
      end

      lines.uniq.sort.select(&:positive?)
    end

    # Returns a Boolean
    def at_least_one_annotation_within_blob?
      annotations.pluck(:end_line).any? { |end_line| end_line <= blob.line_count }
    end

    def file_type
      get_file_type(path)
    end
  end
end
