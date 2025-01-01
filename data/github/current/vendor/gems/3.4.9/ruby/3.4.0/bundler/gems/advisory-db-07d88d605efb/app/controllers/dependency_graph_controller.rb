# frozen_string_literal: true

class DependencyGraphController < InboxController
  UnsupportedEcosystem = Class.new(StandardError)

  rescue_from DependencyGraph::Client::QueryError, with: :query_error
  rescue_from UnsupportedEcosystem, with: :unsupported_ecosystem

  def package_repo
    ecosystem = dependency_graph_ecosystem(params[:ecosystem])
    package_name = params[:package_name]
    repo_nwo = if ecosystem.present? && package_name.present?
                 client.get_package_repo(
                   package_manager: ecosystem,
                   package_name: package_name,
                 )
               end
    render_response(repo_nwo: repo_nwo)
  end

  def estimated_impact
    ecosystem = dependency_graph_ecosystem(params[:ecosystem])
    package_name = params[:package_name]
    version_range = params[:version_range]
    impact = if ecosystem.present? && package_name.present? && version_range.present?
               client.get_estimated_impact(
                 package_manager: ecosystem,
                 package_name: package_name,
                 version_range: version_range,
               )
             end
    render_response(impact: impact)
  end

  private

  def client
    @client ||= DependencyGraph::Client.new
  end

  def dependency_graph_ecosystem(ecosystem)
    return if ecosystem.blank?

    mapped_ecosystem = AdvisoryDB.dependency_graph_ecosystem(ecosystem)
    raise UnsupportedEcosystem unless mapped_ecosystem

    mapped_ecosystem
  end

  def render_response(response)
    render json: response.reverse_merge(status: 200, error: nil)
  end

  # Query errors are typically transient and due to a bad query value.
  # Log it for troubleshooting but don't report to Sentry, etc.
  def query_error(error)
    ::GitHub::Telemetry::Logs.logger.error(
      "Dependency graph query error",
      exception: error,
    )
    render_response(status: error.status, error: error.message)
  end

  def unsupported_ecosystem
    render_response(error: "Unsupported ecosystem")
  end
end
