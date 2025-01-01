# typed: true
# frozen_string_literal: true

class Api::AdvisoryDatabase < Api::App
  include Api::App::AdvisoryPaginationHelpers

  ADVISORIES_PAGE_SIZE = 100
  CWES_PAGE_SIZE = 1000

  get "/advisory-database/sync-advisories", operation_id: :internal do
    @route_owner = "@github/advisory-database"

    control_access :advisory_database_sync,
      resource: current_integration,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    vulns = Vulnerability.order(:updated_at, :id)

    if params[:updated_since].present?
      vulns = vulns.where("vulnerabilities.updated_at >= ?", Time.new(params[:updated_since]))
    end

    if params[:page].present?
      # Enterprise users might still be using an older version of the API
      # that paginates via `page`. We need to support pagination via `page` until
      # all currently supported Enterprise versions paginate via the `after`
      # parameter. Pagination via `page` may be removed once GHES 3.13 is deprecated.
      # Reference: Supported versions
      #     https://github.com/github/enterprise-releases/blob/master/docs/supported-versions.md
      vulns = vulns.paginate(page: params[:page], per_page: ADVISORIES_PAGE_SIZE)
    else
      pagination_params = {
        per_page: ADVISORIES_PAGE_SIZE,
      }
      pagination_params[:after] = params[:after] if params[:after].present?
      pagination_params[:before] = params[:before] if params[:before].present?
      vulnerabilities_platform_relation = paginate_advisories(vulns, pagination_params)
      vulns = vulnerabilities_platform_relation.edge_nodes.sync
      set_cursor_based_pagination_headers(vulnerabilities_platform_relation) if vulns.any?
    end

    associations = Vulnerability.associations_for_enterprise.map do |association|
      association.to_sym
    end
    GitHub::PrefillAssociations.prefill_associations(vulns, associations)

    deliver :vulnerabilities_hash, { vulnerabilities: vulns }
  end

  get "/advisory-database/sync-cwes", operation_id: :internal do
    @route_owner = "@github/advisory-database"

    control_access :advisory_database_sync,
      resource: current_integration,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    cwes = CWE.order(:id).limit(CWES_PAGE_SIZE)

    if params[:page].present?
      cwes = cwes.paginate(page: params[:page], per_page: CWES_PAGE_SIZE)
    end

    deliver :cwe_hash, cwes
  end

  # this is policy is not applicable for this endpoint
  # this is for proxima apps that sync data from dotcom
  def tenant_verification_enforceable
    :no
  end
end
