# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

LabelQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
  query($id: ID!) {
    node(id: $id) {
      ... on Label {
        ...Api::Serializer::IssuesDependency::LabelFragment
      }
    }
  }
GRAPHQL

IssueQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
  query($id: ID!, $includeBody: Boolean!, $includeBodyHTML: Boolean!, $includeBodyText: Boolean!) {
    node(id: $id) {
      ... on Issue {
        ...Api::Serializer::IssuesDependency::IssueFragment
      }

      ... on PullRequest{
        ...Api::Serializer::IssuesDependency::PullRequestIssueFragment
      }
    }
  }
GRAPHQL

IssueCommentQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
  query($id: ID!, $includePerformedViaGitHubApp: Boolean!, $includeBody: Boolean!, $includeBodyHTML: Boolean!, $includeBodyText: Boolean!) {
    node(id: $id) {
      ... on IssueComment {
        ...Api::Serializer::IssuesDependency::IssueCommentFragment
      }
    }
  }
GRAPHQL

class IssueSerializersTest < Api::SerializerTestCase
  fixtures do
    @owner = create(:user)
    @repo = create :repository, owner: @owner, from_example: :pull_request_fork
    @issue = create :issue, repository: @repo, user: @owner
    @forker = create(:user)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :pull_request_fork)

    @label = create(:label, repository: @repo, name: "bug", color: "cccccc", description: "A problem")

    @pull = PullRequest.create_for @repo,
      user: @forker,
      base: "master",
      head: "#{@forker}:topic",
      title: "some title",
      body: "some body"
    @pull_issue = @pull.issue

    @org    = create(:organization, login: "myorg")
    @team   = create(:team, organization: @org, name: "myteam", permission: "pull")

    @milestone = create :milestone, repository: @repo

    @comment = create(:issue_comment, issue: @issue, repository: @repo)
  end

  context "#graphql_label_hash" do
    test "graphql_label_hash and label_hash return identical hashes" do
      results = Api::App::PlatformClient.query(LabelQuery, variables: { id: @label.global_relay_id }, context: { viewer: @user })

      graphql_output = T.unsafe(self).graphql_label(results.data.node)
      output = T.unsafe(self).label(@label, repo: @repo)

      assert_equal output, graphql_output
    end

    test "graphql_label_hash and label_hash are identical" do
      results = Api::App::PlatformClient.query(LabelQuery, variables: { id: @label.global_relay_id }, context: { viewer: @user })

      graphql_output = T.unsafe(self).graphql_label(results.data.node)
      output = T.unsafe(self).label(@label, repo: @repo)

      refute_nil output["description"]
      assert_equal output, graphql_output
    end

    test "label_graphql_hash and label_hash are identical" do
      results = Api::App::PlatformClient.query(LabelQuery, variables: { id: @label.global_relay_id }, context: { viewer: @user })

      graphql_output = T.unsafe(self).graphql_label(results.data.node)
      output = T.unsafe(self).label(@label, repo: @repo)

      refute_nil output["node_id"]
      assert_equal output, graphql_output
    end

    test "payload is valid" do
      variables = {
        id: @label.global_relay_id,
      }

      results = Api::App::PlatformClient.query(LabelQuery, variables: variables, context: { viewer: @user })
      output = T.unsafe(self).graphql_label(results.data.node)
      assert output.key?("id")
      assert output.key?("node_id")
      assert output.key?("name")
      assert output.key?("color")
    end

    test "payload with description is valid" do
      variables = {
        id: @label.global_relay_id,
      }

      results = Api::App::PlatformClient.query(LabelQuery, variables: variables, context: { viewer: @user })
      output = T.unsafe(self).graphql_label(results.data.node)
      assert_equal "A problem", output["description"]
    end
  end

  context "#graphql_issue_hash" do
    test "graphql_issue_hash and issue_hash return identical hashes for an issue" do
      variables = {
        id: @issue.global_relay_id,
        includeBody: true,
        includeBodyHTML: true,
        includeBodyText: true,
      }

      results = Api::App::PlatformClient.query(IssueQuery, variables: variables, context: { viewer: @user })

      graphql_output = T.unsafe(self).graphql_issue(results.data.node)
      output = T.unsafe(self).issue(@issue)

      assert_equal graphql_output, output
    end

    test "graphql_issue_hash and issue_hash return identical hashes for an issue for beta format" do
      api_media_type "application/vnd.github.beta+json"

      variables = {
        id: @issue.global_relay_id,
        includeBody: true,
        includeBodyHTML: true,
        includeBodyText: true,
      }

      results = Api::App::PlatformClient.query(IssueQuery, variables: variables, context: { viewer: @user })

      graphql_output = T.unsafe(self).graphql_issue(results.data.node)
      output = T.unsafe(self).issue(@issue)

      assert_equal graphql_output, output
    end

    test "graphql_issue_hash and issue hash return identical hashes for a pull request" do
      variables = {
        id: @pull.global_relay_id,
        includeBody: true,
        includeBodyHTML: true,
        includeBodyText: true,
      }

      results = Api::App::PlatformClient.query(IssueQuery, variables: variables, context: { viewer: @user })

      graphql_output = T.unsafe(self).graphql_issue(results.data.node)
      output = T.unsafe(self).issue(@pull.issue)

      # I'm omitting the created_at key because 'technically' graphql_issue and issue use different values.
      # graphql_issue will use the PR created_at. issue will use the Issue created_at
      # These 2 values are basically always equal, but they can possibly diverge by one second,
      # which is causing flakes.
      assert_equal graphql_output.except("created_at"), output.except("created_at")
    end
  end

  context "#issue_hash" do
    test "beta format includes 'pull_request' property for issue that is NOT a pull request" do
      api_media_type "application/vnd.github.beta+json"

      output = T.unsafe(self).issue(@issue)
      assert output.key?("pull_request")
      pr_property = output["pull_request"]
      assert pr_property.key?("url")
      assert_nil pr_property["url"]
      assert pr_property.key?("html_url")
      assert_nil pr_property["html_url"]
      assert pr_property.key?("diff_url")
      assert_nil pr_property["diff_url"]
      assert pr_property.key?("patch_url")
      assert_nil pr_property["patch_url"]
      assert pr_property.key?("merged_at")
      assert_nil pr_property["merged_at"]
    end

    test "includes 'pull_request' property for issue that is a pull request when beta is requested and changeset is active" do
      api_media_type "application/vnd.github.beta+json"
      with_changeset "deprecate_beta_media_type" do
        @pull.update(merged_at: Time.now)
        output = T.unsafe(self).issue(@pull_issue)

        assert output.key?("pull_request")
        pr_property = output["pull_request"]
        assert_match /repos\/#{@owner}\/#{@repo}\/pulls\/#{@pull_issue.number}/, pr_property["url"]
        assert_match /#{@owner}\/#{@repo}\/pull\/#{@pull_issue.number}/, pr_property["html_url"]
        assert_match /#{@owner}\/#{@repo}\/pull\/#{@pull_issue.number}.diff/, pr_property["diff_url"]
        assert_match /#{@owner}\/#{@repo}\/pull\/#{@pull_issue.number}.patch/, pr_property["patch_url"]
        assert_equal @pull.merged_at.iso8601, pr_property["merged_at"]
      end
    end

    test "includes 'pull_request' property for issue that is a pull request" do
      @pull.update(merged_at: Time.now)
      output = T.unsafe(self).issue(@pull_issue)

      assert output.key?("pull_request")
      pr_property = output["pull_request"]
      assert_match /repos\/#{@owner}\/#{@repo}\/pulls\/#{@pull_issue.number}/, pr_property["url"]
      assert_match /#{@owner}\/#{@repo}\/pull\/#{@pull_issue.number}/, pr_property["html_url"]
      assert_match /#{@owner}\/#{@repo}\/pull\/#{@pull_issue.number}.diff/, pr_property["diff_url"]
      assert_match /#{@owner}\/#{@repo}\/pull\/#{@pull_issue.number}.patch/, pr_property["patch_url"]
      assert_equal @pull.merged_at.iso8601, pr_property["merged_at"]
    end

    test "handles pull request that is in a different repo" do
      other_repo = create :repository, owner: @owner

      # given a {repo: } value is faking the fact the pull request is in a different repo
      output = T.unsafe(self).issue(@pull.issue, { repo: other_repo })

      assert output.key?("pull_request")
      pr_property = output["pull_request"]
      assert_match /repos\/#{@owner}\/#{@repo}\/pulls\/#{@pull.number}/, pr_property["url"]
      assert_match /#{@owner}\/#{@repo}\/pull\/#{@pull.number}/, pr_property["html_url"]
      assert_match /#{@owner}\/#{@repo}\/pull\/#{@pull.number}.diff/, pr_property["diff_url"]
      assert_match /#{@owner}\/#{@repo}\/pull\/#{@pull.number}.patch/, pr_property["patch_url"]
    end

    test "handles an issue with a deleted pull request gracefully" do
      repo = create :repository
      issue = create :issue, repository: repo, user: repo.owner
      pr = create :pull_request, :disable_disk_access, issue: issue, repository: repo, user: repo.owner
      pr.destroy!
      issue.reload
      output = Api::Serializer.serialize(:issue_hash, issue)
      refute output.key?("pull_request")
    end

    test "includes draft property for PR returned from issues search endpoint" do
      api_media_type "application/vnd.github.shadow-cat-preview+json"
      options = { search: true }
      output = T.unsafe(self).issue(@pull_issue, options)
      assert output.key?("draft")
    end

    test "renders v3 format by default" do
      api_media_type "application/vnd.github.json"

      output = T.unsafe(self).issue(@issue)
      refute output.key?("pull_request"),
        "Expected v3 output to omit 'pull_request' property"
    end

    test "body_html renders task lists" do
      body = <<-MD
