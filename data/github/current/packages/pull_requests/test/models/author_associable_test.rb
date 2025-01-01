# typed: true
# frozen_string_literal: true

require "test_helper"

class AuthorAssociableFixture
  include AuthorAssociable
end

class AuthorAssociableTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @comment = AuthorAssociableFixture.new
    @comment.freeze
  end

  test "exposes the author association" do
    assert @comment.author_association
    assert_equal CommentAuthorAssociation, @comment.author_association.class
  end

  test "initializes the author association with the comment" do
    assert_equal @comment, @comment.author_association.send(:comment)
  end

  test "initializes the author association with the viewer" do
    assert_equal @user, @comment.author_association(@user).send(:viewer)
  end
end
