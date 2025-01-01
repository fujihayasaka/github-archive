# typed: true
# frozen_string_literal: true

module PullRequests::Copilot
  class SuggestedChangesGenerator
    CURRENT_JOBS = 1
    LOCK_TTL = 5.minutes

    # Public: Generate a suggested change from a code review comment and file.
    # requestor - User manually requesting a review from Copilot, or PR author for automatic reviews.
    sig { params(repo: Repository, pull: PullRequest, requestor: User, comment: PullRequestReviewComment).void }
    def initialize(repo:, pull:, requestor:, comment:)
      @repo = repo
      @pull = pull
      @requestor = requestor
      @comment = comment
    end

    # Public: Generate a suggested change from Copilot for the given comment.
    # This assumes that feature flag and license checks have already passed.
    sig { returns(T::Boolean) }
    def generate
      return false if repo.nil? || requestor.nil? || pull.nil?

      success = T.let(true, T::Boolean)

      lock_key = "SuggestedChangesGenerator_#{pull.id}_#{comment.id}"
      restraint = GitHub::Restraint.new
      restraint.lock!(lock_key, CURRENT_JOBS, LOCK_TTL) do
        # Mint a copilot chat app token so we can invoke CAPI on behalf of the user
        app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
        new_access = app.grant(requestor)
        access, _ = new_access.redeem(extended_expiry: true)
        token = Copilot::DecryptedToken.from(access)

        integration_id = CopilotAPI::COPILOT_WORKSPACE_EDITOR_INTEGRATION_ID

        blob_oid = comment.diff_entry.b_blob

        # Can only generate suggestions when the comment is on the right side of the diff
        if comment.side != :right
          return true
        end

        # Can only generate suggestions when a right side exists!
        if blob_oid.nil?
          return true
        end

        comment_ref = {
          "type": "github.pull-request-comment",
          "data": {
            "type": "pull-request-comment",
            "body": comment.body,
            "commit_id": comment.commit_id,
            "created_at": comment.created_at,
            "updated_at": comment.updated_at,
            "diff_hunk": comment.diff_hunk,
            "id": comment.id,
            "in_reply_to_id": comment.in_reply_to&.id,
            "line": comment.line,
            "original_commit_id": comment.original_commit_id,
            "original_line": comment.original_line,
            "original_start_line": comment.original_start_line,
            "pull_request_id": pull.id,
            "side": comment.side,
            "start_line": comment.start_line_number,
            "start_side": comment.start_side,
            "subject_type": comment.subject_type,
          }
        }

        file_contents = repo.read_objects(
          [comment.diff_entry.b_blob], :blob).map do |file|
          file["data"]
        end

        if file_contents.length != 1
          return false
        end

        file_content = file_contents[0]

        # Unable to read the target file??
        if file_content.nil?
          return false
        end

        lang = Linguist::Blob.new(comment.path, file_content).language
        file_ref = {
          "type": "github.file",
          "data": {
            "type": "file",
            "languageID": lang.language_id,
            "languageName": lang.name,
            "commitOID": comment.commit_id,
            "content": file_content,
            "path": comment.path,
            "ref": "refs/heads/#{comment.commit_id}",
            "repoID": repo.id,
            "repoName": repo.name,
            "repoOwner": repo.owner_display_login,
            "url": comment.url,
          }
        }

        capi = Copilot::User::CopilotApi.new(
          requestor,
          integration_id:,
          session: nil, # There won't ever be a user session
          real_ip: nil, # Same as above
          token:,
        )
        resp = capi.classify_code_comment(
          references: [file_ref, comment_ref],
          role: "user",
          experiment_headers: {},
        )

        actionable = T.let(false, T::Boolean)
        resp[:copilot_references].map do |ref|
          next unless ref[:type] == "github.classify.result"
          actionable = ref[:data][:actionable]
        end

        # Inspect the response, determine classification state, and possibly
        # proceed to generate code
        if actionable
          capi.suggested_changes(
            references: [file_ref, comment_ref],
            role: "user",
            experiment_headers: {},
          )
        end

        success = true
      end

      success
    end

    attr_reader :repo, :pull, :requestor, :comment
  end
end
