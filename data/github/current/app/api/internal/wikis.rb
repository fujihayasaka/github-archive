# typed: true
# frozen_string_literal: true

class Api::Internal::Wikis < Api::Internal
  # Internal: Perform an audit of wiki state. For each provided wiki id, returns the wiki id and result of audit,
  # indicating if the wiki is active, inactive, archived, or not_found.
  # These audits are performed by the git backend to look for orphaned git data that can be purged.
  post "/internal/wikis/audits", operation_id: :internal, exempt_from_tenant_context_requirement: true do
    @route_owner = "@github/repos"

    data = receive_with_schema("wiki-audit", "create")
    ids = Set.new(data["repository_ids"])
    results = []

    if ids.count > max_wiki_audit_ids_count
      deliver_error!(
        422,
        message: "Too many ids, at most #{max_wiki_audit_ids_count} ids can be audited in one request."
      )
    end

    # wikis belong to repositories and can't exist without them
    Repository.where(id: ids).each do |repo|
      if RepositoryWiki.find_by(repository: repo)
        status = repo.active ? "active" : "inactive"
      else
        GitHub.logger.info(
          "Wiki not found",
          "code.namespace" => "Api::Internal::Wikis",
          "code.function" => "wiki.audit.not_found",
          "gh.repo.id" => repo.id
        )
        status = "not_found"
      end
      results << audit_result(repo.id, status)
      ids.delete(repo.id)
    end

    ids.each do |id|
      GitHub.logger.info(
        "Repository not found",
        "code.namespace" => "Api::Internal::Wikis",
        "code.function" => "wiki.audit.not_found",
        "gh.repo.id" => id
      )
      results << audit_result(id, "not_found")
    end

    results.each do |value|
      result = value[:result]
      GitHub.dogstats.increment("wiki.audit", tags: ["result:#{result}"])
    end

    audit = { results: results }
    deliver_raw audit, status: 200
  end

  def externally_accessible?
    false
  end

  def require_request_hmac?
    true
  end

  def authenticated_for_private_mode?
    true
  end

  # Relax user-agent requirements for internal API endpoints used by babeld
  def user_agent_allows_access_to_garage_hosts?
    request.user_agent =~ /#{GitHub.current_sha}|^babeld\/.*/
  end

  def audit_result(id, result)
    {
      repository_id: id,
      result: result
    }
  end

  def max_wiki_audit_ids_count
    5000
  end
end
