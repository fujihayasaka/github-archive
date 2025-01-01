# typed: strict
# frozen_string_literal: true

module ActionsCacheManagementHelper
  class << self
    sig do
      params(
        repo: Repository,
        key: T.nilable(String),
        ref: T.nilable(String),
        per_page: Integer,
        page: Integer,
        sort: String,
        direction: String,
      ).returns(TwirpResponse)
    end
    def get_repo_caches(repo:, key: nil, ref: nil, per_page: 30, page: 1, sort: "last_accessed_at", direction: "desc")
      if Actions::Cache.use_v2?(repo)
        res = ActionsResults::Twirp.cache_client.list_caches(repository_id: repo.id, key:, scope: ref, per_page:, page:, sort:, direction:)
        value = CacheList.from_results(res.value)
      else
        res = Launch::Twirp.cache_client.list_caches(owner: repo, key:, ref:, per_page:, page:, sort:, direction:)
        value = CacheList.from_launch(res.value)
      end

      TwirpResponse.new(
        status: res.status,
        value:,
        options: res.options,
        call_succeeded: res.call_succeeded
      )
    end

    sig do
      params(
        repo: Repository,
        key: String,
        current_user: User,
        ref: T.nilable(String)
      ).returns(TwirpResponse)
    end
    def deletes_repo_cache_by_key(repo:, key:, current_user:, ref: nil)
      if Actions::Cache.use_v2?(repo)
        resp = ActionsResults::Twirp.cache_client.delete_caches_by_key(repository_id: repo.id, key:, scope: ref)
        value = CacheList.from_results_delete(resp.value)
      else
        resp = Launch::Twirp.cache_client.delete_caches_by_key(repo:, key:, ref:)
        value = CacheList.from_launch_delete(resp.value)
      end

      return resp unless resp.call_succeeded?
      resp.value.caches.each do |cache|
        emit_cache_delete(repo: repo, id: cache.id, key: cache.key, version: cache.version, scope: cache.scope, current_user: current_user)
      end

      TwirpResponse.new(
        status: resp.status,
        value: value,
        options: resp.options,
        call_succeeded: resp.call_succeeded
      )
    end

    sig do
      params(
        repo: Repository,
        id: Integer,
        current_user: User
      ).returns(TwirpResponse)
    end
    def delete_repo_cache_by_id(repo:, id:, current_user:)
      if Actions::Cache.use_v2?(repo)
        resp = ActionsResults::Twirp.cache_client.delete_cache_by_id(repository_id: repo.id, cache_id: id)
      else
        resp = ::Launch::Twirp.cache_client.delete_cache_by_id(repo:, cache_id: id)
      end
      return resp unless resp.call_succeeded?
      emit_cache_delete(repo: repo, id: id, current_user: current_user)

      resp
    end

    private

    sig do
      params(
        repo: Repository,
        current_user: User,
        id: T.nilable(Integer),
        key: T.nilable(String),
        version: T.nilable(String),
        scope: T.nilable(String),
      ).void
    end
    def emit_cache_delete(repo:, current_user:, id: nil, key: nil, version: nil, scope: nil)
      GitHub.instrument "actions_cache.delete", event_payload(repo: repo, current_user: current_user).merge(
        actions_cache_id: id,
        actions_cache_key: key,
        actions_cache_version: version,
        actions_cache_scope: scope
      )
    end

    sig do
      params(
        repo: T.untyped,
        current_user: T.untyped
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def event_payload(repo:, current_user:)
      {
        user_id: current_user.id,
        user: current_user.display_login,
        repo_id: repo.id,
        repo: repo.nwo,
      }.tap do |h|
        h[:org] = repo.organization if repo.organization.present?
        h[:business] = repo.owner.business if repo.owner.business.present?
      end
    end
  end
end
