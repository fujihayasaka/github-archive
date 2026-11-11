# typed: true
# frozen_string_literal: true

# Centralized GlobalInstrumenter subscribers that fan out OauthEnterpriseLimit
# recompute jobs in response to events that may change which OAuth tokens
# qualify for GHEC higher rate limits.
#
# Eligibility (`Api::RateLimitConfiguration.qualifies_for_higher_limit?`) is
# determined by `org.plan.business_plus?` and `Api::RequestOwner`'s match
# against the user's organizations / OauthApplicationApprovals. The events
# below collectively cover every state change that can flip a token's
# eligibility:
#
# - billing.plan_change                      : org plan moves to/from business_plus
# - org.add_member / org.remove_member       : user's org list changes
# - enterprise_account.organization_add      : org joins a business (delegated plan changes)
# - enterprise_account.organization_remove   : org leaves a business
# - enterprise_account.organization_transfer : org moves between businesses
# - enterprise_account.organization_upgrade  : existing org upgraded into a business
# - oauth_application.transfer               : OAuth app ownership transferred between user/org
#
# Token create / delete and OauthApplicationApproval state changes are wired
# directly on the corresponding models — see OauthAccess and
# OauthApplicationApproval. Business `downgraded_at` set/unset is wired via an
# `after_commit` callback on Business that enqueues
# OauthEnterpriseLimitUpdateBusinessJob.
#
# Fan-out for the events above is gated by the
# `:authnd_oauth_enterprise_limits_other_events` feature flag, except for
# `oauth_application.transfer`, which is gated by its own
# `:authnd_oauth_enterprise_limits_app_transfer_events` feature flag.
#
# Transaction safety: every event below is emitted from within a transaction
# on the ApplicationRecord::Domain::Users cluster (User/Organization/Business
# writes). Enqueuing directly would put a job on the queue that references
# state which can still be rolled back, and trips the test-only
# `EnqueuedJobInsideTransactionError` guard. Each `perform_later` is wrapped
# in `ApplicationRecord::Domain::Users.current_transaction.after_commit`,
# which defers the enqueue until the outermost transaction on that cluster
# commits. If no transaction is open, the block runs immediately. If the
# transaction rolls back, the deferred block is dropped.

# Event: an org's plan changes (per-user/org billing transactions).
# Fans out per user with an OAuth token in the org.
GlobalInstrumenter.subscribe("billing.plan_change") do |_name, _start, _ending, _transaction_id, payload|
  next unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits_other_events, default: false)

  # Eligibility only flips when business_plus is on one side of the change.
  next unless payload[:old_plan_name] == "business_plus" || payload[:new_plan_name] == "business_plus"

  org = Organization.find_by(id: payload[:user_id])
  next unless org

  ApplicationRecord::Domain::Users.current_transaction.after_commit do
    OauthEnterpriseLimitUpdateOrganizationJob.perform_later(organization_id: org.id)
  end
end

# Event: a user is added to an org. The user's organization_ids set changes,
# which can shift Api::RequestOwner's match. Fans out per app the user holds
# a token for.
GlobalInstrumenter.subscribe("org.add_member") do |_name, _start, _ending, _transaction_id, payload|
  next unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits_other_events, default: false)

  user = payload[:user]
  user_id = user&.id || payload[:user_id]
  next unless user_id

  ApplicationRecord::Domain::Users.current_transaction.after_commit do
    OauthEnterpriseLimitUpdateUserJob.perform_later(user_id: user_id.to_i)
  end
end

# Event: a user is removed from an org. The user's organization_ids set
# changes, which can shift Api::RequestOwner's match. Fans out per app the
# user holds a token for.
GlobalInstrumenter.subscribe("org.remove_member") do |_name, _start, _ending, _transaction_id, payload|
  next unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits_other_events, default: false)

  user = payload[:user]
  user_id = user&.id || payload[:user_id]
  next unless user_id

  ApplicationRecord::Domain::Users.current_transaction.after_commit do
    OauthEnterpriseLimitUpdateUserJob.perform_later(user_id: user_id.to_i)
  end
end

# Event: an org joins a business. The org's effective plan (delegated to the
# business) may now be business_plus. Fans out per member with an OAuth token.
GlobalInstrumenter.subscribe("enterprise_account.organization_add") do |_name, _start, _ending, _transaction_id, payload|
  next unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits_other_events, default: false)
  next if payload[:new_organization]  # brand-new orgs have no members yet

  organization_id = payload[:organization_id]
  next unless organization_id

  ApplicationRecord::Domain::Users.current_transaction.after_commit do
    OauthEnterpriseLimitUpdateOrganizationJob.perform_later(organization_id: organization_id.to_i)
  end
end

# Event: an org leaves a business. The org's effective plan reverts from the
# delegated business_plus, so members may lose GHEC higher-rate-limit
# eligibility. Fans out per member with an OAuth token.
GlobalInstrumenter.subscribe("enterprise_account.organization_remove") do |_name, _start, _ending, _transaction_id, payload|
  next unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits_other_events, default: false)

  organization_id = payload[:organization_id]
  next unless organization_id

  ApplicationRecord::Domain::Users.current_transaction.after_commit do
    OauthEnterpriseLimitUpdateOrganizationJob.perform_later(organization_id: organization_id.to_i)
  end
end

# Event: an org transfers between businesses. The source/destination
# businesses may differ in downgraded state, so members' eligibility can
# flip. Fans out per member with an OAuth token.
GlobalInstrumenter.subscribe("enterprise_account.organization_transfer") do |_name, _start, _ending, _transaction_id, payload|
  next unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits_other_events, default: false)
  next unless payload[:failed_at].nil?

  organization_id = payload[:organization_id]
  next unless organization_id

  ApplicationRecord::Domain::Users.current_transaction.after_commit do
    OauthEnterpriseLimitUpdateOrganizationJob.perform_later(organization_id: organization_id.to_i)
  end
end

# Event: an existing org is upgraded into a business. The org's effective
# plan changes to business_plus, so members may gain GHEC higher-rate-limit
# eligibility. Fans out per member with an OAuth token.
GlobalInstrumenter.subscribe("enterprise_account.organization_upgrade") do |_name, _start, _ending, _transaction_id, payload|
  next unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits_other_events, default: false)

  organization_id = payload[:organization_id]
  next unless organization_id

  ApplicationRecord::Domain::Users.current_transaction.after_commit do
    OauthEnterpriseLimitUpdateOrganizationJob.perform_later(organization_id: organization_id.to_i)
  end
end

# Event: an OAuth application's ownership is transferred. The app's owner
# changes (affecting Api::RequestOwner matching) and approvals for the target
# organization are destroyed, so every existing token for this app may have
# its GHEC higher-rate-limit eligibility flip. Fans out per token holder for
# the app.
#
# Note: `instrument :transfer` fires from `OauthApplication#transfer_ownership_to`
# outside any DB transaction (and against Domain::Integrations rather than
# Domain::Users), so we enqueue directly instead of deferring via
# `ApplicationRecord::Domain::Users.current_transaction.after_commit`.
GlobalInstrumenter.subscribe("oauth_application.transfer") do |_name, _start, _ending, _transaction_id, payload|
  next unless FeatureFlag.vexi.enabled?(:authnd_oauth_enterprise_limits_app_transfer_events, default: false)

  app_id = payload[:oauth_application_id]
  next unless app_id

  application_id = app_id.to_i

  OauthEnterpriseLimitUpdateAppJob.perform_later(application_id)
end
