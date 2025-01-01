# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionReferenceScannerTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, has_discussions: true)
  end

  test "returns a single discussion reference"  do
    discussion = create(:discussion, repository: @repo)
    text = "this is a reference https://#{GitHub.url}/#{@repo.nwo}/discussions/#{discussion.number}"
    scanner = DiscussionReferenceScanner.new(text: text, viewer: @user)
    references = scanner.references

    assert_equal discussion, references.first
  end

  test "returns multiple discussion references" do
    discussion = create(:discussion, repository: @repo)
    other_discussion = create(:discussion, repository: @repo)

    text = "this is a reference #{GitHub.url}/#{@repo.nwo}/discussions/#{discussion.number}"
    text += " and also #{GitHub.url}/#{@repo.nwo}/discussions/#{other_discussion.number}"
    scanner = DiscussionReferenceScanner.new(text: text, viewer: @user)
    references = scanner.references

    assert_equal 2, references.length
    assert_includes [discussion, other_discussion], references.first
    assert_includes [discussion, other_discussion], references.last
  end

  test "returns nothing for a non-existant discussion" do
    text = "this is not a reference {GitHub.url}/123/discussions/456"
    scanner = DiscussionReferenceScanner.new(text: text, viewer: @user)

    assert_empty scanner.references
  end

  test "returns nothing if the discussion is not readable by the viewer" do
    private_repo = create(:private_repository, has_discussions: true)
    discussion = create(:discussion, repository: private_repo)
    text = "this is not a reference #{GitHub.url}/#{@repo.nwo}/discussions/#{discussion.number}"
    scanner = DiscussionReferenceScanner.new(text: text, viewer: @user)

    assert_empty scanner.references
  end
end
