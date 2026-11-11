# typed: true
# frozen_string_literal: true

class RepositoryAdvisory::Adapter::Context
  include PreloadableAttributes

  attr_reader :cap_filter,
    :viewer,
    :repository,
    :users_by_id,
    :repositories_by_id,
    :issue,
    :advisory

  attr_preloadable :users_by_id,
    :repositories_by_id

  def initialize(advisory, repository, viewer, cap_filter = nil)
    @advisory = advisory
    @repository = repository
    @viewer = viewer
    @cap_filter = cap_filter

    # we just have a single repository
    @repositories_by_id = {}
    @repositories_by_id[repository.id] = repository
    # init the adapter
    repository_adapter
  end

  def users
    return @users if defined?(@users)
    @users = users_by_id.values
  end

  def repository_adapter
    return @repository_adapter if defined?(@repository_adapter)
    @repository_adapter = Issue::Adapter::RepositoryAdapter.new(self, repository: self.repository)
  end
end
