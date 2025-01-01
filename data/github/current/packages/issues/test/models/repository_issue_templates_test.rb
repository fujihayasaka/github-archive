# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class RepositoryIssueTemplatesTest < GitHub::TestCase
  fixtures do
    @user = create :user
    @org = create :organization
  end

  # Public: adds user to the repo, sets up the repo and pushes a commit
  #         that creates an issue template config which lives
  #         in .github/ISSUE_TEMPLATE/config.yml.
  #
  # Note: initially these were defined within a setup block within each context blocks
  #       but for some reason, the setup blocks were being executed in random order
  #       causing test results to be inconsistent within each context blocks.
  #
  # repo - Repository
  # user - User
  # config_name - String
  def add_template_config(repo, user, config_name)
    repo.add_member user
    example_repo :simple, repo
    commit = repo.commits.create({ message: "Add org issue template config", author: user }) do |files|
      files.add ".github/ISSUE_TEMPLATE/config.yml", <<~MARKDOWN
        blank_issue_enabled: true
        contact_links:
          - name: #{config_name}
            about: faq
            url: http://stackoverflow.com
      MARKDOWN
    end
    repo.refs["refs/heads/master"].update(commit, user)
  end

  # Public: adds user to the repo, sets up the repo and pushes a commit
  #         that creates an issue template which lives
  #         in .github/ISSUE_TEMPLATE/*.md
  #
  # Note: initially these were defined within a setup block within each context blocks
  #       but for some reason, the setup blocks were being executed in random order
  #       causing test results to be inconsistent within each context blocks.
  #
  # repo - Repository
  # user - User
  # config_name - String
  def add_issue_template(repo, user, template_name)
    repo.add_member user
    example_repo :simple, repo
    commit = repo.commits.create({ message: "Add issue template", author: user }) do |files|
      files.add ".github/ISSUE_TEMPLATE/bug.md", <<~MARKDOWN
      ---
      name: #{template_name}
      about: This is a bug
      ---
      MARKDOWN
    end

    repo.refs["refs/heads/master"].update(commit, user)
  end

  context "when org config is present" do
    test "uses org config and org templates if local repo has no settings" do
      # an org owned repo named `.github` is considered a "global repo"
      # https://github.com/github/github/blob/f65e696967f9f292586b2cc62defb3c524e8f677/app/models/repository.rb#L5151
      global_repo = create :repository, owner: @org, name: ".github"
      local_repo = create :repository, owner: @org, name: "local"

      # sets up org config on global repo
      add_template_config(global_repo, @user, "global_config")

      global_preferred_templates = global_repo.preferred_issue_templates
      global_templates = global_preferred_templates.valid_templates
      global_config = global_preferred_templates.issue_template_config.config

      local_preferred_templates = local_repo.preferred_issue_templates
      local_templates = local_preferred_templates.valid_templates
      local_config = local_preferred_templates.issue_template_config.config

      assert_equal global_config, local_config
      assert_equal "global_config", local_config["contact_links"].first["name"]
      assert_equal global_templates, local_templates
    end

    test "defaults to repo settings if repo config is present" do
      global_repo = create :repository, owner: @org, name: ".github"
      local_repo = create :repository, owner: @org, name: "local"

      # sets up org config on global repo and local config on local repo
      add_template_config(global_repo, @user, "global_config")
      add_template_config(local_repo, @user, "local_config")

      global_config = global_repo.preferred_issue_templates.issue_template_config.config
      local_config = local_repo.preferred_issue_templates.issue_template_config.config
      local_templates = local_repo.preferred_issue_templates.valid_templates

      refute_equal global_config, local_config
      assert_empty local_templates
      assert_equal "local_config", local_config["contact_links"].first["name"]
    end

    test "defaults to repo settings if repo template is present" do
      global_repo = create :repository, owner: @org, name: ".github"
      local_repo = create :repository, owner: @org, name: "local"

      # sets up org config on global repo and local template on local repo
      add_template_config(global_repo, @user, "global_config")
      add_issue_template(local_repo, @user, "local_template")

      global_preferred_templates = global_repo.preferred_issue_templates
      global_templates = global_preferred_templates.valid_templates
      global_config = global_preferred_templates.issue_template_config.config

      local_preferred_templates = local_repo.preferred_issue_templates
      local_templates = local_preferred_templates.valid_templates
      local_config = local_preferred_templates.issue_template_config.config

      refute_equal global_templates, local_templates
      assert_equal "local_template", local_templates.first.name
      refute_equal global_config, local_config
      refute_empty global_config
      assert_empty local_config
    end
  end

  context "when org template is present" do
    test "uses org config and org templates if local repo has no settings" do
      global_repo = create :repository, owner: @org, name: ".github"
      local_repo = create :repository, owner: @org, name: "local"

      # sets up org template on global repo
      add_issue_template(global_repo, @user, "global_template")

      global_preferred_templates = global_repo.preferred_issue_templates
      global_templates = global_preferred_templates.valid_templates
      global_config = global_preferred_templates.issue_template_config.config

      local_preferred_templates = local_repo.preferred_issue_templates
      local_templates = local_preferred_templates.valid_templates
      local_config = local_preferred_templates.issue_template_config.config

      assert_equal global_config, local_config
      assert_equal global_templates.first.name, local_templates.first.name
    end

    test "defaults to repo settings if repo config is present" do
      global_repo = create :repository, owner: @org, name: ".github"
      local_repo = create :repository, owner: @org, name: "local"

      # sets up org template on global repo and local config on local repo
      add_issue_template(global_repo, @user, "global_template")
      add_template_config(local_repo, @user, "local_config")

      global_preferred_templates = global_repo.preferred_issue_templates
      global_templates = global_preferred_templates.valid_templates
      global_config = global_preferred_templates.issue_template_config.config

      local_preferred_templates = local_repo.preferred_issue_templates
      local_templates = local_preferred_templates.valid_templates
      local_config = local_preferred_templates.issue_template_config.config

      refute_equal global_config, local_config
      assert_equal "local_config", local_config["contact_links"].first["name"]
      refute_equal global_templates, local_templates
      assert_empty local_templates
    end

    test "defaults to repo settings if repo templates if present" do
      global_repo = create :repository, owner: @org, name: ".github"
      local_repo = create :repository, owner: @org, name: "local"

      # sets up org template on global repo and local template on local repo
      add_issue_template(global_repo, @user, "global_template")
      add_issue_template(local_repo, @user, "local_template")

      global_preferred_templates = global_repo.preferred_issue_templates
      global_templates = global_preferred_templates.valid_templates
      global_config = global_preferred_templates.issue_template_config.config

      local_preferred_templates = local_repo.preferred_issue_templates
      local_templates = local_preferred_templates.valid_templates
      local_config = local_preferred_templates.issue_template_config.config

      refute_equal global_templates, local_templates
      assert_equal "local_template", local_templates.first.name
    end
  end

  context "when user template is present" do
    # Global templates in a .github repo are now available for user repos, too.
    # Minimal test coverage to validate this, otherwise same behavior as for org level templates.
    test "uses user config and user templates if local repo has no settings" do
      global_repo = create :repository, owner: @user, name: ".github"
      local_repo = create :repository, owner: @user, name: "local"

      # sets up user template on global repo
      add_issue_template(global_repo, @user, "global_template")

      global_preferred_templates = global_repo.preferred_issue_templates
      global_templates = global_preferred_templates.valid_templates
      global_config = global_preferred_templates.issue_template_config.config

      local_preferred_templates = local_repo.preferred_issue_templates
      local_templates = local_preferred_templates.valid_templates
      local_config = local_preferred_templates.issue_template_config.config

      assert_equal global_config, local_config
      assert_equal global_templates.first.name, local_templates.first.name
    end
  end

  context "when neither org config nor org template is present" do
    test "uses repo config if present" do
      global_repo = create :repository, owner: @org, name: ".github"
      local_repo = create :repository, owner: @org, name: "local"

      # sets up local config on local repo
      add_template_config(local_repo, @user, "local_config")

      global_preferred_templates = global_repo.preferred_issue_templates
      global_templates = global_preferred_templates.valid_templates
      global_config = global_preferred_templates.issue_template_config.config

      local_preferred_templates = local_repo.preferred_issue_templates
      local_templates = local_preferred_templates.valid_templates
      local_config = local_preferred_templates.issue_template_config.config

      refute_equal global_config, local_config
      assert_equal "local_config", local_config["contact_links"].first["name"]
      assert_empty global_templates
      assert_empty local_templates
    end

    test "uses repo templates if present" do
      global_repo = create :repository, owner: @org, name: ".github"
      local_repo = create :repository, owner: @org, name: "local"

      # sets up local template on local repo
      add_issue_template(local_repo, @user, "local_template")

      global_preferred_templates = global_repo.preferred_issue_templates
      global_templates = global_preferred_templates.valid_templates
      global_config = global_preferred_templates.issue_template_config.config

      local_preferred_templates = local_repo.preferred_issue_templates
      local_templates = local_preferred_templates.valid_templates
      local_config = local_preferred_templates.issue_template_config.config

      refute_equal global_templates, local_templates
      assert_equal "local_template", local_templates.first.name
    end
  end

  context "when neither org nor repo has a config or template" do
    test "does not use any settings" do
      global_repo = create :repository, owner: @org, name: ".github"
      local_repo = create :repository, owner: @org, name: "local"

      global_preferred_templates = global_repo.preferred_issue_templates
      global_templates = global_preferred_templates.valid_templates
      global_config = global_preferred_templates.issue_template_config.config

      local_preferred_templates = local_repo.preferred_issue_templates
      local_templates = local_preferred_templates.valid_templates
      local_config = local_preferred_templates.issue_template_config.config

      assert_empty global_config
      assert_empty local_config
      assert_empty global_templates
      assert_empty local_templates
    end
  end
end
