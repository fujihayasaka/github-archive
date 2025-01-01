# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionBuilderTest < GitHub::TestCase
  fixtures do
    @user     = create(:verified_user)
    @owner    = create(:verified_user)
    @repo     = create(:repository, owner: @owner, has_discussions: true)
    @category = create(:discussion_category, repository: @repo)
    @label    = create(:label, repository: @repo)
  end

  setup do
    example_repo :simple, @repo
    commit = @repo.commits.create({ message: "Add templates", author: @owner }) do |files|
      files.add ".github/DISCUSSION_TEMPLATE/general.yml", <<~YAML
      ---
      labels: #{@label.name}
      body:
      - type: markdown
        attributes:
          value: "Remember to stan Dahyun!"
      - type: input
        attributes:
          label: "hello?"
      YAML
    end

    @repo.refs["refs/heads/master"].update(commit, @owner)
  end

  context "#build" do
    test "builds a basic discussion" do
      params = {
        title: "stan dahyun",
        body: "stream twice",
        category_id: @category.id,
      }

      discussion = Discussion::Builder.new(
        user: @user,
        repository: @repo,
      ).build(discussion_params: params)

      assert_predicate discussion, :valid?
      assert_equal @user, discussion.user
      assert_equal @category, discussion.category
      assert_equal params[:title], discussion.title
      assert_equal params[:body], discussion.body
      assert_empty discussion.labels
    end

    test "builds a discussion with labels if user is authorized to label" do
      params = {
        title: "stan dahyun",
        body: "stream twice",
        category_id: @category.id,
        labels: [@label.id]
      }

      @repo.add_member(@user)
      assert @repo.writable_by?(@user)

      discussion = Discussion::Builder.new(
        user: @user,
        repository: @repo,
      ).build(discussion_params: params)

      assert_predicate discussion, :valid?
      assert_equal @user, discussion.user
      assert_equal @category, discussion.category
      assert_equal params[:title], discussion.title
      assert_equal params[:body], discussion.body
      assert_equal [@label], discussion.labels
    end

    test "ignores labels if user is not authorized to label" do
      params = {
        title: "stan dahyun",
        body: "stream twice",
        category_id: @category.id,
        labels: [@label.id]
      }

      discussion = Discussion::Builder.new(
        user: @user,
        repository: @repo,
      ).build(discussion_params: params)

      assert_predicate discussion, :valid?
      assert_equal @user, discussion.user
      assert_equal @category, discussion.category
      assert_equal params[:title], discussion.title
      assert_equal params[:body], discussion.body
      assert_empty discussion.labels
    end

    test "builds a discussion with a poll" do
      poll_category = @repo.discussion_categories.find_by(supports_polls: true)
      params = {
        title: "stan dahyun",
        body: "stream twice",
        category_id: poll_category.id,
        poll_attributes: {
          question: "What is your favorite color?",
          options_attributes: [
            { option: "red" },
            { option: "blue" },
          ]
        },
      }

      discussion = Discussion::Builder.new(
        user: @user,
        repository: @repo,
      ).build(discussion_params: params)

      assert_predicate discussion, :valid?
      assert_equal @user, discussion.user
      assert_equal poll_category, discussion.category
      assert_equal params[:title], discussion.title
      assert_equal params[:body], discussion.body
      poll = discussion.poll
      assert_equal "What is your favorite color?", poll.question
      assert_equal 2, poll.options.size
      assert_equal "red", poll.options.first.option
      assert_equal "blue", poll.options.second.option
    end

    test "builds a discussion with a template" do
      category = @repo.discussion_categories.find_by(slug: "general")
      params = {
        discussion: {
          title: "stan dahyun",
          category_id: category.id,
        },
        discussion_form: {
          "#{Digest::SHA256.hexdigest("hello?")}" => "hi hi",
        },
      }

      expected_body = <<~'MARKDOWN'.chomp
        ### hello?

        hi hi
      MARKDOWN

      discussion = Discussion::Builder.new(
        user: @user,
        repository: @repo,
      ).build(discussion_params: params[:discussion], discussion_form_params: params[:discussion_form])

      assert_predicate discussion, :valid?
      assert_equal @user, discussion.user
      assert_equal category, discussion.category
      assert_equal [@label], discussion.labels
      assert_equal params[:discussion][:title], discussion.title
      assert_equal expected_body, discussion.body
      assert discussion.created_from_category_template
    end

    test "does not include labels for template if user is authorized to label" do
      category = @repo.discussion_categories.find_by(slug: "general")
      params = {
        discussion: {
          title: "stan dahyun",
          category_id: category.id,
        },
        discussion_form: {
          "#{Digest::SHA256.hexdigest("hello?")}" => "hi hi",
        },
      }

      expected_body = <<~'MARKDOWN'.chomp
        ### hello?

        hi hi
      MARKDOWN

      discussion = Discussion::Builder.new(
        user: @owner,
        repository: @repo,
      ).build(discussion_params: params[:discussion], discussion_form_params: params[:discussion_form])

      assert_predicate discussion, :valid?
      assert_equal @owner, discussion.user
      assert_equal category, discussion.category
      assert_empty discussion.labels
      assert_equal params[:discussion][:title], discussion.title
      assert_equal expected_body, discussion.body
    end

    test "works if label ids are an empty array" do
      params = {
        title: "stan dahyun",
        body: "stream twice",
        category_id: @category.id,
        labels: [""]
      }

      discussion = Discussion::Builder.new(
        user: @user,
        repository: @repo,
      ).build(discussion_params: params)

      assert_predicate discussion, :valid?
      assert_equal @user, discussion.user
      assert_equal @category, discussion.category
      assert_equal params[:title], discussion.title
      assert_equal params[:body], discussion.body
      assert_empty discussion.labels
    end
  end
end
