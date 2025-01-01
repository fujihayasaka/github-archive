# typed: true
# frozen_string_literal: true

require "test_helper"

class PrefilledIssueFieldsTest < GitHub::TestCase
  include MemexHelpers

  setup do
    @user = create(:user)
    @repo = create(:repository, has_discussions: true, owner: @user)
    @discussion = create(:discussion, repository: @repo, body: "lunch at chez maman")
    @discussion_body = DiscussionOpTextFormatter.new(@discussion).format

    @repo_with_templates = create(:repository, from_example: :dot_github)
    commit = @repo_with_templates.commits.create({ message: "Add files", author: @repo_with_templates.owner }) do |files|
      files.add ".github/ISSUE_TEMPLATE/cats.yml", <<~YAML
        name: All about cats
        about: Tell me about your favorite cats
        inputs:
          - type: input
            attributes:
              label: cats name
      YAML
    end

    begin
      @repo_with_templates.refs["refs/heads/master"].update(commit, @repo_with_templates.owner)
    rescue GitHub::DGit::ThreepcFailedToLock
      # Overloaded CI workers seems to cause problems with updating Git repositories in tests where Spokes is enabled.
      # We've not yet been able to fix the root cause, so as a workaround we ignore locking errors when this test is run in CI.
      skip "Failed to lock repository." if TestEnv.github_ci?
      raise
    end

    MemexHelpers.setup_organization_wide_access_for_projects("project_writer")
  end

  def make_fields(repo: @repo, **params)
    PrefilledIssueFields.new(params: params, repository: repo, user: @user)
  end

  context "#title" do
    test "prefills title" do
      assert_equal "goldfish", make_fields(title: "goldfish").title
    end

    test "prefills title from discussion" do
      fields = make_fields(created_from_discussion_number: @discussion.number)
      assert_equal @discussion.title, fields.title
    end

    test "does not prefill title from discussion if discussions are not on" do
      @repo.turn_off_discussions(actor: @repo.owner)
      refute_predicate @repo, :discussions_on?

      fields = make_fields(created_from_discussion_number: @discussion.number)
      assert_nil fields.title
    end

    test "title param takes precedence over discussion" do
      fields = make_fields(
        title: "Sangonomiya Kokomi",
        created_from_discussion_number: @discussion.number,
      )
      assert_equal "Sangonomiya Kokomi", fields.title
    end

    if GitHub.spamminess_check_enabled?
      test "does not prefill title from spammy discussion" do
        spammy_discussion = create(:spammy_discussion, repository: @repo)
        fields = make_fields(created_from_discussion_number: spammy_discussion.number)
        assert_nil fields.title
      end
    end

    test "does not prefill title if discussion does not exist" do
      fields = make_fields(created_from_discussion_number: 99999)
      assert_nil fields.title
    end
  end

  test "prefills template" do
    assert_equal "help.md", make_fields(template: "help.md").template
  end

  context "body" do
    test "prefills body from params[:body]" do
      assert_equal "scrabble", make_fields(body: "scrabble").body
    end

    test "prefills body from params[:permalink]" do
      assert_equal "link", make_fields(body: "link").body
    end

    test "prefills body from params[:body] and params[:permalink], one then the other" do
      fields = make_fields(body: "scrabble", permalink: "link")
      assert_equal "scrabble\n\nlink", fields.body
    end

    test "is nil otherwise" do
      assert_nil make_fields.body
    end

    test "prefills body from discussion" do
      fields = make_fields(created_from_discussion_number: @discussion.number)
      assert_equal @discussion_body, fields.body
    end

    test "does not prefill body from discussion if discussions are not on" do
      @repo.turn_off_discussions(actor: @repo.owner)
      refute_predicate @repo, :discussions_on?

      fields = make_fields(created_from_discussion_number: @discussion.number)
      assert_nil fields.body
    end

    test "includes both body, discussion body, and permalink" do
      fields = make_fields(
        body: "cool body",
        created_from_discussion_number: @discussion.number,
        permalink: "link",
      )
      expected = "cool body\n\n#{@discussion_body}\n\nlink"
      assert_equal expected, fields.body
    end

    if GitHub.spamminess_check_enabled?
      test "does not prefill body from spammy discussion" do
        spammy_discussion = create(:spammy_discussion, repository: @repo)
        fields = make_fields(created_from_discussion_number: spammy_discussion.number)
        assert_nil fields.body
      end
    end

    test "does not prefill body if discussion does not exist" do
      fields = make_fields(created_from_discussion_number: 99999)
      assert_nil fields.body
    end
  end

  context "assignees" do
    test "prefills from assignee" do
      assert_equal [@user], make_fields(assignee: @user.login).assignees
    end

    test "prefills from assignees" do
      assert_equal [@user], make_fields(assignees: @user.login).assignees
    end

    test "prefills multiple users from assignees" do
      user = create(:user)
      @repo.add_member(user)
      assert_same_elements [@user, user], make_fields(assignees: [@user.login, user.login].join(",")).assignees
    end

    test "prefills up to 10 assignees" do
      assignees = []
      11.times do
        assignees << create(:user).tap { |u| @repo.add_member(u) }
      end
      fields = make_fields(assignees: assignees.map(&:login).join(","))
      assert_same_elements assignees.first(10), fields.assignees
    end

    test "doesn't prefill users without write access" do
      user = create(:user)
      assert_equal [], make_fields(assignees: user.login).assignees
    end
  end

  context "milestones" do
    test "prefills by number" do
      ms = create(:milestone, repository: @repo)
      assert_equal ms, make_fields(milestone: ms.number.to_s).milestone
    end

    test "prefills by name" do
      ms = create(:milestone, repository: @repo)
      assert_equal ms, make_fields(milestone: ms.title).milestone
    end

    test "doesn't prefill milestones for another repository" do
      ms = create :milestone
      assert_nil make_fields(milestone: ms.number.to_s).milestone
    end
  end

  context "labels" do
    test "prefills labels" do
      label = create(:label, repository: @repo)
      assert_equal [label], make_fields(labels: label.name).labels
    end

    test "prefills up to 20 labels" do
      labels = []
      21.times { labels << create(:label, repository: @repo) }
      fields = make_fields(labels: labels.map(&:name).join(","))
      assert_equal labels.first(20).sort, fields.labels.sort
    end

    test "doesn't prefill labels for another repository" do
      this_label = create(:label, repository: @repo)
      that_label = create(:label)
      assert_equal [this_label], make_fields(labels: [this_label.name, that_label.name].join(",")).labels
    end

    test "prefills labels from discussion" do
      label = create(:label, repository: @repo)
      @discussion.replace_labels([label])
      assert_equal [label], @discussion.labels

      fields = make_fields(created_from_discussion_number: @discussion.number)
      assert_equal [label], fields.labels
    end

    test "labels param takes precedence over discussion" do
      label = create(:label, repository: @repo)
      other_label = create(:label, repository: @repo)
      @discussion.replace_labels([label])
      assert_equal [label], @discussion.labels

      fields = make_fields(
        created_from_discussion_number: @discussion.number,
        labels: other_label.name,
      )
      assert_equal [other_label], fields.labels
    end

    if GitHub.spamminess_check_enabled?
      test "does not prefill body from spammy discussion" do
        spammy_discussion = create(:spammy_discussion, repository: @repo)
        label = create(:label, repository: @repo)
        spammy_discussion.replace_labels([label])
        assert_equal [label], spammy_discussion.labels

        fields = make_fields(created_from_discussion_number: spammy_discussion.number)
        assert_empty fields.labels
      end
    end

    test "does not prefill labels if discussion does not exist" do
      fields = make_fields(created_from_discussion_number: 99999)
      assert_empty fields.labels
    end
  end

  context "projects" do
    test "prefills a repository project" do
      project = create(:project, owner: @repo)
      fields = make_fields(projects: "#{@repo.nwo}/#{project.number}")
      assert_equal [project], fields.projects
    end

    test "prefills an organization project" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      org.add_member(@user)
      repo.add_member(@user)
      org_project = create(:project, owner: org)
      repo_project = create(:project, owner: repo)

      fields = make_fields(projects: "#{org.name}/#{org_project.number},#{repo.nwo}/#{repo_project.number}", repo: repo)
      assert_same_elements [org_project, repo_project], fields.projects
    end

    test "prefills a user-owned project" do
      repo = create(:repository, owner: @user)
      user_project = create(:project, owner: @user)

      fields = make_fields(projects: "#{@user.login}/#{user_project.number}", repo: repo)
      assert_equal [user_project], fields.projects
    end

    test "prefills an organization and a repository project for the same organization" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      org.add_member(@user)
      repo.add_member(@user)
      org_project = create(:project, owner: org)
      repo_project = create(:project, owner: repo)

      fields = make_fields(projects: "#{org.name}/#{org_project.number},#{repo.nwo}/#{repo_project.number}", repo: repo)
      assert_same_elements [org_project, repo_project], fields.projects
    end

    test "prefills up to 20 projects" do
      org = create(:organization)
      org.add_member(@user)
      repo = create(:repository, owner: org)

      projects = []
      21.times { projects << create(:project, owner: org) }

      fields = make_fields(projects: projects.map { |p| "#{org.login}/#{p.number}" }.join(","), repo: repo)
      assert_equal projects.first(20), fields.projects
    end

    test "doesn't prefill a project the user can't write to" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      repo.add_member(@user)
      this_project = create(:project, owner: repo)
      that_project = create(:project, owner: org)

      fields = make_fields(projects: "#{repo.nwo}/#{this_project.number},#{org.login}/#{that_project.number}", repo: repo)
      assert_equal [this_project], fields.projects
    end

    test "doesn't prefill a project for a different repository" do
      org = create(:organization)
      org.add_member(@user)

      this_repo = create(:repository, owner: org)
      this_repo.add_member(@user, action: :write)
      this_project = create(:project, owner: this_repo)

      that_repo = create(:repository)
      that_repo.add_member(@user, action: :write)
      that_project = create(:project, owner: that_repo)

      fields = make_fields(projects: "#{this_repo.nwo}/#{this_project.number},#{that_repo.nwo}/#{that_project.number}", repo: this_repo)
      assert_equal [this_project], fields.projects
    end

    test "doesn't prefill a project for a different organization" do
      this_org = create(:organization)
      this_org.add_member(@user)
      this_project = create(:project, owner: this_org)
      repo = create(:repository, owner: this_org)

      that_org = create(:organization)
      that_org.add_member(@user)
      that_project = create(:project, owner: that_org)

      fields = make_fields(projects: "#{this_org.login}/#{this_project.number},#{that_org.login}/#{that_project.number}", repo: repo)
      assert_equal [this_project], fields.projects
    end
  end

  context "memex projects" do
    test "prefills an organization memex project" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      org.add_member(@user)
      repo.add_member(@user)

      org_project = create(:memex_project, owner: org)

      fields = make_fields(projects: "#{org.login}/#{org_project.number}", repo: repo)
      assert_equal [org_project], fields.memex_projects
    end

    test "prefills up to 20 projects" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      org.add_member(@user)
      repo.add_member(@user)

      projects = []
      21.times { projects << create(:memex_project, owner: org) }

      fields = make_fields(projects: projects.map { |p| "#{org.login}/#{p.number}" }.join(","), repo: repo)
      assert_equal projects.first(20), fields.memex_projects
    end

    test "doesn't prefill a project the user can't write to" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      org.add_member(@user)
      repo.add_member(@user)

      MemexHelpers::setup_organization_wide_access_for_projects("none", "User", org.id)

      writable_memex = create(:memex_project, owner: org)
      writable_memex.grant_role(@user, Role.project_writer_role)

      non_writable_memex = create(:memex_project, owner: org)

      fields = make_fields(projects: "#{org.login}/#{writable_memex.number},#{org.login}/#{non_writable_memex.number}", repo: repo)
      assert_equal [writable_memex], fields.memex_projects
    end

    test "doesn't prefill a deleted project" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      org.add_member(@user)
      repo.add_member(@user)

      this_project = create(:memex_project, owner: org)
      that_project = create(:memex_project, owner: org)
      that_project.soft_delete!(@user)

      fields = make_fields(projects: "#{org.login}/#{this_project.number},#{org.login}/#{that_project.number}", repo: repo)

      assert_equal 1, fields.memex_projects.length
      assert_equal [this_project], fields.memex_projects
    end

    test "prefills memex projects from the repo owner if user has write access" do
      user2 = create(:user)
      org1 = create(:organization)
      repo = create(:repository, owner: org1)
      org1.add_member(@user)
      repo.add_member(@user)
      org1_project1 = create(:memex_project, owner: org1)
      org1_project2 = create(:memex_project, owner: org1)
      user_project = create(:memex_project, owner: @user)
      user2_project = create(:memex_project, :with_writer, writer: @user, owner: user2, title: "abcde")
      user2_project2 = create(:memex_project, owner: user2)

      MemexHelpers::setup_organization_wide_access("project_reader", org1_project2)

      org2 = create(:organization)
      org2.add_member(@user)

      org2_project1 = create(:memex_project, owner: org2)
      org2_project2 = create(:memex_project, owner: org2)

      fields = make_fields(projects: "#{org1.login}/#{org1_project1.number},#{org1.login}/#{org1_project2.number},#{org2.login}/#{org2_project1.number},#{org2.login}/#{org2_project2.number}, #{@user.login}/#{user_project.number}, #{user2.login}/#{user2_project.number}, #{user2.login}/#{user2_project2.number}", repo: repo)
      assert_same_elements [org1_project1], fields.memex_projects
    end

    test "doesn't prefill user project from other users even if they have access" do
      repo = create(:repository, owner: @user)
      user_project = create(:memex_project, owner: @user)
      user2 = create(:user)
      user2_project = create(:memex_project, owner: user2)
      user2_project.grant_role(@user, Role.project_writer_role)

      fields = make_fields(projects: "#{user2.login}/#{user2_project.number},#{@user.login}/#{user_project.number}", repo: repo)
      assert_equal [user_project], fields.memex_projects
    end

    test "adds a warning if loading memex projects fails" do
      repo = create(:repository, owner: @user)
      user_project = create(:memex_project, owner: @user)

      User
        .any_instance
        .expects(:memex_projects)
        .raises(ActiveRecord::ActiveRecordError)

      fields = make_fields(projects: "#{@user.login}/#{user_project.number}", repo: repo)
      projects = fields.memex_projects

      assert_equal([], projects)
      assert_equal({ attribute: :memex_projects, type: :database_error }, fields.warnings[0])
    end
  end

  context "issue forms" do
    test "captures extra param data" do
      fields = make_fields(cats_name: "jackson", repo: @repo_with_templates)
      extra_fields = { cats_name: "jackson" }
      assert_equal extra_fields, fields.structured_template_inputs
    end

    test "captures extra param data only" do
      fields = make_fields(cats_name: "jackson", cats_color: "orange", body: "meow", repo: @repo_with_templates)
      extra_fields = { cats_name: "jackson", cats_color: "orange" }
      assert_equal extra_fields, fields.structured_template_inputs
    end
  end
end
