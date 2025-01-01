# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class Api::Serializer::DiscussionsDependencyTest < Api::SerializerTestCase
  fixtures do
    @owner = create(:verified_user)
    @user = create(:verified_user)
    @repo = create(:repository, owner: @owner, has_discussions: true)
    @label = create(:label, repository: @repo)
    @discussion = create(:discussion, user: @user, repository: @repo, labels: [@label])
    @comment = create(:discussion_comment, user: @user, discussion: @discussion)
  end

  context "#discussion_hash" do
    test "renders v3 format when v3 media type is requested" do
      output = serialize_hash_method(:discussion_hash, @discussion)
      assert output.key?("repository_url")
      assert output.key?("category")
      assert output.key?("answer_html_url")
      assert output.key?("reactions")
      assert output.key?("labels")
      assert output["labels"].is_a?(Array)
    end

    test "renders selected answer when there is one" do
      answerable_category = @repo.discussion_categories.find_by(supports_mark_as_answer: true)
      @discussion.category = answerable_category
      answer = create(:discussion_comment, discussion: @discussion)

      answer.mark_as_answer(actor: @user)

      output = serialize_hash_method(:discussion_hash, @discussion)
      refute_nil output["answer_chosen_at"]
      assert_equal serialize_hash_method(:user_hash, @user), output["answer_chosen_by"]
      assert_equal answer.url, output["answer_html_url"]
    end

    test "renders discussion category based on the discussion category schema" do
      output = serialize_hash_method(:discussion_hash, @discussion)
      assert output.key?("repository_url")
      assert output.key?("category")
      assert output.key?("answer_html_url")
      assert output.key?("reactions")
    end

    test "renders locked state for discussion with locked_at set" do
      assert @discussion.lock(actor: @owner)
      output = serialize_hash_method(:discussion_hash, @discussion)
      assert_equal "open", @discussion.state
      assert_equal "locked", output["state"]
      assert output["locked"]
    end

    Discussion::StateReasonable::CloseReason.values.each do |value|
      test "renders for discussion closed as #{value.serialize}" do
        assert @discussion.close(actor: @user, reason: value)
        output = serialize_hash_method(:discussion_hash, @discussion)
        assert_equal "closed", output["state"]
        assert_equal value.serialize, output["state_reason"]
      end
    end

    test "renders for reopened discussion" do
      assert @discussion.close(actor: @user)
      assert @discussion.reopen(actor: @user)
      output = serialize_hash_method(:discussion_hash, @discussion)
      assert_equal "open", output["state"]
      assert_equal Discussion::StateReasonable::StateReason::Reopened.serialize, output["state_reason"]
    end
  end

  context "#discussion_category_hash" do
    test "renders v3 format when v3 media type is requested" do
      output = serialize_hash_method(:discussion_category_hash, @discussion.category)
      assert output.key?("id")
      assert output.key?("node_id")
      assert output.key?("repository_id")
      assert output.key?("emoji")
    end
  end

  context "#discussion_comment_hash" do
    test "renders v3 format when v3 media type is requested" do
      reaction = create(:reaction, subject: @comment, content: "tada")

      output = serialize_hash_method(:discussion_comment_hash, @comment)
      assert output.key?("repository_url")
      assert output.key?("reactions")
      assert_match %r{.*/discussions/comments/#{@comment.id}/reactions$}, output["reactions"]["url"]
    end
  end
end
