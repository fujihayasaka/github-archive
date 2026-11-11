# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  # Note on GHES, there is only one business so organization transfers aren't thing
  class OrganizationTransferredJob < AbstractOrganizationChangeFanoutJob

    queue_as :security_products_enablement_organization_transferred

    retry_on_dirty_exit

    sig { params(repository_id: Integer).void }
    def process_repository(repository_id)
      rsc = RepositorySecurityConfiguration.find_by(repository_id: repository_id)
      if rsc.present? && T.must(rsc.security_configuration).target_type == "Business"
        repo = Repositories::Public.get_active_or_deleted!(repository_id)
        org = Organization.find_by(id: arguments[0][:organization_id])
        visibility = repo.public? ? :public : :private

        default_configuration = SecurityConfigurationDefault.find_for(target: arguments[0][:destination_enterprise], visibility:).first

        if default_configuration
          T.must(default_configuration.security_configuration).apply_to_repository(
            repo,
            actor: arguments[0][:actor],
            override_existing_config: true,
            reason: :org_transfer
          )
        else
          ActiveRecord::Base.connected_to(role: :writing) do
            rsc.destroy
          end
        end
      end
    end

    protected

    sig { returns(T.untyped) }
    def logging_context
      super.merge({
        "gh.security_products.job.source_event": "security_products_enablement_organization_transferred",
      })
    end

    sig { returns(T.untyped) }
    def failbot_context
      super.merge({
        "gh.security_products.job.source_event": "security_products_enablement_organization_transferred",
      })
    end
  end
end
