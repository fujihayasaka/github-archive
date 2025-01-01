# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTemplatesTest < GitHub::TestCase
  fixtures do
    @repo  = create(:repository, has_discussions: true)
    @owner = @repo.owner
  end

  setup do
    example_repo :simple, @repo
    commit = @repo.commits.create({ message: "Add templates", author: @repo.owner }) do |files|
      files.add ".github/DISCUSSION_TEMPLATE/announcements.yml", <<~YAML
      ---
      body:
      - type: input
        attributes:
          label: "what are you announcing?"
      YAML

      files.add ".github/DISCUSSION_TEMPLATE/general.yml", <<~YAML
      ---
      body:
      - type: input
        attributes:
          label: "what is your favorite pizza?"
      YAML

      # add an invalid template for the ideas category
      files.add ".github/DISCUSSION_TEMPLATE/ideas.yml", <<~YAML
      ---
      body: [
      YAML
    end

    @repo.refs["refs/heads/master"].update(commit, @repo.owner)
  end

  test "lists templates" do
    discussion_templates = DiscussionTemplates.new(@repo)
    assert_equal 3, discussion_templates.templates.size
    assert_equal 2, discussion_templates.valid_templates.size

    announcements_template, general_template = discussion_templates.valid_templates
    refute_nil announcements_template
    refute_nil general_template
    announcements_template = T.must(announcements_template)
    assert_equal ".github/DISCUSSION_TEMPLATE/announcements.yml", announcements_template.filename
    assert_equal @repo, announcements_template.repository
    announcement_input = announcements_template.user_inputs.first
    assert_equal "input", announcement_input.type
    assert_equal "what are you announcing?", announcement_input.label

    general_template = T.must(general_template)
    assert_equal ".github/DISCUSSION_TEMPLATE/general.yml", general_template.filename
    assert_equal @repo, general_template.repository
    general_input = general_template.user_inputs.first
    assert_equal "input", general_input.type
    assert_equal "what is your favorite pizza?", general_input.label
  end

  test "is case insensitive for the .yml" do

    commit = @repo.commits.create({ message: "Add templates", committer: @repo.owner }) do |files|
      files.add ".github/DISCUSSION_TEMPLATE/general.YMl", <<~YAML
      ---
      body:
      - type: input
        attributes:
          label: "what are you announcing?"
      YAML
    end
    @repo.refs["refs/heads/master"].update(commit, @repo.owner)

    discussion_templates = DiscussionTemplates.new(@repo)
    assert_equal 1, discussion_templates.valid_templates.size
    valid_template = discussion_templates.valid_templates.first
    refute_nil valid_template
    assert_equal ".github/DISCUSSION_TEMPLATE/general.YMl", T.must(valid_template).filename
  end

  test "does not return templates for broken repository" do
    @repo.network.update!(maintenance_status: "broken")
    discussion_templates = DiscussionTemplates.new(@repo)
    assert_empty discussion_templates.templates
  end

  context "#for_slug" do
    test "returns template for a given slug" do
      discussion_templates = DiscussionTemplates.new(@repo)
      general_template = discussion_templates.for_slug("general")
      refute_nil general_template
      general_template = T.must(general_template)
      assert_equal ".github/DISCUSSION_TEMPLATE/general.yml", general_template.filename
      assert_equal @repo, general_template.repository
      general_input = general_template.user_inputs.first
      assert_equal "input", general_input.type
      assert_equal "what is your favorite pizza?", general_input.label
    end

    test "does not return invalid templates" do
      discussion_templates = DiscussionTemplates.new(@repo)
      assert_nil discussion_templates.for_slug("ideas")
    end

    test "returns nil if template does not exist" do
      discussion_templates = DiscussionTemplates.new(@repo)
      assert_nil discussion_templates.for_slug("hatsune-miku")
    end
  end

  context "#[]" do
    test "returns template by file name" do
      discussion_templates = DiscussionTemplates.new(@repo)
      template = discussion_templates[".github/DISCUSSION_TEMPLATE/general.yml"]
      refute_nil template
      assert_equal "general", T.must(template).category_slug
    end

    test "returns invalid template by file name" do
      discussion_templates = DiscussionTemplates.new(@repo)
      template = discussion_templates[".github/DISCUSSION_TEMPLATE/ideas.yml"]
      refute_nil template
      assert_equal "ideas", T.must(template).category_slug
    end

    test "returns nil for non-existent file" do
      discussion_templates = DiscussionTemplates.new(@repo)
      assert_nil discussion_templates[".github/DISCUSSION_TEMPLATE/dahyun.yml"]
    end
  end

  context ".valid_path?" do
    test "true for path to YAML template" do
      assert DiscussionTemplates.valid_path?(".github/DISCUSSION_TEMPLATE/general.yml")
      assert DiscussionTemplates.valid_path?(".github/DISCUSSION_TEMPLATE/general.yaml")
    end

    test "false for directoy outside of `.github`" do
      refute DiscussionTemplates.valid_path?("DISCUSSION_TEMPLATE/general.yml")
    end

    test "false for path to markdown template" do
      refute DiscussionTemplates.valid_path?(".github/DISCUSSION_TEMPLATE/general.md")
    end
  end
end