- [ ] one
- [ ] two
- [ ] three
      MD
      @issue.update body: body

      # api_media_type 'application/vnd.github.v3.html+json' # FIXME: should work
      output = T.unsafe(self).issue(@issue, mime_params: Set[:html])

      assert output.key?("body_html"), "body_html expected"
      doc = Nokogiri::HTML(output["body_html"])
      assert_equal 3, doc.css("ul.contains-task-list li.task-list-item input.task-list-item-checkbox[disabled]").size
    end

    test "body_html renders task lists in comments" do
      body = <<-MD
- [ ] one
- [ ] two
- [ ] three
      MD
      comment = @issue.comments.create body: body, user: @owner
      comment.react(content: "heart", actor: create(:user))

      # api_media_type 'application/vnd.github.v3.html+json' # FIXME: should work
      output = T.unsafe(self).issue_comment(comment, mime_params: Set[:html])

      assert output.key?("body_html"), "body_html expected"
      doc = Nokogiri::HTML(output["body_html"])
      assert_equal 3, doc.css("ul.contains-task-list li.task-list-item input.task-list-item-checkbox[disabled]").size
    end
  end

  context "#milestone_hash" do
    test "returns properly formatted URLs" do
      output = T.unsafe(self).milestone(@milestone)


      html_milestone_path = "/#{@owner}/#{@repo}/milestone/#{@milestone.number}"
      api_milestone_path = "/repos/#{@owner}/#{@repo}/milestones/#{@milestone.number}".dup
      api_milestone_path.prepend "/api/v3" if GitHub.enterprise?

      assert_equal html_milestone_path, URI.parse(output["html_url"]).path
      assert_equal api_milestone_path, URI.parse(output["url"]).path
      assert_equal "#{api_milestone_path}/labels", URI.parse(output["labels_url"]).path
    end
  end

  context "#review request hash" do
    test "returns correct event hashes" do
      @review_request_event = @pull.events.create!(subject: @owner, actor: @forker, event: "review_requested")
      @remove_review_request_event = @pull.events.create!(subject: @forker, actor: @owner, event: "review_request_removed")

      output = T.unsafe(self).issue_event(@review_request_event)
      assert_equal @forker.login, output["review_requester"]["login"]
      assert_equal @owner.login, output["requested_reviewer"]["login"]

      output = T.unsafe(self).issue_event(@remove_review_request_event)
      assert_equal @owner.login, output["review_requester"]["login"]
      assert_equal @forker.login, output["requested_reviewer"]["login"]
    end

    test "returns correct team in event hashes" do
      @review_request_event = @pull.events.create!(subject: @team, actor: @forker, event: "review_requested")
      @remove_review_request_event = @pull.events.create!(subject: @team, actor: @owner, event: "review_request_removed")

      output = T.unsafe(self).issue_event(@review_request_event)
      assert_equal @forker.login, output["review_requester"]["login"]
      assert_equal @team.name, output["requested_team"]["name"]

      output = T.unsafe(self).issue_event(@remove_review_request_event)
      assert_equal @owner.login, output["review_requester"]["login"]
      assert_equal @team.name, output["requested_team"]["name"]
    end
  end

  context "#dismissed review hash" do
    test "returns correct event hashes" do
      @dismissed_review_event = @pull.events.create!(actor: @owner, event: "review_dismissed",
      pull_request_review_state_was: 1, pull_request_review_id: 2034, message: "a message")

      output = T.unsafe(self).issue_event(@dismissed_review_event)
      assert_equal "commented", output["dismissed_review"]["state"]
      assert_equal 2034, output["dismissed_review"]["review_id"]
      assert_equal "a message", output["dismissed_review"]["dismissal_message"]
      assert_nil output["dismissed_review"]["dismissal_commit_id"]
    end

    test "returns correct event hashes with a commit ID" do
      @dismissed_review_event = @pull.events.create!(actor: @owner, event: "review_dismissed",
      pull_request_review_state_was: 40, pull_request_review_id: 2034, message: "a message", after_commit_oid: "3456")

      output = T.unsafe(self).issue_event(@dismissed_review_event)
      assert_equal "approved", output["dismissed_review"]["state"]
      assert_equal 2034, output["dismissed_review"]["review_id"]
      assert_equal "a message", output["dismissed_review"]["dismissal_message"]
      assert_equal "3456", output["dismissed_review"]["dismissal_commit_id"]
    end
  end

  context "#issue_comment_hash" do
    test "payload with reactions is valid" do
      @comment.react(content: "heart", actor: create(:user))

      output = T.unsafe(self).issue_comment(@comment)
      assert output.key?("reactions")
    end

    test "payload with performed_via_github_app is valid" do
      installation = make_integration_installation(repository: @repo, permissions: { "issues" => :write })
      comment = create(:issue_comment, performed_via_integration: installation.integration)

      api_media_type "application/vnd.github.machine-man-preview+json"
      output = T.unsafe(self).issue_comment(comment)
      assert output.key?("performed_via_github_app")
    end
  end

  context "#graphql_issue_comment_hash" do
    test "payload with reactions is valid" do
      @comment.react(content: "heart", actor: create(:user))

      variables = {
        id: @comment.global_relay_id,
        includeBody: true,
        includeBodyHTML: true,
        includeBodyText: true,
        includePerformedViaGitHubApp: false,
      }

      results = Api::App::PlatformClient.query(IssueCommentQuery, variables: variables, context: { viewer: @user })
      output = T.unsafe(self).graphql_issue_comment(results.data.node)
      assert output.key?("reactions")
    end

    test "payload with performed_via_github_app is valid" do
      installation = make_integration_installation(repository: @repo, permissions: { "issues" => :write })
      comment = create(:issue_comment, performed_via_integration: installation.integration)
      comment.react(content: "heart", actor: create(:user))

      variables = {
        id: comment.global_relay_id,
        includeBody: true,
        includeBodyHTML: true,
        includeBodyText: true,
        includePerformedViaGitHubApp: true,
      }

      results = Api::App::PlatformClient.query(IssueCommentQuery, variables: variables, context: { viewer: @user })
      api_media_type "application/vnd.github.machine-man-preview+json"
      output = T.unsafe(self).graphql_issue_comment(results.data.node)

      assert output.key?("performed_via_github_app")
      assert output.key?("reactions")
    end
  end

  context "#issue_timeline_hash" do
    test "payload is valid" do
      timeline_item = @pull.timeline_for(@owner, all_valid_events: true).first
      output        = T.unsafe(self).issue_timeline(timeline_item, repo: @repo)
      refute_nil timeline_item
      refute_nil output
    end
  end

  context "#label_hash" do
    test "payload is valid" do
      output = T.unsafe(self).label(@label)
      assert_equal "A problem", output["description"]
    end
  end
end
