# typed: true
# frozen_string_literal: true

require "test_helper"

class PagesWorkflowTemplatesTest < GitHub::TestCase
  fixtures do
    @owner = create :user
    @repo = create :repository, owner: @owner, from_example: :repository_test_simple
    @branch = GitHub.enterprise? ? "ghes" : "main"
    @repo.heads.create(@branch, @repo.default_branch_ref.commit.oid, @repo.owner)
    @repo.update_default_branch(@branch)
    @repo.heads.create("protected", @repo.default_branch_ref.commit.oid, @repo.owner)
    @repo.protect_branch("foo_protected_bar", creator: @repo.owner, entry_point: :test_case)
    @repo.protect_branch("foo_protected_bar?", creator: @repo.owner, entry_point: :test_case)

    example_repo_snapshot

    @templates = [
      {
        "id" => "blank",
        "data" => Base64.encode64(<<~YAML
on:
  push:
    branches:
      - $default-branch
  jobs:
    build:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@main
      YAML
        ),
        "name" => "Simple workflow",
        "categories" => ["Test"]
      }
    ]
  end

  setup do
    example_repo_restore
    PagesWorkflowTemplate.stubs(:templates).returns(@templates)
  end

  test "get_yaml_by_id renders default branch has a json string" do
    yaml = PagesWorkflowTemplate.get_yaml_by_id("blank", @repo, @owner)
    refute yaml.include? "$default-branch"
    assert yaml.include? "- \"#{@branch}\""
  end

  test "get_yaml_by_id renders default branch has a json string and supports odd cases" do
    # Change default branch
    branch_name = "\"❤️\"-hello"
    @repo.heads.create(branch_name, @repo.default_branch_ref.commit.oid, @repo.owner)
    @repo.update_default_branch(branch_name)

    yaml = PagesWorkflowTemplate.get_yaml_by_id("blank", @repo, @owner)
    refute yaml.include? "$default-branch"
    assert yaml.include? "- \"\\\"❤️\\\"-hello\""
  end
end
