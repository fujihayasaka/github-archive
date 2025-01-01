# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTemplateTest < GitHub::TestCase
  fixtures do
    @repo = create :repository
    @owner = @repo.owner

    @rainbow_label = create(:label, name: "rainbow-skate", repository: @repo)
    @skaters_label = create(:label, name: "skaters", repository: @repo)
    @labels_string = "#{@rainbow_label.name},#{@skaters_label.name},this-label-does-not-exist"
  end

  setup do
    example_repo :simple, @repo
    commit = @repo.commits.create({ message: "Add templates", author: @repo.owner }) do |files|
      files.add ".github/DISCUSSION_TEMPLATE/announcements.yml", <<~YAML
      ---
      title: Dahyun
      labels: [#{@rainbow_label.name}, #{@skaters_label.name}]
      body:
      - type: input
        attributes:
          label: "who is your favorite skater?"
      YAML

      files.add ".github/DISCUSSION_TEMPLATE/bad.yml", <<~YAML
      ---
      title: Bad template
      body: []
      YAML

      files.add ".github/DISCUSSION_TEMPLATE/general.yml", <<~YAML
      ---
      title: Dahyun
      labels: "#{@labels_string}"
      body:
      - type: markdown
        attributes:
          value: "Example description"
      - type: input
        attributes:
          label: "what is your favorite pizza?"
      YAML

      files.add ".github/DISCUSSION_TEMPLATE/no-labels.yml", <<~YAML
      ---
      title: No labels
      body:
      - type: input
        attributes:
          label: "Why do you stan Dahyun?"
      YAML
    end

    @repo.refs["refs/heads/master"].update(commit, @repo.owner)
    @announcements_tree_entry, @bad_tree_entry, @general_tree_entry, @no_labels_tree_entry = @repo.directory(
      @repo.default_oid,
      DiscussionTemplates::TEMPLATES_DIRECTORY,
    ).tree_entries
  end

  context ".from_tree_entry" do
    test "creates new discussion template" do
      template = DiscussionTemplate.from_tree_entry(@general_tree_entry)

      assert_predicate template, :valid?
      assert_equal "Dahyun", template.title
      assert_equal @labels_string, template.labels_string
      assert_equal 2, template.inputs.size
      markdown = template.inputs.first
      assert_equal "markdown", markdown.type
      assert_equal "Example description", markdown.value
      input = template.inputs.second
      assert_equal "input", input.type
      assert_equal "what is your favorite pizza?", input.label
    end

    test "includes user_inputs" do
      template = DiscussionTemplate.from_tree_entry(@general_tree_entry)

      assert_predicate template, :valid?
      assert_equal 2, template.inputs.count
      assert_equal 1, template.user_inputs.count
      input = template.user_inputs.first
      assert_equal "input", input.type
      assert_equal "what is your favorite pizza?", input.label
    end

    test "converts labels from arrays into comma-delimited strings" do
      template = DiscussionTemplate.from_tree_entry(@announcements_tree_entry)

      assert_predicate template, :valid?
      assert_equal "#{@rainbow_label.name}, #{@skaters_label.name}", template.labels_string
    end

    test "returns errors for template config" do
      template = DiscussionTemplate.from_tree_entry(@bad_tree_entry)

      refute_predicate template, :valid?
      assert_equal ["Body cannot be empty"], template.errors.full_messages
    end
  end

  context "#labels" do
    test "returns Labels associated to the current repo from the labels_string provided" do
      template = DiscussionTemplate.from_tree_entry(@general_tree_entry)
      assert_equal 2, template.labels.size
      assert_includes template.labels, @rainbow_label
      assert_includes template.labels, @skaters_label
    end

    test "returns no labels if not specified" do
      template = DiscussionTemplate.from_tree_entry(@no_labels_tree_entry)
      assert_empty template.labels
    end
  end

  context "#discussion" do
    test "returns a new discussion" do
      template = DiscussionTemplate.from_tree_entry(@no_labels_tree_entry)
      discussion = template.discussion
      assert_instance_of Discussion, discussion
      assert_predicate discussion, :new_record?
    end

    test "returns a new discussion with associated labels if labels are provided" do
      template = DiscussionTemplate.from_tree_entry(@general_tree_entry)
      discussion = template.discussion
      assert_equal 2, discussion.labels.size
      assert_includes discussion.labels, @rainbow_label
      assert_includes discussion.labels, @skaters_label
    end
  end

  context "#url" do
    test "returns full qualified url for associated new discussion form for repo and category" do
      template = DiscussionTemplate.from_tree_entry(@general_tree_entry)
      assert_equal template.url, "#{GitHub.url}/#{@repo.nwo}/discussions/new?category=general"
    end
  end
end
