# typed: true
# frozen_string_literal: true

require "test_helper"

class PurgeRepositoryWikiOrchestrationTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers
  include HydroMessageJobTestHelpers
  include CustomPropertiesTestHelper

  fixtures do
    @repo_with_wiki = create(:repository, has_wiki: true)
  end

  setup do
    # has_wiki enables the wiki feature on the repo but does not create the wiki in spokes
    @repo_with_wiki.initialize_wiki(@repo_with_wiki.user)
  end

  test "skip if wiki is already purged" do
    # Delete wiki
    delete_wiki(@repo_with_wiki)

    orchestration = RepositoryOrchestration.purge_wiki(@repo_with_wiki.reload)
    orchestration.execute

    refute orchestration.valid?

    assert_equal "Cannot purge wiki that has already been purged", orchestration.errors&.where(:repository)&.map { |e| e.message }&.join(", ")
  end

  test "skip if wiki is not empty" do
    # Create a wiki page
    @repo_with_wiki.unsullied_wiki.pages.create("wiki-#{SecureRandom.uuid}", :markdown, "example body", "example commit message", @repo_with_wiki.user)

    orchestration = RepositoryOrchestration.purge_wiki(@repo_with_wiki.reload, skip_if_not_empty: true)
    refute orchestration.valid?

    assert_equal "Cannot purge wiki that is not empty for imports", orchestration.errors&.where(:repository)&.map { |e| e.message }&.join(", ")
  end

  test "should purge wiki git data from disk" do
    Repository.any_instance.expects(:remove_wiki_from_disk).once

    orchestration = purge_wiki(@repo_with_wiki)

    assert orchestration.succeeded?
  end

  test "should purge wiki git data from spokes" do
    GitHub::DGit::Maintenance.expects(:delete_wiki_replicas_and_checksums).once

    orchestration = purge_wiki(@repo_with_wiki)

    assert orchestration.succeeded?
  end

  test "should destroy repository wiki record" do
    assert RepositoryWiki.find_by(repository: @repo_with_wiki)

    orchestration = purge_wiki(@repo_with_wiki)

    assert orchestration.succeeded?

    assert_nil RepositoryWiki.find_by(repository: @repo_with_wiki)
  end

  test "should fail if wiki cannot be removed from disk" do
    Repository.any_instance.stubs(:remove_wiki_from_disk).raises(GitHub::Spokes::ClientError)

    orchestration = purge_wiki(@repo_with_wiki)

    assert_equal :failed, orchestration.state.to_sym
    max_attempts = Orchestration::MAX_ATTEMPTS
    assert_equal max_attempts + 1, orchestration.attempts
  end

  def purge_wiki(repo, perform_jobs: [])
    orchestration = RepositoryOrchestration.purge_wiki(repo)
    perform_orchestration(orchestration, perform_jobs:)
  end

  def perform_orchestration(orchestration, perform_jobs: [])
    jobs = ([RepositoryOrchestrationJob] + perform_jobs).uniq
    perform_enqueued_jobs(only: jobs) do
      orchestration.execute
    end
    orchestration.reload
  end

  def delete_wiki(repository)
    repository.remove_wiki_from_disk
    GitHub::DGit::Maintenance.delete_wiki_replicas_and_checksums(repository.network.id, repository.id)
    T.must(RepositoryWiki.find_by(repository: repository)).destroy
  end
end
