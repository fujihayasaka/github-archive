# typed: strict
# frozen_string_literal: true

class BusinessOrchestration < ApplicationRecord::Domain::Accounts
  include GitHub::Memoizer
  include Orchestration
  include AccountOrchestration

  belongs_to :business, optional: true
  belongs_to :actor, class_name: "User"
  belongs_to :parent, class_name: "BusinessOrchestration"

  sig { returns(T.class_of(BusinessOrchestration)) }
  def self.base_orchestration
    BusinessOrchestration
  end

  sig { returns(T.nilable(T::Hash[Symbol, Integer])) }
  protected def target_uniqueness_condition_on_start
    nil
  end

  sig { returns(String) }
  def self.base_orchestration_name
    "business_orchestration"
  end

  sig { returns(String) }
  def self.log_prefix
    "gh.business"
  end

  sig { returns(T.class_of(OrchestrationJob)) }
  def self.job_class
    BusinessOrchestrationJob
  end

  sig { params(block: T.proc.void).void }
  def infer_tenant(&block)
    return yield unless GitHub.multi_tenant_enterprise? && GitHub::CurrentTenant.get.blank? && business_id.present?

    tenant = GitHub::CurrentTenant.unscope { Business.find_by(id: business_id) }

    GitHub::CurrentTenant.set(tenant) { yield }
  end

  sig { returns(T.nilable(T::Array[Integer])) }
  memoize def organization_ids
    return nil if data_organization_ids.nil?
    self.class.decode(data_organization_ids)
  end

  sig { params(ids: T::Array[Integer]).void }
  def organization_ids=(ids)
    self.data_organization_ids = self.class.encode(ids)
  end

  sig { returns(ActiveRecord::Relation) }
  def organizations
    Organization.where(id: organization_ids)
  end

  sig { returns(T.nilable(T::Array[Integer])) }
  memoize def team_ids
    return nil if data_team_ids.nil?
    self.class.decode(data_team_ids)
  end

  sig { params(ids: T::Array[Integer]).void }
  def team_ids=(ids)
    self.data_team_ids = self.class.encode(ids)
  end

  sig { returns(ActiveRecord::Relation) }
  def teams
    Team.where(id: team_ids)
  end

  sig { returns(T.nilable(T::Array[Integer])) }
  memoize def user_ids
    return nil if data_user_ids.nil?
    self.class.decode(data_user_ids)
  end

  sig { params(ids: T::Array[Integer]).void }
  def user_ids=(ids)
    self.data_user_ids = self.class.encode(ids)
  end

  sig { returns(ActiveRecord::Relation) }
  def users
    User.where(id: user_ids)
  end

  sig { params(options: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
  def log_data(options = {})
    {
      "code.namespace" => self.class.name,
      "#{self.class.log_prefix}.orchestration.id" => id,
      "#{self.class.log_prefix}.orchestration.type" => type,
      "#{self.class.log_prefix}.orchestration.state" => state,
      "#{self.class.log_prefix}.orchestration.step_name" => step_name,
      "#{self.class.log_prefix}.orchestration.attempts" => attempts,
      "#{self.class.log_prefix}.orchestration.data" => data,
      "#{self.class.log_prefix}.orchestration.organization_ids" => organization_ids,
      "#{self.class.log_prefix}.orchestration.team_ids" => team_ids,
      "#{self.class.log_prefix}.orchestration.user_ids" => user_ids,
      "#{self.class.log_prefix}.orchestration.batch" => log_batch_action,
      "#{self.class.log_prefix}.business_id" => business_id,
      "#{self.class.log_prefix}.business.staff_owned" => log_staff_owned,
      "gh.business.id" => business_id,
      "gh.actor.id" => data[:actor_id],
      "gh.request_id" => GitHub.context[:request_id],
    }.merge(options)
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def failbot_data
    {
      "#{self.class.log_prefix}.business_id" => business_id,
      "#{self.class.log_prefix}.orchestration.id" => id,
      "#{self.class.log_prefix}.orchestration.step_name" => step_name,
      "#{self.class.log_prefix}.orchestration.type" => type
    }
  end

  sig { returns(T::Array[String]) }
  def datadog_tags
    ["orchestration_type:business", "orchestration_staff_owned:#{log_staff_owned}"]
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def build_hydro_event_message
    self.class.build_hydro_event_message(id)
  end

  sig { params(business_orchestration_id: T.nilable(Integer)).returns(T::Hash[String, T.untyped]) }
  def self.build_hydro_event_message(business_orchestration_id)
    message = {
      business_orchestration_id: business_orchestration_id,
      request_id: GitHub.context[:request_id],
    }
  end

  sig do
    params(
      business_orchestration_id: T.nilable(Integer),
      message: T.nilable(T::Hash[String, T.untyped]),
      kwargs: T.untyped
    )
      .returns(Hydro::Sink::Result)
  end
  def self.publish_hydro_event(business_orchestration_id:, message: nil, **kwargs)
    # the synchronous event publisher is used to ensure the message is successfully sent before the orchestration
    # continues
    result = GitHub.sync_hydro_publisher.publish(message || build_hydro_event_message(business_orchestration_id), **kwargs.merge({ partition_key: business_orchestration_id }))
    GitHub.dogstats.increment("orchestration.hydro_publish.status", tags: ["success:#{result.success?}"])
    raise HydroPublishError.new(result.error) unless result.success?
    result
  end

  sig do
    params(
      business: Business,
      user_ids: T::Array[Integer],
      actor: T.nilable(User),
      send_email_notification: T::Boolean,
      staff_action: T::Boolean
    ).returns(AddOwnersBusinessOrchestration)
  end
  def self.add_owners(
    business:,
    user_ids:,
    actor:,
    send_email_notification: false,
    staff_action: false
  )
    with_write do
      AddOwnersBusinessOrchestration.create(
        business: business,
        actor: actor,
        data_user_ids: encode(user_ids.compact),
        data: {
          send_email_notification: send_email_notification,
          staff_action: staff_action
        }
      )
    end
  end

  sig do
    params(
      business: Business,
      user_ids: T::Array[Integer],
      actor: T.nilable(User),
      reason: T.nilable(String),
      send_notification: T::Boolean,
      new_role: T.nilable(Symbol)
    ).returns(RemoveOwnersBusinessOrchestration)
  end
  def self.remove_owners(
    business:,
    user_ids:,
    actor:,
    reason: nil,
    send_notification: true,
    new_role: nil
  )
    with_write do
      RemoveOwnersBusinessOrchestration.create(
        business: business,
        actor: actor,
        data_user_ids: encode(user_ids.compact),
        data: {
          reason: reason,
          send_notification: send_notification,
          new_role: new_role
        }
      )
    end
  end

  sig do
    params(
      business: Business,
      user_ids: T::Array[Integer],
      actor: T.nilable(User),
      send_email_notification: T::Boolean,
      staff_action: T::Boolean
    ).returns(AddBillingManagersBusinessOrchestration)
  end
  def self.add_billing_managers(
    business:,
    user_ids:,
    actor:,
    send_email_notification: false,
    staff_action: false
  )
    with_write do
      AddBillingManagersBusinessOrchestration.create(
        business: business,
        actor: actor,
        data_user_ids: encode(user_ids.compact),
        data: {
          send_email_notification: send_email_notification,
          staff_action: staff_action
        }
      )
    end
  end

  sig do
    params(
      business: Business,
      user_ids: T::Array[Integer],
      actor: T.nilable(User),
      reason: T.nilable(String),
      send_email_notification: T::Boolean,
      new_role: T.nilable(Symbol)
    ).returns(RemoveBillingManagersBusinessOrchestration)
  end
  def self.remove_billing_managers(
    business:,
    user_ids:,
    actor:,
    reason: nil,
    send_email_notification: true,
    new_role: nil
  )
    with_write do
      RemoveBillingManagersBusinessOrchestration.create(
        business: business,
        actor: actor,
        data_user_ids: encode(user_ids.compact),
        data: {
          reason: reason,
          send_email_notification: send_email_notification,
          new_role: new_role,
        }
      )
    end
  end

  sig do
    params(
      user_ids: T::Array[Integer],
      business: Business,
      business_roles_bitfield: T.nilable(Integer)
    ).returns(AddUserAccountsBusinessOrchestration)
  end
  def self.add_user_accounts(
    user_ids:,
    business:,
    business_roles_bitfield: nil
  )
    with_write do
      AddUserAccountsBusinessOrchestration.create(
        business:,
        data: {
          business_roles_bitfield: business_roles_bitfield
        },
        data_user_ids: encode(user_ids.compact),
      )
    end
  end

  sig do
    params(
      business: Business,
      user_ids: T::Array[Integer],
      actor: T.nilable(User),
      reason: T.nilable(String),
      send_notification: T::Boolean,
    ).returns(RemoveMembersBusinessOrchestration)
  end
  def self.remove_members(
    business:,
    user_ids:,
    actor:,
    reason: nil,
    send_notification: true
  )
    with_write do
      RemoveMembersBusinessOrchestration.create(
        business: business,
        actor: actor,
        data: {
          reason: reason,
          send_notification: send_notification
        },
        data_user_ids: encode(user_ids.compact),
      )
    end
  end

  sig do
    params(
      business: Business,
      organization_ids: T::Array[Integer],
      organization_upgrade: T::Boolean,
      new_organization: T::Boolean,
      actor: T.nilable(User),
      ensure_sufficient_licenses: T::Boolean
    ).returns(AddOrganizationsBusinessOrchestration)
  end
  def self.add_organizations(
    business:,
    organization_ids:,
    organization_upgrade: false,
    new_organization: false,
    actor: nil,
    ensure_sufficient_licenses: true
  )
    with_write do
      AddOrganizationsBusinessOrchestration.create(
        business: business,
        actor: actor,
        data: {
          organization_upgrade: organization_upgrade,
          new_organization: new_organization,
          ensure_sufficient_licenses: ensure_sufficient_licenses,
        },
        data_organization_ids: encode(organization_ids.compact),
      )
    end
  end

  sig do
    params(
      business: Business,
      organization_ids: T::Array[Integer],
      is_transfer: T::Boolean,
      actor: T.nilable(User),
      remove_unaffiliated_users: T::Boolean,
    ).returns(RemoveOrganizationsBusinessOrchestration)
  end
  def self.remove_organizations(
    business:,
    organization_ids:,
    is_transfer: false,
    actor: nil,
    remove_unaffiliated_users: false
  )
    with_write do
      RemoveOrganizationsBusinessOrchestration.create(
        business: business,
        actor: actor,
        data: {
          is_transfer: is_transfer,
          remove_unaffiliated_users: remove_unaffiliated_users,
        },
        data_organization_ids: encode(organization_ids.compact)
      )
    end
  end

  sig do
    params(
      business: Business,
      organization_ids: T::Array[Integer],
      target_business_id: Integer,
      actor: T.nilable(User)
    ).returns(TransferOrganizationsBusinessOrchestration)
  end
  def self.transfer_organizations(
    business:,
    organization_ids:,
    target_business_id:,
    actor: nil
  )
    with_write do
      TransferOrganizationsBusinessOrchestration.create(
        business: business,
        actor: actor,
        data: {
          target_business_id: target_business_id,
        },
        data_organization_ids: encode(organization_ids.compact)
      )
    end
  end

  sig do
    params(
      business: Business,
      user_ids: T::Array[Integer],
      organization_ids: T::Array[Integer],
      reason: T.nilable(String),
      actor: T.nilable(GH::Auth::Actor),
      remove_direct_repo_access: T::Boolean,
      remove_team_membership: T::Boolean,
      remove_user_roles: T::Boolean,
      business_team_operation: T::Boolean
    )
      .returns(RemoveOrganizationMembersCleanupBusinessOrchestration)
  end
  def self.remove_organization_members_cleanup(
    business:,
    user_ids:,
    organization_ids:,
    reason: nil,
    actor: nil,
    remove_direct_repo_access: false,
    remove_team_membership: true,
    remove_user_roles: true,
    business_team_operation: false
  )
    with_write do
      RemoveOrganizationMembersCleanupBusinessOrchestration.create(
        actor:,
        business:,
        data: {
          reason:,
          remove_direct_repo_access:,
          remove_team_membership:,
          remove_user_roles:,
          business_team_operation:,
        },
        data_user_ids: encode(user_ids.compact),
        data_organization_ids: encode(organization_ids.compact)
      )
    end
  end

  sig do
    params(
      business: Business,
      actor: T.nilable(User)
    ).returns(UpgradeFromOrganizationBusinessOrchestration)
  end
  def self.upgrade_from_organization(
    business:,
    actor: nil
  )
    with_write do
      UpgradeFromOrganizationBusinessOrchestration.create(
        business: business,
        actor: actor,
      )
    end
  end

  sig do
    params(
      business: Business,
      actor: T.nilable(User),
    ).returns(CompleteCreationFromCouponBusinessOrchestration)
  end
  def self.complete_creation_from_coupon(
    business:,
    actor: nil
  )
    with_write do
      CompleteCreationFromCouponBusinessOrchestration.create(
        business: business,
        actor: actor,
      )
    end
  end

  sig do
    params(
      business: Business,
      actor: T.nilable(User),
      staff_initiated: T::Boolean,
      switch_billing_to_invoice: T::Boolean
    ).returns(ConvertTrialBusinessOrchestration)
  end
  def self.convert_trial(
    business:,
    actor: nil,
    staff_initiated: false,
    switch_billing_to_invoice: false
  )
    with_write do
      ConvertTrialBusinessOrchestration.create(
        business: business,
        actor: actor,
        data: {
          staff_initiated: staff_initiated,
          switch_billing_to_invoice: switch_billing_to_invoice
        }
      )
    end
  end

  sig do
    params(
      business: Business,
      actor: T.nilable(User),
      staff_initiated: T::Boolean
    ).returns(CancelTrialBusinessOrchestration)
  end
  def self.cancel_trial(
    business:,
    actor: nil,
    staff_initiated: false
  )
    with_write do
      CancelTrialBusinessOrchestration.create(
        business: business,
        actor: actor,
        data: {
          staff_initiated: staff_initiated
        }
      )
    end
  end

  sig do
    params(
      business: Business,
      actor: T.nilable(User),
    ).returns(ExpireTrialBusinessOrchestration)
  end
  def self.expire_trial(
    business:,
    actor: nil
  )
    with_write do
      ExpireTrialBusinessOrchestration.create(
        business: business,
        actor: actor
      )
    end
  end

  sig { params(feature: Symbol).returns(T::Boolean) }
  def feature_enabled?(feature)
    T.must(business).feature_flag_enabled_or_raise?(feature) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage:
  end

  sig { returns(T::Boolean) }
  def log_staff_owned
    T.must(business).staff_owned?
  end

  sig { returns(T::Boolean) }
  def log_batch_action
    return true if user_ids && T.must(user_ids).size > 1
    return T.must(organization_ids).size > 1 if organization_ids&.any?
    false
  end

  sig { params(orgs: T::Boolean, batch_size: Integer, block: T.proc.params(user_ids: T::Array[Integer], organization_ids: T.nilable(T::Array[Integer])).void).void }
  def in_batches(orgs: true, batch_size: 500, &block)
    (user_ids || []).in_groups_of(batch_size, false).each do |user_ids_batch|
      if orgs
        (organization_ids || []).in_groups_of(batch_size, false).each do |organization_ids_batch|
          block.call(user_ids_batch, organization_ids_batch)
        end
      else
        block.call(user_ids_batch, nil)
      end
    end
  end

  sig { params(step: Symbol, key: String).returns(T::Array[Integer]) }
  def step_completed_for(step, key)
    (data["completed_#{step}"] || {})[key] || []
  end

  sig { params(step: Symbol, key: String, value: Integer).void }
  def mark_step_completed(step, key, value)
    completed = data["completed_#{step}"] || {}
    completed_steps = completed[key] || []
    completed[key] = completed_steps + [value]
    self.data["completed_#{step}"] = completed
    with_write { update(data: self.data) }
  end

  sig { params(step: Symbol, key: String).void }
  def clear_completed(step, key)
    completed = data["completed_#{step}"] || {}
    completed[key] = []
    self.data["completed_#{step}"] = completed
    with_write { update(data: self.data) }
  end
end
