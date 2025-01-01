# typed: true
# frozen_string_literal: true
require "test_helper"
require "test_helpers/permissions_helper"

class VariantAnalysis::CodeScanningRepoListsTest < GitHub::TestCase
  include VariantAnalysis::CodeScanningRepoLists
  fixtures do
    @owner = create(:paid_user)

    # Create a repository mirroring the contents of https://github.com/github/mrva-top-repos/
    @list_holder_repo = create(:public_repository, owner: @owner, from_example: :"mrva-top-repos")
  end

  setup do
    VariantAnalysis::CodeScanningRepoLists.stubs(:mrva_top_repos_id).returns(@list_holder_repo.id)
  end

  CodeqlVariantAnalysis::ALLOWED_LANGUAGES.each do |language|
    test "gets the dynamically generated #{language} top repos" do
      # from mrva-top-repos
      repos = VariantAnalysis::CodeScanningRepoLists.get_repo_list(language, "top_10000")
      assert_equal "mock/#{language}", repos[0]
      assert_equal 1, repos.size
    end

    test "gets 3 of the second dynamically generated #{language} repo list" do
      # from mrva-top-repos, all languages share the same list
      repos = VariantAnalysis::CodeScanningRepoLists.get_repo_list(language, "other_3")
      assert_equal "mock/first", repos[0]
      assert_equal "mock/second", repos[1]
      assert_equal "mock/third", repos[2]
      assert_equal 3, repos.size
    end

    test "gets 1 of the second dynamically generated #{language} repo list" do
      # from mrva-top-repos, all languages share the same list
      repos = VariantAnalysis::CodeScanningRepoLists.get_repo_list(language, "other_1")
      assert_equal "mock/first", repos[0]
      assert_equal 1, repos.size
    end
  end

  test "gets the top 100 repos for a language that doesn't exist" do
    assert_raises_with_message VariantAnalysis::CodeScanningRepoLists::InvalidQueryList, "Invalid language: hucairz" do
      VariantAnalysis::CodeScanningRepoLists.get_repo_list("hucairz", "top_100")
    end
  end

  test "gets the top repos for a language that doesn't exist" do
    assert_raises_with_message VariantAnalysis::CodeScanningRepoLists::InvalidQueryList, "Invalid language: hucairz" do
      VariantAnalysis::CodeScanningRepoLists.get_repo_list("hucairz", "top")
    end
  end

  test "gets the top 100 repos for a list that doesn't exist" do
    repos = VariantAnalysis::CodeScanningRepoLists.get_repo_list("cpp", "hucairz_100")
    assert_nil repos
  end

  test "gets the top repos for a list that doesn't exist" do
    repos = VariantAnalysis::CodeScanningRepoLists.get_repo_list("cpp", "hucairz")
    assert_nil repos
  end

  test "tries to get a list with an invalid name" do
    assert_raises_with_message(VariantAnalysis::CodeScanningRepoLists::InvalidQueryList, "Invalid list name: bad? list! name#") do
      VariantAnalysis::CodeScanningRepoLists.get_repo_list("cpp", "bad? list! name#")
    end
  end

  test "tries to get a list with an invalid language" do
    assert_raises_with_message(VariantAnalysis::CodeScanningRepoLists::InvalidQueryList, "Invalid language: bad? language!") do
      VariantAnalysis::CodeScanningRepoLists.get_repo_list("bad? language!", "hucairz")
    end
  end

  test "tries to get a language list with an invalid contents" do
    assert_raises_with_message(VariantAnalysis::CodeScanningRepoLists::InvalidQueryList, "Invalid language: bad") do
      VariantAnalysis::CodeScanningRepoLists.get_repo_list("bad", "bad")
    end
  end
end
