# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryWikiDependencyTest < GitHub::TestCase
  include RepositoriesTestHelper

  fixtures do
    @repo  = create(:repository)
    @fork  = fast_fork_repo(@repo, owner: @repo.owner, name: "glorious-fork")
  end

  setup do
    reset_repo_root
  end

  test "creates blank repo for new wiki" do
    refute @repo.unsullied_wiki.exist?, "repo wiki should not exist"
    @repo.initialize_wiki(@repo.owner)
    assert @repo.unsullied_wiki.exist?, "repo wiki should exist"
  end

  test "with fork_parent_wiki=false, creates a blank wiki" do
    example_repo :wiki, @repo.unsullied_wiki

    @fork.initialize_wiki(@fork.owner)
    assert @fork.unsullied_wiki.exist?
    assert_nil @fork.unsullied_wiki.pages.find("Home")
  end

  context "fork_parent_wiki=true" do

    test "forks repo parent wiki" do
      example_repo :wiki, @repo.unsullied_wiki

      @fork.initialize_wiki(@fork.owner, fork_parent_wiki: true)
      assert_match(/^home/, @fork.unsullied_wiki.pages.find("Home").data)
      assert_match /^\d:[0-9a-f]{40}$/, GitHub::DGit::Routing.wiki_checksum(@fork.network.id, @fork.id)
      GitHub::DGit::Routing.all_repo_replicas(@fork.id, true).each do |repl|
        assert repl.healthy?
      end
    end

    test "creates a blank repo for wiki when parent has disabled wikis" do
      example_repo :wiki, @repo.unsullied_wiki
      @repo.update!(has_wiki: false)

      @fork.initialize_wiki(@fork.owner, fork_parent_wiki: true)
      assert_nil @fork.unsullied_wiki.pages.find("Home")
    end

    test "creates blank repo for wiki without parent wiki" do
      refute @fork.unsullied_wiki.exist?, "fork wiki should not exist"
      @fork.initialize_wiki(@fork.owner, fork_parent_wiki: true)
      assert @fork.unsullied_wiki.exist?, "fork wiki should exist"
      refute @repo.unsullied_wiki.exist?, "repo wiki should not exist"
    end
  end
end
