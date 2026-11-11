# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Background job that fans out a sandbox enablement write to every organization
# in a business when an enterprise admin selects "Enabled for all orgs".
#
# Uses AbstractEnterpriseChangeFanoutJob (BatchedJob) which self-re-enqueues in
# pages of BATCH_SIZE=1000 orgs, so large enterprises are handled safely.
#
# A guard at the top of process_organization aborts the fan-out if the enterprise
# has reverted away from all-orgs mode before this batch ran.
class Businesses::SandboxEnableAllOrgsJob < AbstractEnterpriseChangeFanoutJob
  queue_as :business_sandbox_enable_all_orgs

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  protected

  sig { params(organization_id: Integer).void }
  def process_organization(organization_id)
    business_id = arguments.dig(0, :business_id)
    actor_id    = arguments.dig(0, :actor_id)

    business = ::Business.find_by(id: business_id)
    # Guard: abort if the enterprise was reverted before this batch ran.
    return unless business&.github_sandbox_all_orgs_mode?

    actor = ::User.find_by(id: actor_id)
    return unless actor

    org = ::Organization.find_by(id: organization_id)
    return unless org

    with_write do
      org.update_github_sandbox_enabled(
        Configurable::GithubSandboxEnabled::ALL_MEMBERS,
        actor: actor,
        force: true,
      )
    end
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def logging_context
    super.merge({
      "gh.business.id": arguments.dig(0, :business_id),
      "gh.sandbox.job": "sandbox_enable_all_orgs",
    })
  end

  sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
  def failbot_context
    super.merge({
      "gh.business.id": arguments.dig(0, :business_id),
    })
  end
end
