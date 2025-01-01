# typed: true
# frozen_string_literal: true

class Issue::Loader::Repositories < Issue::Loader::Base
  def initialize(context, repository_ids: [])
    @context = context
    @repository_ids = repository_ids
  end

  def self.load_for(context, repository_ids: [])
    super new(context, repository_ids: repository_ids)
  end

  def load
    Repository.strict_loading.
      where(id: @repository_ids).
      index_by(&:id).tap do |repositories_by_id|
        @context.preload_attr(:repositories_by_id, repositories_by_id)
        load_readable(repositories_by_id.values)
      end
  end

  private

  def load_readable(repos)
    Promise.all(
      repos.map do |repo|
        next unless repo
        repo.async_readable_by?(@context.viewer).then do |readable|
          next unless readable
          [repo.id, repo]
        end
      end
    ).then do |readable_repos|
      @context.preload_attr(:readable_repositories_by_id, readable_repos.compact.to_h)
    end.sync
  end
end
