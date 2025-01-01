# typed: true
# frozen_string_literal: true

class PurgeRepositoryWikiOrchestration < RepositoryOrchestration
  validate :purgeable?, on: :create

  def purgeable?
    wiki = repository.unsullied_wiki

    unless wiki.exist?
      errors.add(:repository, "Cannot purge wiki that has already been purged")
    end

    if data[:skip_if_not_empty] && wiki.exist? && !wiki.rpc.any_refs[:empty]
      errors.add(:repository, "Cannot purge wiki that is not empty for imports")
    end
  end

  job_start

  step :purge_from_disk do
    T.bind(self, PurgeRepositoryWikiOrchestration)

    T.must(repository).remove_wiki_from_disk
  end

  step :purge_from_spokes do
    T.bind(self, PurgeRepositoryWikiOrchestration)

    network = T.must(repository.network)

    GitHub::DGit::Maintenance.delete_wiki_replicas_and_checksums(network.id, repository.id)
  end

  step :destroy_repository_wiki_record do
    T.bind(self, PurgeRepositoryWikiOrchestration)

    T.must(RepositoryWiki.find_by(repository: repository)).destroy
  end

  sig { returns(Repository) }
  def repository
    T.must(super)
  end
end
