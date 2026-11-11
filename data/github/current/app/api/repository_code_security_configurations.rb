# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeSecurityConfigurations < Api::App
  include ReceiveSchemaWithOpenApi

  get "/repositories/:repository_id/code-security-configuration", operation_id: "code-security/get-configuration-for-repository" do
    repo = find_repo!

    control_access :read_repo_code_security_configuration,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    owner = repo.owner
    halt deliver_empty(status: 204) unless owner.security_configurations_enabled?

    repo_security_config = RepositorySecurityConfiguration.find_by(repository_id: repo.id, organization_id: owner.id)
    halt deliver_empty(status: 204) if repo_security_config.nil?

    deliver(:code_security_configuration_for_repository, { repo_security_config:, target: owner, actor: current_user })
  end
end
