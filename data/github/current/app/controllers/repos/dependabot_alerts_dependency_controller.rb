# typed: true
# frozen_string_literal: true

# This controller provides additional information from Dependency Graph services for the package affected by
# the Alert which cannot be denormalised unto the Alert itself, e.g. transitive relationships to other packages.
class Repos::DependabotAlertsDependencyController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    only: [:show]

  before_action :require_user_can_view_dependabot_alerts
  before_action :require_dependency_relationship_data_service
  before_action :fetch_alert

  UNEXPECTED_ERROR_STR = [
    "The transitive paths are currently unavailable due to a system error.",
    "Please try reloading the page, or come back later."
  ].join(" ").freeze

  def show
    response = dgp_alerting_client.get_dependency_relationships(
      repository_id: current_repository.id,
      package_name: T.must(current_alert.package_name),
      manifest_path: current_alert.vulnerable_manifest_path,
      requirements: current_alert.vulnerable_requirements,
      include_snapshots: true
    )

    transitive_paths = response.dependencies.to_a
    render DependabotAlerts::TransitivePathsComponent.new(alert: current_alert, transitive_paths:), layout: false
  rescue DependencyGraphPlatform::Twirp::BaseError, ArgumentError => err
    Failbot.report(err)
    render DependabotAlerts::TransitivePathsErrorComponent.new(error: UNEXPECTED_ERROR_STR), layout: false
  end

  private

  attr_reader :current_alert

  sig { void }
  def require_user_can_view_dependabot_alerts
    render_404 unless current_repository.can_view_vulnerability_alerts?(current_user)
  end

  sig { void }
  def require_dependency_relationship_data_service
    render_404 unless ::DependencyGraph::VulnerabilityScanning.relationship_information_available?
  end

  sig { returns(DependencyGraphPlatform::Twirp::AlertingClient) }
  memoize def dgp_alerting_client
    DependencyGraphPlatform::Twirp::AlertingClient.new
  end

  def fetch_alert
    @current_alert = current_repository.
      repository_vulnerability_alerts.
      without_default_scope. # Remove the "active" default scope
      find_by(number: params.require(:number))
  end
end
