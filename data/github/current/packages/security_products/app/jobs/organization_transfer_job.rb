# typed: strict
# frozen_string_literal: true

class OrganizationTransferJob < AbstractOrganizationChangeFanoutJob

  queue_as :security_products_organization_transfer

  retry_on_dirty_exit

  sig { params(repository_id: Integer).void }
  def process_repository(repository_id)
    GlobalInstrumenter.instrument("enterprise_account.organization_transfer_per_repository", {
      repository_id: repository_id,
    })
  end

  protected

  sig { returns(T.untyped) }
  def logging_context
    super.merge({
      "gh.security_products.job.source_event": "organization_transfer",
    })
  end

  sig { returns(T.untyped) }
  def failbot_context
    super.merge({
      "gh.security_products.job.source_event": "organization_transfer",
    })
  end
end
