# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    def gh_create_pull_request_path(repo)
      expand_nwo_from :create_pull_request_path, repo
    end

    def gh_merge_pull_request_path(pull)
      expand_nwo_from :merge_pull_request_path, pull
    end

    def gh_cleanup_pull_request_path(pull)
      expand_nwo_from :cleanup_pull_request_path, pull
    end

    def gh_undo_cleanup_pull_request_path(pull)
      expand_nwo_from :undo_cleanup_pull_request_path, pull
    end

    def gh_pull_request_diff_path(pull)
      expand_nwo_from :pull_request_diff_path, pull
    end

    def gh_pull_request_patch_path(pull)
      expand_nwo_from :pull_request_patch_path, pull
    end

    def gh_show_pull_request_path(pull)
      expand_nwo_from :show_pull_request_path, pull
    end

    def gh_pull_request_commit_path(pull, commit)
      base = gh_show_pull_request_path(pull)
      "#{ base }/commits/#{ commit }"
    end

    def gh_pull_request_files_path(pull, use_changes_route: false)
      base = gh_show_pull_request_path(pull)

      if use_changes_route
        "#{ base }/changes"
      else
        "#{ base }/files"
      end
    end

    def gh_pull_requests_files_with_range_path(pull, range, use_changes_route: false)
      base = gh_pull_request_files_path(pull, use_changes_route:)
      "#{ base }/#{ range }"
    end

    def gh_show_pull_request_check_sha_path(pull, commit, selected_check_run)
      base = gh_show_pull_request_path(pull)
      return "#{ base }/checks?sha=#{ commit }" unless selected_check_run.present?

      mapped_check_run = CheckRun.for_sha_and_repository_id(commit, pull.repository_id).find_by(name: selected_check_run.name)
      return "#{ base }/checks?sha=#{ commit }" unless mapped_check_run.present?
      "#{ base }/checks?check_run_id=#{ mapped_check_run.id }"
    end

    def gh_cleanup_codespaces_path(pull)
      expand_nwo_from :cleanup_codespaces_path, pull
    end
  end
end
