# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class CreateAutoInactiveDeploymentStatuses < ApplicationJob
  queue_as :create_auto_inactive_deployment_statuses

  resolve_tenant_context do |message|
    Repositories::Public.resolve_tenant(id: message[:repository_id])
  end

  def perform(deployment, include_production, environment_url = nil)
    deployment.set_previous_environment_deployments_inactive!(include_production: include_production, environment_url: environment_url)
  end
end
