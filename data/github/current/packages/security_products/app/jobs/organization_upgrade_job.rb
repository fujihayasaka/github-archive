# typed: strict
# frozen_string_literal: true

class OrganizationUpgradeJob < AbstractOrganizationChangeFanoutJob
  queue_as :security_products_organization_upgrade

  retry_on_dirty_exit

  sig { params(repository_id: Integer).void }
  def process_repository(repository_id)
    GlobalInstrumenter.instrument("enterprise_account.organization_upgrade_per_repository", {
      repository_id: repository_id,
      organization_upgrade_envelope: arguments.dig(0, :original_message_envelope),
    })
  end

  protected

  sig { returns(T.untyped) }
  def logging_context
    super.merge({
      "gh.security_products.job.source_event": "organization_upgrade",
    })
  end

  sig { returns(T.untyped) }
  def failbot_context
    super.merge({
      "gh.security_products.job.source_event": "organization_upgrade",
    })
  end
end
