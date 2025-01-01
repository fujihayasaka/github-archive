# typed: strict
# frozen_string_literal: true

module Copilot::PullRequests
  class CodeReviewReferenceSerializer
    extend T::Sig

    sig do
      params(
        pull_request: T.nilable(PullRequest),
        include_diff: T.nilable(T::Boolean),
        include_full_files: T.nilable(T::Boolean)
      ).returns(T.nilable(T::Hash[T.untyped, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
    end
    def to_hash(pull_request, include_diff: false, include_full_files: false)
      return nil if pull_request.nil?

      base_repo = pull_request.base_repository
      head_repo = pull_request.head_repository
      compare_repository = pull_request.compare_repository
      merge_base = compare_repository.best_merge_base(pull_request.base_sha, pull_request.head_sha)

      pull_comparison = PullRequest::Comparison.find(
        pull: pull_request,
        start_commit_oid: pull_request.merge_base,
        end_commit_oid: pull_request.head_sha,
        base_commit_oid: merge_base
      )

      files = nil
      diff_creator = nil
      if include_diff && !base_repo.nil? && !head_repo.nil?
        diff_creator = PullRequests::Copilot::CompareTreesDiffCreator.new(
            base_repo: base_repo,
            head_repo: head_repo,
            base_revision: merge_base,
            head_revision: pull_request.head_sha
        )

        hunks = diff_creator.diff_hunks_without_line_numbers
        files = hunks.map do |hunk|
          {
            "type": "diff_hunk", # TODO: match reference type??
            "changeReference": hunk[:change_reference],
            "fileName": hunk[:file_path],
            "diff": hunk[:diff],
            "headerContext": hunk[:header_context],
          }
        end
      end

      return nil if base_repo.nil? || head_repo.nil?

      data = {
        "id": pull_request.id,
        "type": "pull-request",
        "title": pull_request.title,
        "body": pull_request.body,
        "url": pull_request.permalink,
        "authorLogin": pull_request.owner.display_login,
        "repository": {
          "id": base_repo.id,
          "name": base_repo.name,
          "ownerLogin": base_repo.owner_display_login,
          "ownerType": base_repo.owner_type,
          "readmePath": nil,
          "description": base_repo.description,
          "commitOID": base_repo.commit_for_ref(base_repo.default_branch).oid,
          "ref": "refs/heads/" + pull_request.base_ref_name,
          "refInfo": {
            "name": base_repo.default_branch,
            "type": "branch"
          },
          "visibility": base_repo.visibility,
          "languages": [],
          "type": "repository"
        },
        "headRepository": {
          "id": head_repo.id,
          "name": head_repo.name,
          "ownerLogin": head_repo.owner_display_login,
          "ownerType": head_repo.owner_type,
          "readmePath": nil,
          "description": head_repo.description,
          "commitOID": head_repo.commit_for_ref(head_repo.default_branch).oid,
          "ref": "refs/heads/" + pull_request.head_ref_name,
          "refInfo": {
            "name": head_repo.default_branch,
            "type": "branch"
          },
          "visibility": head_repo.visibility,
          "languages": [],
          "type": "repository"
        },
        "number": pull_request.number,
        "baseRevision": pull_request.base_sha,
        "headRevision": pull_request.head_sha,
        "baseRepoID": base_repo.id,
        "headRepoID": head_repo.id,
        "comparisonStartOID": pull_comparison.start_commit.oid,
        "comparisonEndOID": pull_comparison.end_commit.oid,
        "comparisonBaseOID": pull_comparison.base_commit.oid,
        "files": files,
      }

      if diff_creator && include_full_files
        data.merge!(
          "headFileContents": diff_creator.head_file_contents,
          "baseFileContents": diff_creator.base_file_contents,
        )
      end

      {
        "type": "github.pull_request",
        "id": pull_request.path_uri&.path,
        "data": data,
      }
    end
  end
end
