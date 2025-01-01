# typed: false
# frozen_string_literal: true

# Created for a Repository with git-backed wiki.  Mostly for stats and query
# abilities.
class RepositoryWiki < ApplicationRecord::Domain::Repositories
  include RepositoryWiki::Maintenance

  validates_uniqueness_of :repository_id

  belongs_to :repository
  destroy_in_background_with :repository

  before_create :set_default_values
  before_validation :set_initial_maintenance_status, on: :create

  after_commit :synchronize_search_index

  def entity = repository
  def async_entity = async_repository

  def unsullied_wiki
    repository.unsullied_wiki
  end

  def host
    repository.host
  end

  def name
    repository.nwo
  end

  def shard_path
    unsullied_wiki.shard_path
  end

  def rpc
    unsullied_wiki.rpc
  end

  def spokes_api
    unsullied_wiki.spokes_api
  end

  def dgit_spec
    repository.dgit_spec(wiki: true)
  end

  def increment_cache_version!
    RepositoryWiki.increment_counter(:cache_version_number, id)
    reload
  end

  # Internal: Before create callback used to set default attributes values for a
  # record that's about to be created.
  def set_default_values
    self.pushed_at ||= Time.now
    self.pushed_count ||= 0
    self.pushed_count_since_maintenance ||= 0
  end

  def set_initial_maintenance_status
    self.maintenance_status  ||= "complete"
    self.last_maintenance_at ||= Time.now
    self.last_maintenance_attempted_at ||= Time.now
  end

  # Internal: Synchronize this wiki with its representation in the search
  # index. If the wiki is newly created or updated, then it will be updated in
  # the search index. If the wiki has been destroyed, then it will be removed
  # from the search index. This method handles both cases.
  def synchronize_search_index
    if self.destroyed?
      RemoveFromSearchIndexJob.perform_later("wiki", repository_id)
    else
      Search.add_to_search_index("wiki", repository_id)
    end
    self
  end
end
