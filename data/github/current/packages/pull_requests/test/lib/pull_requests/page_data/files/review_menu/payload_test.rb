# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData::Files::ReviewMenu
    class PayloadTest < GitHub::TestCase
      fixtures do
        @user = create(:user)

        @repository = create(:repository, admin: @user, from_example: :review_comment_fork)
        create(:collaborator, collaborator: @user, repository: @repository)
        assert @repository.member?(@user)

        @pull = create(:pull_request,
          repository: @repository,
          base_repository: @repository,
          base_user: @user,
          base_ref: @repository.default_branch,
          head_repository: @repository,
          head_user: @user,
          head_ref_name: "topic",
          user: @user,
        )

        review = PullRequestReview.create(
          user: @user,
          pull_request: @pull,
          state: :pending,
          head_sha: @pull.head_sha,
        )

        comment = create(:pull_request_review_comment,
          pull_request: @pull,
          user: @user,
          body: "hiya",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26,
          pull_request_review: review,
        )

        thread = comment.memoized_async_pull_request_review_thread.sync

        @expected_payload = {
          "id" => @pull.latest_pending_review_for(@user).id,
          "comments" => [
            {
              "bodyHTML" => comment.body_html,
              "id" => String(thread.id),
              "isOutdated" => false,
              "isResolved" => false,
              "line" => 18,
              "path" => thread.path,
              "subject" => {
                "diffLines" => [
                    {
                      "html" => "@@ -15,24 +15,26 @@ Comic Books — the first version of Aquaman, was created by writer Mort Weising",
                      "left" => 14,
                      "right" => 14,
                      "text" => "@@ -15,24 +15,26 @@ Comic Books — the first version of Aquaman, was created by writer Mort Weising",
                      "type" => "HUNK"
                    },
                    {
                      "html" => "and artist Paul Norris, appeared in a backup feature in DC Comics&#39; More Fun",
                      "left" => 15,
                      "right" => 15,
                      "text" => " and artist Paul Norris, appeared in a backup feature in DC Comics' More Fun",
                      "type" => "CONTEXT"
                    },
                    {
                      "html" => "Comics #73-107 (Nov. 1941 - Feb. 1946), after which the series dropped superhero",
                      "left" => 16,
                      "right" => 16,
                      "text" => " Comics #73-107 (Nov. 1941 - Feb. 1946), after which the series dropped superhero",
                      "type" => "CONTEXT"
                    },
                    {
                      "html" => "stories to become a humor title. Aquaman&#39;s feature moved to Adventure Comics",
                      "left" => 17,
                      "right" => 17,
                      "text" => " stories to become a humor title. Aquaman's feature moved to Adventure Comics",
                      "type" => "CONTEXT"
                    },
                    {
                      "html" => "#103-284 (April 1946 - May 1961) as a backup to the comic book&#39;s star, <span class=\"x x-first x-last\">Superboy</span>.",
                      "left" => 18,
                      "right" => 17,
                      "text" => "-#103-284 (April 1946 - May 1961) as a backup to the comic book's star, Superboy.",
                      "type" => "DELETION"
                    },
                    {
                      "html" => "#103-284 (April 1946 - May 1961) as a backup to the comic book&#39;s star, <span class=\"x x-first x-last\">SUPERBOY</span>.",
                      "left" => 18,
                      "right" => 18,
                      "text" => "+#103-284 (April 1946 - May 1961) as a backup to the comic book's star, SUPERBOY.",
                      "type" => "ADDITION"
                    }
                  ],
                "endLine" => 26,
                "endDiffSide" => "RIGHT",
                "originalEndLine" => 18,
                "originalStartLine" => nil,
                "pullRequestCommit" => @pull.head_sha,
                "startDiffSide" => "RIGHT",
                "startLine" => 26,
              },
              "subjectType" => "line",
              "threadPreviewComments" => []
            }
          ]
        }.freeze
      end

      test "serializes the code button with Ruby conventions using to_hash" do
        data = PullRequests::PageData::Files::ReviewMenu::Loader.load(
          current_user: @user,
          pull_request: @pull,
        )

        refute_nil data

        assert_no_queries do
          actual_payload = PullRequests::PageData::Files::ReviewMenu::Payload.call(T.must(data))
          assert_equal @expected_payload.as_json, actual_payload.as_json
        end
      end
    end
  end
end
