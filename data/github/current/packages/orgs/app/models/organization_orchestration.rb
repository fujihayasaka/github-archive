# typed: strict
# frozen_string_literal: true

class OrganizationOrchestration < ApplicationRecord::Domain::Users
  include GitHub::Memoizer
  include Orchestration

  belongs_to :business
  belongs_to :actor, class_name: "User"
  belongs_to :parent, class_name: "OrganizationOrchestration"

  sig { returns(T.class_of(OrganizationOrchestration)) }
  def self.base_orchestration
    OrganizationOrchestration
  end

  sig { returns(T.nilable(T::Hash[Symbol, Integer])) }
  protected def target_uniqueness_condition_on_start
    nil
  end

  sig { returns(String) }
  def self.log_prefix
    "gh.orgs"
  end

  sig { returns(T.class_of(OrchestrationJob)) }
  def self.job_class
    OrganizationOrchestrationJob
  end

  sig { params(block: T.proc.void).void }
  def infer_tenant(&block)
    return yield unless GitHub.multi_tenant_enterprise? && GitHub::CurrentTenant.get.blank? && business_id.present?

    tenant = GitHub::CurrentTenant.unscope { Business.find_by(id: business_id) }

    GitHub::CurrentTenant.set(tenant) { yield }
  end

  sig { returns(T::Array[Integer]) }
  memoize def organization_ids
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

  sig { returns(T::Array[Integer]) }
  memoize def team_ids
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

  sig { returns(T::Array[Integer]) }
  memoize def user_ids
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
      "#{self.class.log_prefix}.orchestration.business_team_action" => log_business_team_action,
      "#{self.class.log_prefix}.orchestration.batch" => log_batch_action,
      "#{self.class.log_prefix}.business_id" => business_id,
      "#{self.class.log_prefix}.business.staff_owned" => log_staff_owned,
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
    ["orchestration_staff_owned:#{log_staff_owned}", "orchestration_business_team:#{log_business_team_action}", "orchestration_batch_action:#{log_batch_action}"]
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def build_hydro_event_message
    self.class.build_hydro_event_message(id)
  end

  sig { params(organization_orchestration_id: T.nilable(Integer)).returns(T::Hash[String, T.untyped]) }
  def self.build_hydro_event_message(organization_orchestration_id)
    message = {
      organization_orchestration_id: organization_orchestration_id,
      request_id: GitHub.context[:request_id],
    }
  end

  sig do
    params(
      organization_orchestration_id: T.nilable(Integer),
      message: T.nilable(T::Hash[String, T.untyped]),
      kwargs: T.untyped
    )
      .returns(Hydro::Sink::Result)
  end
  def self.publish_hydro_event(organization_orchestration_id:, message: nil, **kwargs)
    # the synchronous event publisher is used to ensure the message is successfully sent before the orchestration
    # continues
    result = GitHub.sync_hydro_publisher.publish(message || build_hydro_event_message(organization_orchestration_id), **kwargs.merge({ partition_key: organization_orchestration_id }))
    GitHub.dogstats.increment("orchestration.hydro_publish.status", tags: ["success:#{result.success?}"])
    raise HydroPublishError.new(result.error) unless result.success?
    result
  end

  sig do
    params(
      actor: T.nilable(GH::Auth::Actor),
      organizations: T::Array[Organization],
      teams: T::Array[Team],
      users: T::Array[User],
      action: String,
      business_id: T.nilable(Integer),
      caller_type: T.nilable(Symbol),
      invitation_id: T.nilable(Integer),
      perform_instrumentation: T::Boolean,
      skip_license_usage_update: T.nilable(T::Boolean),
      skip_notifications: T::Boolean,
      business_team_action: T.nilable(T::Boolean),
    )
      .returns(AddUsersOrganizationOrchestration)
  end
  def self.add_users(
    actor:,
    organizations:,
    teams:,
    users:,
    action: "read",
    business_id: nil,
    caller_type: nil,
    invitation_id: nil,
    perform_instrumentation: true,
    skip_license_usage_update: false,
    skip_notifications: false,
    business_team_action: nil
  )
    organizations.each do |org|
      users.each { |user| user.can_be_granted_permission_over!(org, action) }
    end

    with_write do
      AddUsersOrganizationOrchestration.create(
        actor: actor,
        business_id:,
        data: {
          action: action,
          caller_type: caller_type,
          invitation_id: invitation_id,
          skip_instrumentation: !perform_instrumentation,
          skip_license_usage_update: skip_license_usage_update,
          skip_notifications: skip_notifications,
          business_team_action: business_team_action || false,
        },
        data_organization_ids: encode(organizations.pluck(:id).compact),
        data_team_ids: encode(teams.pluck(:id).compact),
        data_user_ids: encode(users.pluck(:id).compact),
      )
    end
  end

  sig do
    params(
      actor: T.nilable(GH::Auth::Actor),
      organizations: T::Array[Organization],
      teams: T::Array[Team],
      users: T::Array[User],
      business_id: T.nilable(Integer),
      save_settings: T::Boolean,
      reason: T.nilable(T.any(String, Symbol)),
      remove_direct_repo_access: T::Boolean,
      background_team_remove_member: T::Boolean,
      send_notification: T::Boolean,
      business_team_action: T.nilable(T::Boolean),
    ).returns(RemoveUsersOrganizationOrchestration)
  end
  def self.remove_users(
    actor:,
    organizations:,
    teams:,
    users:,
    business_id: nil,
    save_settings: true,
    reason: nil,
    remove_direct_repo_access: true,
    background_team_remove_member: false,
    send_notification: true,
    business_team_action: nil
  )
    membership_types = {}
    organizations.each do |org|
      for_org = {}
      users.each do |user|
        for_org[user.id] = org.role_of(user).types
      end
      membership_types[org.id] = for_org
    end

    with_write do
      RemoveUsersOrganizationOrchestration.create(
        actor: actor,
        business_id:,
        data: {
          save_settings: save_settings,
          reason: reason,
          remove_direct_repo_access: remove_direct_repo_access,
          background_team_remove_member: background_team_remove_member,
          send_notification: send_notification,
          membership_types: membership_types,
          business_team_action: business_team_action || false,
        },
        data_organization_ids: encode(organizations.pluck(:id).compact),
        data_team_ids: encode(teams.pluck(:id).compact),
        data_user_ids: encode(users.pluck(:id).compact),
      )
    end
  end

  sig { params(values: T::Array[Integer]).returns(String) }
  def self.encode(values)
    values.map(&:to_i).map { |i| [i].pack("Q<") }.join("")
  end

  sig { params(values: String).returns(T::Array[Integer]) }
  def self.decode(values)
    values.unpack("Q<*").map(&:to_i).compact
  end

  sig { params(teams: T::Boolean, batch_size: Integer, block: T.proc.params(user_ids: T::Array[Integer], organization_ids: T::Array[Integer], team_ids: T.nilable(T::Array[Integer])).void).void }
  def in_batches(teams: true, batch_size: 500, &block)
    user_ids.in_groups_of(batch_size, false).each do |user_ids_batch|
      organization_ids.in_groups_of(batch_size, false).each do |organization_ids_batch|
        if teams
          team_ids.in_groups_of(batch_size, false).each do |team_ids_batch|
            block.call(user_ids_batch, organization_ids_batch, team_ids_batch)
          end
        else
          block.call(user_ids_batch, organization_ids_batch, nil)
        end
      end
    end
  end

  sig { params(feature: Symbol).returns(T::Boolean) }
  def feature_enabled?(feature)
    if business.present?
      T.must(business).feature_enabled?(feature)
    else
      Organization.where(id: organization_ids.first).first&.feature_enabled?(feature) || false
    end
  end

  sig { returns(T::Boolean) }
  def log_staff_owned
    business&.staff_owned? || false
  end


  sig { returns(T::Boolean) }
  def log_business_team_action
    data[:business_team_action] || false
  end

  sig { returns(T::Boolean) }
  def log_batch_action
    user_ids.size > 1 || organization_ids.size > 1
  end
end
