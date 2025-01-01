# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPullRequestTemplatesTest < GitHub::TestCase
  fixtures do
    @user = create :user
    @org = create :organization
  end

  test "returns templates as found in the repo" do
    local_repo = create :repository, owner: @user, name: "local"
    add_pr_template(local_repo, @user, "local_template.md")

    local_templates = local_repo.pull_request_templates

    assert_equal "local_template.md", local_templates.first.filename
  end

  context "when org templates exist" do
    test "returns org templates if org-owned repo doesn't have any" do
      global_repo = create :repository, owner: @org, name: ".github"
      local_repo = create :repository, owner: @org, name: "local"
      add_pr_template(global_repo, @user, "global_template.md")

      global_templates = global_repo.pull_request_templates
      local_templates = local_repo.pull_request_templates

      assert_equal "global_template.md", local_templates.first.filename
    end

    test "returns repo templates if they exist" do
      global_repo = create :repository, owner: @org, name: ".github"
      local_repo = create :repository, owner: @org, name: "local"
      add_pr_template(global_repo, @user, "global_template.md")
      add_pr_template(local_repo, @user, "local_template.md")

      global_templates = global_repo.pull_request_templates
      local_templates = local_repo.pull_request_templates

      assert_equal 1, local_templates.count
      assert_equal "local_template.md", local_templates.first.filename
    end
  end

  context "when user templates exist" do
    test "returns user templates if user-owned repo doesn't have any" do
      global_repo = create :repository, owner: @user, name: ".github"
      local_repo = create :repository, owner: @user, name: "local"
      add_pr_template(global_repo, @user, "global_template.md")

      global_templates = global_repo.pull_request_templates
      local_templates = local_repo.pull_request_templates

      assert_equal "global_template.md", local_templates.first.filename
    end

    test "returns repo templates if they exist" do
      global_repo = create :repository, owner: @user, name: ".github"
      local_repo = create :repository, owner: @user, name: "local"
      add_pr_template(global_repo, @user, "global_template.md")
      add_pr_template(local_repo, @user, "local_template.md")

      global_templates = global_repo.pull_request_templates
      local_templates = local_repo.pull_request_templates

      assert_equal 1, local_templates.count
      assert_equal "local_template.md", local_templates.first.filename
    end
  end

  context "when there aren't any templates defined at any level" do
    test "returns an empty list" do
      global_repo = create :repository, owner: @org, name: ".github"
      local_repo = create :repository, owner: @org, name: "local"

      global_templates = global_repo.pull_request_templates
      local_templates = local_repo.pull_request_templates

      assert_empty global_templates
      assert_empty local_templates
    end
  end

  def add_pr_template(repo, user, template_filename)
    repo.add_member user
    example_repo :simple, repo
    commit = repo.commits.create({ message: "Add PR template", author: user }) do |files|
      files.add ".github/PULL_REQUEST_TEMPLATE/#{template_filename}", <<~MARKDOWN
        Make sure your PR is cool before merging.
      MARKDOWN
    end

    repo.refs["refs/heads/master"].update(commit, user)
  end
end
