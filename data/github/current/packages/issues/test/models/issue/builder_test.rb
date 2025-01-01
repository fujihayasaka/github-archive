# typed: true
# frozen_string_literal: true
#
# The behaviour tested below was moved from
# AbstractRepositoryController.build_issue to Issue::Builder.build
#
# These tests attempt to capture (and define (and test!)) the behaviour
# inherited from the original build_issue. While we think they accurately
# represent the way github.com currently operates, they shouldn't necessarily
# be seen as an endorsement of that behaviour - it has evolved over time, and
# is likely to have picked up unexpected behaviours along the way.
#
# If you find something not working as expected, but that is defined below as
# an expected way for Issue::Builder.build to operate, you should feel free to
# correct that behaviour and adjust the test

require "test_helper"

class IssueBuilderTest < GitHub::TestCase
  def write_template(repo, name, config)
    commit = repo.commits.create({ message: "Add file", committer: repo.owner }) do |files|
      files.add ".github/ISSUE_TEMPLATE/#{name}", config
    end
    repo.refs["refs/heads/master"].update(commit, repo.owner)
  end

  def create_issue_template(repo:, name:, labels: "", assignees: "")
    write_template repo, name, <<~MARKDOWN
    ---
    name: Bug report
    about: It's a bug
    labels: #{labels}
    assignees: #{assignees}
    ---
    This is a bug.
    MARKDOWN
  end

  def setup
    @repo = create(:repository, from_example: :simple)
    @owner = @repo.owner

    @collaborator = create(:user)
    @repo.add_member(@collaborator)

    @open_milestone = create(:milestone, title: "open-milestone", repository: @repo, created_by: @owner, state: "open")

    @label = @repo.labels.create(name: "Features")
    @label2 = @repo.labels.create(name: "Bugs")

    @default_issue_builder = Issue::Builder.new(@owner, @repo)
  end

  context "create an issue" do
    test "works" do
      issue = @default_issue_builder.build(issue: { title: "what", body: "whoami" })

      refute_nil issue
    end

    test "can create with a single assignee login" do
      issue = @default_issue_builder.build(issue: { title: "what", body: "whoami", assignee: @owner.login })

      assert_same_elements [@owner], issue.assignees
    end

    test "can create with a single assignee id" do
      issue = @default_issue_builder.build(issue: { title: "what", body: "whoami", assignee_id: @owner.id })

      assert_same_elements [@owner], issue.assignees
    end

    test "assignee_id field takes precedence" do
      issue = @default_issue_builder.build(issue: { title: "what", body: "whoami", assignee: @owner.login, assignee_id: @collaborator.id })

      assert_same_elements [@collaborator], issue.assignees
    end

    test "can create with an assignee" do
      issue = @default_issue_builder.build(issue: { title: "what", body: "whoami", user_assignee_ids: [@owner.id] })

      assert_same_elements [@owner], issue.assignees
    end

    test "can create with multiple assignees" do
      assignees = [@owner, @collaborator]
      issue = @default_issue_builder.build(issue: { title: "what", body: "whoami", user_assignee_ids: assignees.map(&:id) })

      assert_same_elements assignees, issue.assignees
    end

    test "assignees overwrites assignee" do
      issue = @default_issue_builder.build(issue: { title: "what", body: "whoami", assignee_id: @owner.id, user_assignee_ids: [@collaborator.id] })

      assert_equal @collaborator, issue.assignee
      assert_same_elements [@collaborator], issue.assignees
    end

    test "can set single label with :labels field" do
      issue = @default_issue_builder.build(issue: { title: "what", body: "whoami", labels: [@label.id] })

      assert_same_elements [@label], issue.labels
    end

    test "can set single label with :label_ids field" do
      issue = @default_issue_builder.build(issue: { title: "what", body: "whoami", label_ids: [@label.id] })

      assert_same_elements [@label], issue.labels
    end

    test "can set multiple labels with :labels field" do
      labels = [@label, @label2]
      issue = @default_issue_builder.build(issue: { title: "what", body: "whoami", labels: labels.map(&:id) })

      assert_same_elements labels, issue.labels
    end

    test "can set multiple labels with :label_ids field" do
      labels = [@label, @label2]
      issue = @default_issue_builder.build(issue: { title: "what", body: "whoami", label_ids: labels.map(&:id) })

      assert_same_elements labels, issue.labels
    end

    test "label_ids field takes precedence" do
      issue = @default_issue_builder.build(issue: { title: "what", body: "whoami", labels: [@label.id], label_ids: [@label2.id] })

      assert_same_elements [@label2], issue.labels
    end

    test "does not add labels from label_ids if user does not have permission to add labels" do
      user = create(:user)
      builder = Issue::Builder.new(user, @repo)
      issue = builder.build(issue: { title: "what", body: "whoami", label_ids: [@label2.id] })
      refute issue.labelable_by?(actor: user)

      assert_empty issue.labels
    end

    test "does not add labels from labels if user does not have permission to add labels" do
      user = create(:user)
      builder = Issue::Builder.new(user, @repo)
      issue = builder.build(issue: { title: "what", body: "whoami", labels: [@label.id] })
      refute issue.labelable_by?(actor: user)

      assert_empty issue.labels
    end

    test "can create with projects" do
      project = create(:project, owner: @repo)
      project_not_to_add = create(:project, owner: @repo)

      issue = @default_issue_builder.build(issue: { title: "Hello" }, issue_project_ids: {
        project.id.to_s => "on",
        project_not_to_add.id.to_s => "",
      })

      assert issue.save
      assert_same_elements [project], issue.projects
    end

    test "can create a new issue in an existing milestone" do
      issue = @default_issue_builder.build(issue: { title: "what" }, milestone: @open_milestone.id.to_s)

      assert_equal @open_milestone, issue.milestone
    end

    test "users with read-only access can create from issue templates with labels" do
      template_name = "bugs.md"
      create_issue_template(repo: @repo, name: template_name, labels: @label.name)
      read_only_user = create(:user, login: "read-only-user")

      issue_builder = Issue::Builder.new(read_only_user, @repo)
      issue = issue_builder.build(issue: { title: "what", body: "whoami", body_template_name: template_name })

      assert_equal template_name, issue.body_template_name
      assert_same_elements [@label], issue.labels
    end

    test "users with read-only access can create from issue templates with labels from global repo" do
      global_repo = create(:repository, name: ".github", owner: @owner, from_example: :simple)
      label = global_repo.labels.create(name: @label.name)

      template_name = "bugs.md"
      create_issue_template(repo: global_repo, name: template_name, labels: label.name)
      read_only_user = create(:user, login: "read-only-user")

      issue_builder = Issue::Builder.new(read_only_user, @repo)
      issue = issue_builder.build(issue: { title: "what", body: "whoami", body_template_name: template_name })

      assert_equal template_name, issue.body_template_name
      assert_same_elements [@label], issue.labels
      assert issue.labels.all? { |l| l.repository_id == @repo.id }
    end

    test "users with read-only access can create from issue templates with empty labels from global repo" do
      global_repo = create(:repository, name: ".github", owner: @owner, from_example: :simple)

      template_name = "bugs.md"
      create_issue_template(repo: global_repo, name: template_name)
      read_only_user = create(:user, login: "read-only-user")

      issue_builder = Issue::Builder.new(read_only_user, @repo)
      issue = issue_builder.build(issue: { title: "what", body: "whoami", body_template_name: template_name })

      assert_equal template_name, issue.body_template_name
      assert_same_elements [], issue.labels
    end

    test "users with read-only access can create from issue templates with assignees" do
      template_name = "bugs.md"
      create_issue_template(repo: @repo, name: template_name, assignees: @collaborator.name)
      read_only_user = create(:user, login: "read-only-user")

      issue_builder = Issue::Builder.new(read_only_user, @repo)
      issue = issue_builder.build(issue: { title: "what", body: "whoami", body_template_name: template_name })

      assert_equal template_name, issue.body_template_name
      assert_same_elements [@collaborator], issue.assignees
    end

    test "users with write access can create from params and not from issue template" do
      default_assignee = create(:user)
      @repo.add_member default_assignee
      template_name = "bugs.md"
      create_issue_template(repo: @repo, name: template_name, labels: @label.name, assignees: default_assignee.name)

      issue = @default_issue_builder.build(issue:
        {
          title: "what",
          body: "whoami",
          label_ids: [@label2.id],
          user_assignee_ids: [@collaborator.id],
          body_template_name: template_name,
        },
      )

      assert_same_elements [@label2], issue.labels
      assert_same_elements [@collaborator], issue.assignees
    end

    test "triage user can set title, body, assignees, labels, and milestones" do
      org = create :business_plus_organization, admin: @owner
      org_repo = create(:repository, owner: org, name: "my org")
      milestone = create(:milestone, repository: org_repo, title: "milestone")
      label = create(:label, repository: org_repo, name: "bug")

      triage_user = create(:user)
      org_repo.add_member(triage_user, action: :triage)

      issue_builder = Issue::Builder.new(triage_user, org_repo)
      issue = issue_builder.build(issue:
        {
          title: "what",
          body: "whoami",
          label_ids: [label.id],
          user_assignee_ids: [triage_user.id],
        },
        milestone: milestone.id.to_s,
      )

      assert_equal "what", issue.title
      assert_equal "whoami", issue.body
      assert_same_elements [label], issue.labels
      assert_same_elements [triage_user], issue.assignees
      assert_equal milestone, issue.milestone
    end

    test "triage user can customize title, body, labels and assignees when using issue templates" do
      org = create :business_plus_organization, admin: @owner
      org_repo = create(:repository, owner: org, name: "my org", from_example: :simple)

      triage_user = create(:user)
      org_repo.add_member(triage_user, action: :triage)
      label1 = create(:label, repository: org_repo, name: "label1")
      label2 = create(:label, repository: org_repo, name: "label2")

      template_name = "bugs.md"
      create_issue_template(repo: org_repo, name: template_name, labels: label1.name, assignees: triage_user.name)

      issue_builder = Issue::Builder.new(triage_user, org_repo)
      issue = issue_builder.build(issue:
        {
          title: "what",
          body: "whoami",
          body_template_name: template_name,
          label_ids: [label2.id],
          user_assignee_ids: [],
        })

      issue.save!

      assert_equal "what", issue.title
      assert_equal "whoami", issue.body
      assert_same_elements [label2], issue.labels
      assert_same_elements [], issue.assignees
    end

    test "read-only user can only set title and body" do
      read_only_user = create(:user, login: "read-only-user")

      issue_builder = Issue::Builder.new(read_only_user, @repo)
      issue = issue_builder.build(issue:
        {
          title: "what",
          body: "whoami",
          label_ids: [@label.id],
          user_assignee_ids: [@collaborator.id],
        },
        milestone: @open_milestone.id.to_s,
      )

      assert_equal "what", issue.title
      assert_equal "whoami", issue.body
      assert_equal [], issue.labels
      assert_equal [], issue.assignees
      assert_nil issue.milestone
    end

    test "user_id param is ignored" do
      issue = @default_issue_builder.build(issue: { title: "Hello" }, user_id: @collaborator.id)

      assert @owner, issue.user
    end

    test "repository_id param is ignored" do
      other_repo  = create(:repository, owner: @owner)

      issue = @default_issue_builder.build(issue: { title: "Hello" }, repository_id: other_repo.id)

      assert @repo, issue.repository
    end

    test "user_id and repository_id params are ignored together" do
      other_repo  = create(:repository, owner: @owner)

      issue = @default_issue_builder.build(issue: { title: "Hello" }, user_id: @collaborator.id, repository_id: other_repo.id)

      assert @owner, issue.user
      assert @repo, issue.repository
    end

    test "should log number of projects issue was added to on create" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      project_one = create(:project, owner: @repo)
      project_two = create(:project, owner: @repo)

      issue = @default_issue_builder.build(issue: { title: "Hello" }, issue_project_ids: {
        project_one.id.to_s => "on",
        project_two.id.to_s => "on",
      })

      assert issue.save
      assert_same_elements [project_one, project_two], issue.projects

      assert_equal 2, GitHub.dogstats.counts("pending_card.created_during_issue_creation").first.value
    end

    test "overwrites body with structured format if using structured issue templates that does not allow body" do
      template_name = "bugs.yaml"
      write_template @repo, template_name, <<~YAML
        ---
        name: Bug report
        body:
        - type: textarea
          attributes:
            label: "Neighbor?"
      YAML

      issue = @default_issue_builder.build(issue: { title: "cats", body_template_name: template_name, body: "the musical" }, issue_form: {
        "#{Digest::SHA256.hexdigest("Neighbor?")}" => "Totoro"
      })
      assert issue.save
      expected = <<~TXT.chomp
        ### Neighbor?

        Totoro
      TXT
      assert_equal expected, issue.body
    end

    test "does not append body with structured format if using structured issue templates" do
      template_name = "bugs.yaml"
      write_template @repo, template_name, <<~YAML
        name: Bug report
        body:
        - type: textarea
          attributes:
            label: "Neighbor?"
      YAML

      issue = @default_issue_builder.build(issue: { title: "cats", body_template_name: template_name, body: "the musical" }, issue_form: { "#{Digest::SHA256.hexdigest("Neighbor?")}" => "Totoro" })
      assert issue.save
      expected = <<~TXT.chomp
        ### Neighbor?

        Totoro
      TXT
      assert_equal expected, issue.body
    end

    test "does not invoke StructuredTemplates::BodyBuilder or overwrite body if template is not structured" do
      template_name = "bugs.md"
      create_issue_template(repo: @repo, name: template_name, labels: @label.name)

      StructuredTemplates::BodyBuilder.any_instance.stubs(:to_markdown).returns("meow")

      issue = @default_issue_builder.build(issue: { title: "cats", body_template_name: template_name, body: "the musical" }, issue_form: { "#{Digest::SHA256.hexdigest("Neighbor?")}" => "Totoro" })
      template = @repo.preferred_issue_templates[template_name]
      refute_predicate template, :structured?

      assert_equal "the musical", issue.body
    end
  end

  context "issue type" do
    test "creates an issue with an issue type" do
      GitHub.flipper[:issue_types].enable
      user = create(:user)
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      repo.add_member(user, action: :write)

      issue_type = org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])

      issue = Issue::Builder.new(user, repo).build(issue: { title: "test", issue_type_id: issue_type.id })

      refute_nil issue
      assert_equal issue_type, issue.issue_type
    end

    test "creates an issue without the type if the issue type is disabled" do
      GitHub.flipper[:issue_types].enable
      user = create(:user)
      org = create(:organization, admin: user)
      repo = create(:repository, owner: org)

      issue_type = org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
      issue_type.update(enabled: false)

      issue = Issue::Builder.new(user, repo).build(issue: { title: "test", issue_type_id: issue_type.id })

      refute_nil issue
      assert_nil issue.issue_type
    end

    test "creates an issue without the type if the issue type doesn't belong to the same owner as the repository" do
      GitHub.flipper[:issue_types].enable
      user = create(:user)
      org = create(:organization, admin: user)
      repo = create(:repository, owner: org)

      different_org = create(:organization, admin: @user)
      issue_type = different_org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])

      issue = Issue::Builder.new(user, repo).build(issue: { title: "test", issue_type_id: issue_type.id })

      refute_nil issue
      assert_nil issue.issue_type
    end

    test "creates an issue without the type if the user doesn't have permissions to set the type" do
      GitHub.flipper[:issue_types].enable
      user = create(:user)
      org = create(:organization)
      org.add_member(user)

      repo = create(:repository, owner: org)
      repo.add_member(user, action: :read)
      issue_type = org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])

      issue = Issue::Builder.new(user, repo).build(issue: { title: "test", issue_type_id: issue_type.id })

      refute_nil issue
      assert_nil issue.issue_type
    end


    test "creates an issue without the type if the organization is not feature flagged into issue types" do
      GitHub.flipper[:issue_types].disable
      user = create(:user)
      org = create(:organization, admin: user)
      repo = create(:repository, owner: org)

      issue_type = org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
      issue = Issue::Builder.new(user, repo).build(issue: { title: "test", issue_type_id: issue_type.id })

      refute_nil issue
      assert_nil issue.issue_type
    end
  end
end
