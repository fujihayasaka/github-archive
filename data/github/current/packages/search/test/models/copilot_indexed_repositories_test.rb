# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotIndexedRepositoriesTest < GitHub::TestCase
  include BackgroundDeletesTestHelpers

  context "get_indexing_status" do
    test "repo is indexed for semantic code search" do
      stub_response(code_search_ok: true, doc_search_ok: true)
      repo = create(:repository)
      cir = CopilotIndexedRepositories.create!(repository_id: repo.id)
      assert(cir.semantic_code_search_ok?)
      assert(cir.semantic_doc_search_ok?)
    end

    test "repo is indexed for semantic doc search" do
      stub_response(code_search_ok: true, doc_search_ok: true)
      repo = create(:repository)
      cir = CopilotIndexedRepositories.create!(repository_id: repo.id, markdown_only: true)
      assert(cir.semantic_code_search_ok?)
      assert(cir.semantic_doc_search_ok?)
    end

    test "blackbird response error" do
      Search::Blackbird::Client.stubs(:get_repository_status).returns(
        Twirp::ClientResp::new(error: Twirp::Error.not_found("repo not found"))
      )
      repo = create(:repository)
      cir = CopilotIndexedRepositories.find_or_create_by(repository_id: repo.id)
      refute(cir.semantic_code_search_ok?)
      refute(cir.semantic_doc_search_ok?)
    end
  end

  test "deleted with repository" do
    repo = create(:repository)
    cir = CopilotIndexedRepositories.create!(repository_id: repo.id)

    other_repo = create(:repository)
    other_cir = CopilotIndexedRepositories.create!(repository_id: other_repo.id)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = repo
      config.expect_destroyed = [cir]
      config.expect_not_destroyed = [other_cir]
    end
  end

  def stub_response(code_search_ok:, doc_search_ok:)
    Search::Blackbird::Client.stubs(:get_repository_status).returns(
      Twirp::ClientResp::new(data: ::Blackbird::Query::V1::GetRepositoryStatusResponse::new(corpora: nil, repositories: [
        Blackbird::Query::V1::RepositoryStatus::new(semantic_code_search_ok: code_search_ok, semantic_doc_search_ok: doc_search_ok)
      ]))
    )
  end
end
