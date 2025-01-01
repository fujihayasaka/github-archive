# typed: true
# frozen_string_literal: true

require "test_helper"

class PrefilledDiscussionsFieldsTest < GitHub::TestCase
  fixtures do
    @user = create(:verified_user)
    @repo = create(:repository, has_discussions: true, owner: @user)
    @label = create(:label, repository: @repo, name: "dahyun")
  end

  setup do
    example_repo :simple, @repo
    commit = @repo.commits.create({ message: "Add template", author: @user }) do |files|
      files.add ".github/DISCUSSION_TEMPLATE/general.yml", <<~YAML
      ---
      title: "Bug: "
      labels: ["dahyun"]
      body:
        - type: input
          attributes:
            label: What is your name?
      YAML
    end

    @repo.refs["refs/heads/master"].update(commit, @user)
  end

  context "#body" do
    test "returns body param value" do
      params = {
        body: "happier than ever",
      }

      result = PrefilledDiscussionsFields.new(
        params: params,
        repository: @repo,
        user: @user,
      )

      assert_equal params[:body], result.body
    end

    test "returns permalink param value" do
      params = {
        permalink: "https://github.com/github/merica-fork-yeah-tour",
      }

      result = PrefilledDiscussionsFields.new(
        params: params,
        repository: @repo,
        user: @user,
      )

      assert_equal params[:permalink], result.body
    end

    test "combines body and permalink param values" do
      params = {
        body: "i didn't change my number",
        permalink: "https://github.com/github/merica-fork-yeah-tour",
      }

      result = PrefilledDiscussionsFields.new(
        params: params,
        repository: @repo,
        user: @user,
      )

      expected = "i didn't change my number\n\nhttps://github.com/github/merica-fork-yeah-tour"
      assert_equal expected, result.body
    end

    test "returns nil if body or permalink are missing" do
      result = PrefilledDiscussionsFields.new(
        params: {},
        repository: @repo,
        user: @user,
      )

      assert_nil result.body
    end
  end

  context "#title" do
    test "returns welcome text if welcome text is true" do
      params = {
        welcome_text: true,
      }

      result = PrefilledDiscussionsFields.new(
        params: params,
        repository: @repo,
        user: @user,
      )

      assert_equal "Welcome to #{@repo.name} Discussions!", result.title
    end

    test "returns title param value" do
      params = {
        title: "happier than ever",
      }

      result = PrefilledDiscussionsFields.new(
        params: params,
        repository: @repo,
        user: @user,
      )

      assert_equal params[:title], result.title
    end

    test "returns title from template" do
      result = PrefilledDiscussionsFields.new(
        params: { category: "general" },
        repository: @repo,
        user: @user,
      )

      assert_equal "Bug: ", result.title
    end

    test "title param overrides value from template" do
      params = {
        title: "stan dahyun",
        category: "general",
      }
      result = PrefilledDiscussionsFields.new(
        params: params,
        repository: @repo,
        user: @user,
      )

      assert_equal "stan dahyun", result.title
    end

    test "returns nil if title is missing" do
      result = PrefilledDiscussionsFields.new(
        params: {},
        repository: @repo,
        user: @user,
      )

      assert_nil result.title
    end
  end

  context "labels" do
    test "prefills labels" do
      label = create(:label, repository: @repo)
      params = {
        labels: label.name,
      }

      result = PrefilledDiscussionsFields.new(
        params: params,
        repository: @repo,
        user: @user,
        can_label: true,
      )
      assert_equal [label], result.labels
    end

    test "prefills labels from template" do
      result = PrefilledDiscussionsFields.new(
        params: { category: "general" },
        repository: @repo,
        user: @user,
        can_label: true,
      )
      assert_equal [@label], result.labels
    end

    test "prefills labels from template and params for authorized user" do
      other_label = create(:label, repository: @repo)
      params = {
        category: "general",
        labels: other_label.name,
      }

      result = PrefilledDiscussionsFields.new(
        params: params,
        repository: @repo,
        user: @user,
        can_label: true,
      )
      assert_equal [@label, other_label], result.labels
    end

    test "prefills labels from template even if user is not authorized to label" do
      result = PrefilledDiscussionsFields.new(
        params: { category: "general" },
        repository: @repo,
        user: @user,
        can_label: false,
      )
      assert_equal [@label], result.labels
    end

    test "only prefills labels from template if user is not authorized to label" do
      other_label = create(:label, repository: @repo)
      params = {
        category: "general",
        labels: other_label.name,
      }

      result = PrefilledDiscussionsFields.new(
        params: params,
        repository: @repo,
        user: @user,
        can_label: false,
      )
      assert_equal [@label], result.labels
    end

    test "prefills up to maximum labels" do
      PrefilledDiscussionsFields.stub_const(:MAX_LABELS_FROM_PARAMS, 1) do
        label, other_label = create_list(:label, 2, repository: @repo)
        params = {
          labels: [label, other_label].join(",")
        }

        result = PrefilledDiscussionsFields.new(
          params: params,
          repository: @repo,
          user: @user,
          can_label: true,
        )
        assert_equal [label], result.labels
      end
    end

    test "doesn't prefill labels for another repository" do
      this_label = create(:label, repository: @repo)
      that_label = create(:label)
      params = {
        labels: [this_label, that_label].join(",")
      }

      result = PrefilledDiscussionsFields.new(
        params: params,
        repository: @repo,
        user: @user,
        can_label: true,
      )
      assert_equal [this_label], result.labels
    end

    test "does not prefill labels if user cannot label" do
      label = create(:label, repository: @repo)
      params = {
        labels: label.name,
      }

      result = PrefilledDiscussionsFields.new(
        params: params,
        repository: @repo,
        user: @user,
        can_label: false,
      )
      assert_empty result.labels
    end
  end
end
