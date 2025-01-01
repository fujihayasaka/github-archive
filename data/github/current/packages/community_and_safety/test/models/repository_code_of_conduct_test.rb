# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCodeOfConductTest < GitHub::TestCase
  fixtures do
    @repo_with_code_of_conduct = create :repository, from_example: :code_of_conduct_markdown

    @repo_without_code_of_conduct = create :repository, from_example: :code_of_conduct_none
  end

  test "find by repo ID" do
    coc = RepositoryCodeOfConduct.find(@repo_with_code_of_conduct.id)
    assert coc
    assert_equal "contributor-covenant/version/1/4", coc.key
  end

  test "stores the repo" do
    with_code_of_conduct = RepositoryCodeOfConduct.new(@repo_with_code_of_conduct)
    assert_equal @repo_with_code_of_conduct, with_code_of_conduct.repository
  end

  test "returns the key" do
    with_code_of_conduct = RepositoryCodeOfConduct.new(@repo_with_code_of_conduct)
    assert_equal "contributor-covenant/version/1/4", with_code_of_conduct.key
  end

  test "returns none with no code of conduct" do
    without_code_of_conduct = RepositoryCodeOfConduct.new(@repo_without_code_of_conduct)
    assert_equal "none", without_code_of_conduct.key
  end

  test "returns the content" do
    with_code_of_conduct = RepositoryCodeOfConduct.new(@repo_with_code_of_conduct)
    assert_match /Contributor Covenant/, with_code_of_conduct.content
  end

  test "returns the path" do
    with_code_of_conduct = RepositoryCodeOfConduct.new(@repo_with_code_of_conduct)
    expected = "/#{@repo_with_code_of_conduct.nwo}/blob/master/CODE_OF_CONDUCT.md"
    assert_equal with_code_of_conduct.path, expected
  end

  test "returns the URL" do
    with_code_of_conduct = RepositoryCodeOfConduct.new(@repo_with_code_of_conduct)
    expected = "#{GitHub.url}/#{@repo_with_code_of_conduct.nwo}/blob/master/CODE_OF_CONDUCT.md"
    assert_equal with_code_of_conduct.url.to_s, expected
  end
end
