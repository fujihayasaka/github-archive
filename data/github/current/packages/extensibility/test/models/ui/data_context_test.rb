# typed: true
# frozen_string_literal: true

require "test_helper"

class UI::DataContextTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, has_discussions: true, from_example: :review_comment_source)
    create(:commit, repository: @repo, branch: "branch1")

    @issue = create(:issue, repository: @repo)
    @issue_comment = create(:issue_comment, issue: @issue)

    @pull_request = create(:pull_request, repository: @repo, head_ref: "branch1")
    @pull_request_comment = create(:pull_request_review_comment, pull_request: @pull_request)

    @discussion = create(:discussion, repository: @repo)
    @discussion_comment = create(:discussion_comment, discussion: @discussion)
  end

  test "with just a repo" do
    data = UI::DataContext.new({ entity: @repo })
    assert_same_hash(
      {
        "github" => {
          "repository" => {
            "id" => @repo.id
          }
        }
      },
      data.data
    )
  end

  test "with an issue" do
    data = UI::DataContext.new({ entity: @repo, subject: @issue })
    assert_same_hash(
      {
        "github" => {
          "repository" => {
            "id" => @repo.id
          },
          "issue" => {
            "id" => @issue.id
          }
        }
      },
      data.data
    )
  end

  test "with an issue comment" do
    data = UI::DataContext.new({ entity: @repo, subject: @issue_comment })
    assert_same_hash(
      {
        "github" => {
          "repository" => {
            "id" => @repo.id
          },
          "issue" => {
            "id" => @issue.id
          }
        }
      },
      data.data
    )
  end

  test "with a PR" do
    data = UI::DataContext.new({ entity: @repo, subject: @pull_request })
    assert_same_hash(
      {
        "github" => {
          "repository" => {
            "id" => @repo.id
          },
          "pull_request" => {
            "id" => @pull_request.id
          },
          "issue" => {
            "id" => @pull_request.issue.id
          }
        }
      },
      data.data
    )
  end

  test "with a PR comment" do
    data = UI::DataContext.new({ entity: @repo, subject: @pull_request_comment })
    assert_same_hash(
      {
        "github" => {
          "repository" => {
            "id" => @repo.id
          },
          "pull_request" => {
            "id" => @pull_request.id
          },
          "issue" => {
            "id" => @pull_request.issue.id
          }
        }
      },
      data.data
    )
  end

  test "with a Discussion" do
    data = UI::DataContext.new({ entity: @repo, subject: @discussion })
    assert_same_hash(
      {
        "github" => {
          "repository" => {
            "id" => @repo.id
          },
          "discussion" => {
            "id" => @discussion.id
          }
        }
      },
      data.data
    )
  end

  test "with a Discussion Comment" do
    data = UI::DataContext.new({ entity: @repo, subject: @discussion_comment })
    assert_same_hash(
      {
        "github" => {
          "repository" => {
            "id" => @repo.id
          },
          "discussion" => {
            "id" => @discussion.id
          }
        }
      },
      data.data
    )
  end
end
