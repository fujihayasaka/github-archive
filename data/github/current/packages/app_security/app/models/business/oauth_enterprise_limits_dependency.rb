# typed: strict
# frozen_string_literal: true

# Mixed into Business to recompute OauthEnterpriseLimit rows for every org in
# the business whenever the business's `downgraded_at` flips. A business
# downgrade/upgrade changes the effective plan of every org that delegates
# billing to the business, which can flip GHEC higher-rate-limit eligibility
# for those orgs' members' OAuth tokens.
#
# The corresponding `after_commit :recompute_oauth_enterprise_limits_for_orgs`
# callback is declared in `packages/admin/app/models/business.rb` to satisfy
# the ActiveRecordCallbackTest linter, which requires callbacks to be declared
# in the base model file.
module Business::OauthEnterpriseLimitsDependency
  extend T::Helpers

  requires_ancestor { Business }

  sig { void }
  def recompute_oauth_enterprise_limits_for_orgs
    return unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits_other_events, default: false)

    ::OauthEnterpriseLimitUpdateBusinessJob.perform_later(business_id: id)
  end
end
