# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module ActionsCacheManagementHelper
  class << self

    def get_repo_caches(repo:, key:, ref:, per_page: 30, page: 1, sort: "last_accessed_at", direction: "desc")
      Launch::Twirp.cache_client.list_caches(owner: repo, key:, ref:, per_page:, page:, sort:, direction:)
    end

    def deletes_repo_cache_by_key(repo:, key:, ref:, current_user:)
      resp = Launch::Twirp.cache_client.delete_caches_by_key(repo:, key:, ref:)
      return resp unless resp.call_succeeded?

      resp.value.caches.each do |cache|
        emit_cache_delete(repo: repo, id: cache.id, key: cache.key, version: cache.version, scope: cache.scope, current_user: current_user)
      end

      resp
    end

    def delete_repo_cache_by_id(repo:, id:, current_user:)
      resp = ::Launch::Twirp.cache_client.delete_cache_by_id(repo:, cache_id: id)
      return resp unless resp.call_succeeded?

      emit_cache_delete(repo: repo, id: id, current_user: current_user)

      resp
    end

    private

    def emit_cache_delete(repo:, id: nil, key: nil, version: nil, scope: nil, current_user:)
      GitHub.instrument "actions_cache.delete", event_payload(repo: repo, current_user: current_user).merge(
        actions_cache_id: id,
        actions_cache_key: key,
        actions_cache_version: version,
        actions_cache_scope: scope
      )
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
