# typed: true
# frozen_string_literal: true

class Api::Internal::Gists < Api::Internal
  # Internal: Given a gist identifier, returns the gist database ID and repo name.
  get "/internal/gists/:id", operation_id: :internal do
    @route_owner = "@github/repos"

    gist = if include_hidden?
      record_or_404(find_gist_including_deleted_and_disabled)
    else
      find_gist!
    end

    deliver :internal_gist_hash, gist
  end

  # Internal: Perform an audit of gist state. For each provided gist id, returns the gist id and result of audit,
  # indicating if the gist is active, inactive, archived, or not_found.
  # These audits are performed by the git backend to look for orhpaned git data that can be purged.
  post "/internal/gists/audits", operation_id: :internal, exempt_from_tenant_context_requirement: true do
    @route_owner = "@github/repos"

    data = receive_with_schema("gist-audit", "create")
    ids = Set.new(data["gist_ids"])
    results = []

    if ids.count > max_gist_audit_ids_count
      deliver_error!(
        422,
        message: "Too many ids, at most #{max_gist_audit_ids_count} ids can be audited in one request."
      )
    end

    Gist.where(id: ids).pluck(:id, :delete_flag).each do |gist_id, delete_flag|
      status = delete_flag ? "inactive" : "active"
      results << audit_result(gist_id, status)
      ids.delete(gist_id)
    end

    ids.each do |id|
      GitHub.logger.info(
        "Gist not found",
        "code.namespace" => "Api::Internal::Gists",
        "code.function" => "gist.audit.not_found",
        "gh.gist.id" => id
      )
      results << audit_result(id, "not_found")
    end

    results.each do |value|
      result = value[:result]
      GitHub.dogstats.increment("gist.audit", tags: ["result:#{result}"])
    end

    audit = { results: results }
    deliver_raw audit, status: 200
  end

  def include_hidden?
    params[:include_hidden] == "true"
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
      gist_id: id,
      result: result
    }
  end

  def max_gist_audit_ids_count
    5000
  end
end
