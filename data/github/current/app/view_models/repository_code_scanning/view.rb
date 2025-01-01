# typed: true
# frozen_string_literal: true

module RepositoryCodeScanning
  class View < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include CodeScanningHelper
    include GitHub::Memoizer


    attr_reader :query, :repository, :response, :selected_tool

    def after_initialize
      helpers.extend(TextHelper)
      helpers.extend(ScanningHelper)
    end

    def severity_octicon(rule_severity)
      case rule_severity
      when :NOTE
        "note"
      when :WARNING
        "alert"
      when :ERROR
        "circle-slash"
      else
        "alert"
      end
    end

    def severity_color(rule_severity)
      case rule_severity
      when :NOTE
        "color-fg-muted"
      when :WARNING
        "color-fg-severe"
      when :ERROR
        "color-fg-danger"
      else
        ""
      end
    end

    def result_resolved?(result)
      result.resolution.present? && result.resolution != :NO_RESOLUTION
    end

    def close_reason_details_singular
      {
        FALSE_POSITIVE: "This alert is not valid",
        USED_IN_TESTS: "This alert is not in production code",
        WONT_FIX: "This alert is not relevant",
      }
    end

    def close_path_no_params
      urls.repository_code_scanning_close_path(repository.owner, repository)
    end

    # cannist: can we remove ref_names parameter from this?
    def reopen_path(number: nil,  ref_names:)
      urls.repository_code_scanning_reopen_path(repository.owner, repository, number: number, ref_names: ref_names)
    end

    def turboscan_unavailable?
      response.nil? || response.data.nil? || response.error.present?
    end

    def rule_tags
      response&.data&.rule_tags || []
    end

    def tool_display_name
      selected_tool
    end

    def tag_path(tag)
      query_params = [[:tag, tag], [:is, :open]]
      query_params << [:tool, tool_display_name] if tool_display_name.present?
      tag_query = Search::Query.stringify(query_params)
      index_path(query: tag_query)
    end

    def index_path(**params)
      repository_index_path(repository, **params)
    end

    def result_path(result)
      repository_result_path(repository, result.number)
    end

    def severity_link_for_result(result, base_query: nil)
      the_query = base_query || query
      severity_link_for_repo_result(repository, result, the_query)
    end

    def related_location_path(commit_oid:, related_location:)
      params = {
        commit_oid: commit_oid,
        file_path: related_location.location.file_path,
        start_line: related_location.location.start_line,
        end_line: related_location.location.end_line,
        start_column: related_location.location.start_column,
        end_column: related_location.location.end_column,
      }
      urls.repository_code_scanning_related_location_popover_path(repository.owner, repository, params)
    end

    def split_file_path_and_name(filepath)
      helpers.split_file_path_and_name(filepath)
    end

    def blob_path(commit_oid:, file_path:, start_line:, end_line:)
      "/#{repository.name_with_display_owner}/blob/#{commit_oid}/#{urls.escape_url_branch(file_path)}#L#{start_line}-L#{end_line}"
    end

    memoize def alerts_writable_by_current_user?
      repository.code_scanning_alerts_writable_by?(current_user)
    end

    memoize def alerts_readable_by_current_user?
      repository.code_scanning_alerts_readable_by?(current_user)
    end

    def show_hubber_warning?
      repository.code_scanning_readable_because_hubber?(current_user)
    end

  end
end
