# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryReindexAllTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, name: "cool", owner: create(:user))
  end

  test "enqueues necessary reindexing jobs" do
    Search.expects(:add_to_search_index).with("repository", @repo.id)
    Search.expects(:add_to_search_index).with("commit", @repo.id, "purge" => true)
    Search.expects(:add_to_search_index).with("wiki", @repo.id, "purge" => true)
    Search.expects(:add_to_search_index).with("bulk_issues", @repo.id, "purge" => true)
    Search.expects(:add_to_search_index).with("bulk_projects", @repo.id, "purge" => true)
    Search.expects(:add_to_search_index).with("bulk_pull_requests", @repo.id, "purge" => true)
    Search.expects(:add_to_search_index).with("bulk_discussions", @repo.id, "purge" => true)
    Search.expects(:add_to_search_index).with("bulk_releases", @repo.id, "purge" => true)

    if GitHub.use_elastomer_code_search?
      Search.expects(:add_to_search_index).with("code", @repo.id, "purge" => true)
    end

    @repo.reindex_all
  end

  unless GitHub.use_elastomer_code_search?
    test "does not enqueue legacy code index outside of GHES" do
      Search.stubs(:add_to_search_index)
      Search.expects(:add_to_search_index).with do |type, repo_id, _options|
        refute type == "code" && repo_id == @repo.id
      end

      @repo.reindex_all
    end
  end
end
