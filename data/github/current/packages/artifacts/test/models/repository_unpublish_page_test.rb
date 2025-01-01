# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryUnpublishPageTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include GitHub::LoggerHelper

  test "destroys the repository's page and logs info on success" do
    repo = create(:repository)

    GitHub.logger.stubs(:info).returns(true)
    GitHub.logger.expects(:info).with("[repository_unpublish_page] repository page has been destroyed", {
      "code.namespace" => repo.class.to_s,
      "code.function" => "unpublish_page",
      "gh.repo.id" => repo.id
    })

    page = create(:page, repository: repo)
    repo.unpublish_page
    assert_nil repo.reload.page
  end

  test "does not destroy the repository's page but logs info on failure" do
    repo = create(:repository)
    page = create(:page, repository: repo)
    repo.page.stubs(:destroy).returns(false)

    GitHub.logger.stubs(:info).returns(true)
    GitHub.logger.expects(:info).with({
      :exception => page.errors&.full_messages.to_sentence,
      "code.namespace" => repo.class.to_s,
      "code.function" => "unpublish_page",
      "gh.repo.id" => repo.id
    })

    repo.unpublish_page
    assert repo.reload.page
  end

  test "unpublishes when repo soft-deleted" do
    repo = create(:repository)
    page = create(:page, repository: repo)
    refute_nil repo.reload.page

    perform_enqueued_hydro_jobs(only: [HydroUnpublishPageRepositoryDeletedJob], allowed_primary_query_count: 6) do
      repo.remove(repo.owner, synchronous: true)
    end

    assert_nil repo.reload.page
  end
end
