# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData::Files
    class PayloadTest < GitHub::TestCase
      include PerformanceTestHelpers

      fixtures do
        @user = create(:user)
        @user_session = create(:authentication_record, user: @user).user_session
        @repo = create(:repository, admin: @user, from_example: :pull_request_history)
        create(:collaborator, collaborator: @user, repository: @repo)
        assert @repo.member?(@user)

        @pull = create(:pull_request,
          base_ref: @repo.default_branch,
          base_repository: @repo,
          base_user: @user,
          head_ref_name: "topic",
          head_repository: @repo,
          head_user: @user,
          repository: @repo,
          user: @user,
        )
        assert_predicate @pull, :valid?

        @check_suite = create :check_suite,
          repository: @pull.repository,
          head_sha: @pull.head_sha,
          status: "completed"
        @check_run = create :check_run,
          check_suite: @check_suite,
          name: "run-1",
          status: "completed",
          conclusion: "success"
        @check_annotation = create(:check_annotation,
          check_run: @check_run,
          path: "README.md",
          repository: @pull.repository,
          message: "Integration ran",
          start_line: 14,
          end_line: 14
        )

        @review = PullRequestReview::Creator.execute(pull_request: @pull,
          user: @user,
          comments: [{ path: "README.md", position: 1, body: "cool" }],
          event: "comment").review

        @base_ref_oid = @pull.base_sha
        @start_commit_oid = @pull.merge_base
        @end_commit_oid = @pull.head_sha
        @viewed_files = PullRequestUserReviews.new(@pull, @user).freeze
      end

      test "serializes data as expected" do
        Timecop.freeze do # Freeze the time to avoid flakiness of the generated alive channel
          codeowners = Repository::Codeowners.new(@pull.repository)

          # PullRequest::Comparison cannot be frozen or reloaded, so can't be defined in the fixtures block.
          pull_comparison = PullRequest::Comparison.find(
            pull: @pull,
            start_commit_oid: @start_commit_oid,
            end_commit_oid: @end_commit_oid,
            base_commit_oid: @pull.base_sha
          )

          expected_commits = @pull.changed_commits.map do |commit|
            {
              "actorLogin" => commit.user_display_login,
              "createdAt" => commit.created_at.to_s,
              "messageHeadline" => commit.short_message_text,
              "oid" => commit.oid,
              "shortOid" => commit.abbreviated_oid,
            }
          end

          expected_diff_summaries = pull_comparison.diff.entries.map do |diff_entry|
            {
              "changeType" => Diffs::Entry::ChangeType.deserialize(
                diff_entry.status_label&.upcase
              ),
              "isCodeowner" => codeowners.owners_for_path(diff_entry.path).include?(:current_user),
              "isManifestFile" => false,
              "isVendored" => false,
              "markedAsViewed" => @viewed_files.reviewed?(diff_entry.path),
              "path" => diff_entry.path,
              "pathDigest" => diff_entry.path_digest,
              "highestAnnotationLevel" => "WARNING",
              "totalCommentsCount" => 1,
            }
          end

          expected_diff_contents = [{ "isBinary" => false,
            "isSubmodule" => false,
            "isTooBig" => false,
            "diffLines" =>
             [{ "type" => "HUNK",
               "blobLineNumber" => 0,
               "position" => 0,
               "displayNoNewLineWarning" => false,
               "text" => "@@ -1 +1,3 @@",
               "html" => "@@ -1 +1,3 @@",
               "left" => 0,
               "right" => 0 },
              { "type" => "CONTEXT",
               "blobLineNumber" => 1,
               "position" => 1,
               "displayNoNewLineWarning" => false,
               "text" => " # Pull Request History",
               "html" => " # Pull Request History",
               "left" => 1,
               "right" => 1 },
              { "type" => "ADDITION",
               "blobLineNumber" => 2,
               "position" => 2,
               "displayNoNewLineWarning" => false,
               "text" => "+",
               "html" => "+",
               "left" => 1,
               "right" => 2 },
              { "type" => "ADDITION",
               "blobLineNumber" => 3,
               "position" => 3,
               "displayNoNewLineWarning" => false,
               "text" => "+It's gonna be great.",
               "html" => "+It&#39;s gonna be great.",
               "left" => 1,
               "right" => 3 }],
            "linesAdded" => 2,
            "linesChanged" => 2,
            "linesDeleted" => 0,
            "newCommitOid" => "68c1c1fbcd5eafa8063fbaa0795bb7a7fb819b7d",
            "newTreeEntry" =>
             { "mode" => 100644,
              "path" => "README.md",
              "lineCount" => 3,
              "isGenerated" => false },
            "oldCommitOid" => nil,
            "oldTreeEntry" =>
             { "mode" => 100644, "path" => "README.md", "lineCount" => 1 },
            "path" => "README.md",
            "pathDigest" =>
             "b335630551682c19a781afebcf4d07bf978fb1f8ac04c6bf87428ed5106870f5",
            "richDiff" => nil,
            "status" => "MODIFIED",
            "truncatedReason" => nil,
            "size" => "" }]

          base_url = @pull.url(include_host: false)
          first_comment = @review.review_comments[0]
          review_thread = @review.review_threads[0]

          expected_payload = {
            "aliveChannel" => GitHub::WebSocket::Channels.signed_pull_request(@pull),
            "annotations" => [
              {
                annotationLevel: "WARNING",
                appAvatarAltText: "#{@check_suite.github_app.name} avatar image",
                appAvatarUrl: @check_suite.github_app.preferred_avatar_url(size: 20),
                checkRun: {
                  detailsUrl: @check_run.details_url,
                  name: @check_run.name
                },
                checkSuiteName: @check_run.check_suite.name,
                databaseId: @check_annotation.id,
                endLine: @check_annotation.end_line,
                id: @check_annotation.global_relay_id,
                message: @check_annotation.message.dup.force_encoding("UTF-8"),
                path: @check_annotation.path.dup.force_encoding("UTF-8"),
                pathDigest: Digest::SHA256.hexdigest(@check_annotation.path),
                startLine: @check_annotation.start_line,
                title: @check_annotation.title.dup.force_encoding("UTF-8"),
              },
            ],
            "bannersData" => {
              "banners" => {
                "dependabotAutomatedSecurityUpdates" => { "render" => false },
                "pausedDependabotUpdate" => { "render" => false },
                "hiddenCharacterWarning" => { "render" => false },
              }
            },
            "commits" => expected_commits,
            "diffSummaries" => expected_diff_summaries,
            "diffContents" => expected_diff_contents,
            "pullRequest" => {
              "author" => { "login" => @user.login },
              "baseBranch" => "master",
              "commitsCount" => 1,
              "comparison" => {
                "baseOid" => @pull.historical_comparison.async_base_oid.sync,
                "headOid" => @pull.historical_comparison.async_head_oid.sync
              },
              "globalRelayId" => @pull.global_relay_id,
              "headBranch" => "topic",
              "headRepositoryName" => @pull.repository.name,
              "headRepositoryOwnerLogin" => @pull.repository.owner_display_login,
              "isInAdvisoryRepo" => false,
              "mergedBy" => nil,
              "mergedTime" => nil,
              "number" => @pull.number,
              "pathName" => @pull.permalink(include_host: false),
              "state" => "OPEN",
              "title" => @pull.title,
              "titleHtml" => @pull.title_html,
              "viewerCanLeaveNonCommentReviews" => false,
              "viewerHasViolatedPushPolicy" => false
            },
            "repository" => {
              "codespacesEnabled" => GitHub.codespaces_enabled?,
              "copilotEnabled" => @pull.repository.feature_enabled?(:copilot_workspace),
              "editorEnabled" => @repo.owner.feature_preview_enabled?(:copilot_hadron_editor), # Assumes that the owner of the repository is the user from the fixtures
              "defaultBranch" => @repo.default_branch,
              "id" => @repo.id,
              "isEnterprise" => GitHub.enterprise?,
              "name" => @repo.name,
              "ownerLogin" => @repo.owner_display_login,
              "viewerPermission" => "write"
            },
            "threadPreviews" => [{
              "firstComment" => {
                "author" => {
                  "login" => @user.display_login,
                  "avatarUrl" => @user.primary_avatar_url
                },
                "authorAssociation" => "COLLABORATOR",
                "body" => first_comment.body,
                "bodyHTML" => first_comment.body_html,
                "createdAt" => first_comment.created_at.to_s,
                "currentDiffResourcePath" => first_comment.async_current_diff_path_uri.sync.to_s,
                "databaseId" => first_comment.id,
                "id" => first_comment.global_relay_id,
                "isHidden" => false,
                "lastUserContentEdit" => nil,
                "outdated" => false,
                "publishedAt" => first_comment.created_at.to_s,
                "reference" =>
                  {
                    "number" => @pull.number,
                    "text" => nil,
                    "author" => { login: @pull.user.display_login }
                  },
                "repository" => {
                  "id" => @pull.repository.id.to_s,
                  "isPrivate" => TestEnv.test_with_all_emus? ? true : false,
                  "name" => @pull.repository.name,
                  "owner" => {
                    "id" => @pull.repository.owner.id.to_s,
                    "login" => @pull.repository.owner.display_login,
                    "url" => @pull.repository.owner.async_url.to_s
                    }
                  },
                "stafftoolsUrl" => nil,
                "state" => "submitted",
                "subjectType" => "line",
                "url" =>
                  "#{GitHub.url}/#{@pull.repository.owner.display_login}/#{@pull.repository.name}/pull/#{@pull.number}#discussion_r#{first_comment.id}",
                "viewerCanBlockFromOrg" => false,
                "viewerCanDelete" => false,
                "viewerCanMinimize" => false,
                "viewerCanSeeMinimizeButton" => false,
                "viewerCanSeeUnminimizeButton" => false,
                "viewerCanReport" => false,
                "viewerCanReportToMaintainer" => false,
                "viewerCanUnblockFromOrg" => false,
                "viewerCanUpdate" => false,
                "viewerDidAuthor" => true,
                "viewerRelationship" => "COLLABORATOR"
              },
              "line" => 1,
              "id" => review_thread.id.to_s,
              "isOutdated" => false,
              "isResolved" => false,
              "path" => "README.md",
              "subject" => {
                "diffLines" => [
                  {
                    "html" => "@@ -1 +1,3 @@",
                    "left" => 0,
                    "right" => 0,
                    "text" => "@@ -1 +1,3 @@",
                    "type" => "HUNK"
                  },
                  {
                    "html" => "# Pull Request History",
                    "left" => 1,
                    "right" => 1,
                    "text" => " # Pull Request History",
                    "type" => "CONTEXT"
                  }
                ],
                "endLine" => 1,
                "endDiffSide" => "RIGHT",
                "originalEndLine" => 1,
                "originalStartLine" => nil,
                "pullRequestCommit" => {
                  "commit" => {
                    "abbreviatedOid" => @pull.head_sha
                  }
                },
                "startDiffSide" => "RIGHT",
                "startLine" => 1
              },
              "threadPreviewComments" => []
            }],
            "urls" => {
              "checks" => "#{base_url}/checks",
              "commits" => "#{base_url}/commits",
              "conversation" => base_url,
              "files" => "#{base_url}/files",
            },
            "user" => {
              "canChangeBase" => true,
              "currentUserLogin" => @user.login,
              "canEditTitle" => true,
              "isFileTreeExpanded" => true,
              "lastReviewOid" => "c78be2730338ba61f8bc0f9a3b8dae0fdfd239cd",
              "shouldShowViewedFilesCount" => true,
              "viewedFilesCount" => 0,
              "viewSettings" => {
                "hideWhitespace" => false,
                "lineSpacing" => "relaxed",
                "splitPreference" => "unified",
                "commentsPreference" => "visible",
              },
            },
            "viewerPendingReview" => { "id" => nil, "comments" => [] }
          }

          data = PullRequests::PageData::Files::Loader.load(
            comparison: pull_comparison,
            current_user: @user,
            pull_request: @pull,
            cap_filter: nil,
            user_session: nil,
            timeout: 2,
            ignore_whitespace: false,
          )

          rpc_counts = {
            authzd: {
              single: 0,
              batch: 0,
            },
            gitrpc: 0,
          }

          assert_rpc_calls(rpc_counts) do
            # for some reason 1 flipper call is happening for a blob information FF check even though there are no asserted gitrpc calls
            # need to figure this out at some point
            assert_query_count(0, ignore_feature_flags: true) do
              actual_payload = PullRequests::PageData::Files::Payload.call(data)
              assert_equal expected_payload.as_json, actual_payload.as_json
            end
          end
        end
      end
    end
  end
end
