# typed: strict
# frozen_string_literal: true

class TeamOrchestration < ApplicationRecord::Domain::Accounts
  include GitHub::Memoizer
  include Orchestration
  include AccountOrchestration

  belongs_to :business, optional: true
  belongs_to :team
  belongs_to :business_team, foreign_key: :team_id, class_name: "BusinessTeam" # rubocop:todo Rails/InverseOf
  belongs_to :actor, class_name: "User"
  belongs_to :parent, class_name: "TeamOrchestration"

  sig { returns(T.class_of(TeamOrchestration)) }
  def self.base_orchestration
    TeamOrchestration
  end

  sig { returns(T.nilable(T::Hash[Symbol, Integer])) }
  protected def target_uniqueness_condition_on_start
    nil
  end

  sig { returns(String) }
  def self.base_orchestration_name
    "team_orchestration"
  end

  sig { returns(String) }
  def self.log_prefix
    "gh.team"
  end

  sig { returns(T.class_of(OrchestrationJob)) }
  def self.job_class
    TeamOrchestrationJob
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
      "#{self.class.log_prefix}.orchestration.user_ids" => user_ids,
      "#{self.class.log_prefix}.orchestration.batch" => log_batch_action,
      "#{self.class.log_prefix}.business_id" => business_id,
      "#{self.class.log_prefix}.team_id" => team_id,
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
      "#{self.class.log_prefix}.team_id" => team_id,
      "#{self.class.log_prefix}.orchestration.id" => id,
      "#{self.class.log_prefix}.orchestration.step_name" => step_name,
      "#{self.class.log_prefix}.orchestration.type" => type
    }
  end

  sig { returns(T::Array[String]) }
  def datadog_tags
    ["orchestration_type:team", "orchestration_staff_owned:#{log_staff_owned}"]
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def build_hydro_event_message
    self.class.build_hydro_event_message(id)
  end

  sig { params(team_orchestration_id: T.nilable(Integer)).returns(T::Hash[String, T.untyped]) }
  def self.build_hydro_event_message(team_orchestration_id)
    message = {
      team_orchestration_id: team_orchestration_id,
      request_id: GitHub.context[:request_id],
    }
  end

  sig do
    params(
      team_orchestration_id: T.nilable(Integer),
      message: T.nilable(T::Hash[String, T.untyped]),
      kwargs: T.untyped
    )
      .returns(Hydro::Sink::Result)
  end
  def self.publish_hydro_event(team_orchestration_id:, message: nil, **kwargs)
    # the synchronous event publisher is used to ensure the message is successfully sent before the orchestration
    # continues
    result = GitHub.sync_hydro_publisher.publish(message || build_hydro_event_message(team_orchestration_id), **kwargs.merge({ partition_key: team_orchestration_id }))
    GitHub.dogstats.increment("orchestration.hydro_publish.status", tags: ["success:#{result.success?}"])
    raise HydroPublishError.new(result.error) unless result.success?
    result
  end

  sig do
    params(
      team: BusinessTeam,
      business_id: Integer,
      user_ids: T::Array[Integer],
      options: T::Hash[Symbol, T.untyped],
      actor: T.nilable(GH::Auth::Actor),
    )
      .returns(AddMembersBusinessTeamOrchestration)
  end
  def self.add_business_team_members(
    team:,
    business_id:,
    user_ids:,
    options: {},
    actor: nil
  )
    with_write do
      AddMembersBusinessTeamOrchestration.create(
        actor: actor,
        business_id:,
        team: team,
        data: {
          options: options
        },
        data_user_ids: encode(user_ids.compact),
      )
    end
  end

  sig do
    params(
      team: Team,
      user_ids: T::Array[Integer],
      caller_type: T.nilable(Symbol),
      options: T::Hash[Symbol, T.untyped],
      actor: T.nilable(GH::Auth::Actor),
    )
      .returns(AddMembersTeamOrchestration)
  end
  def self.add_team_members(
    team:,
    user_ids:,
    caller_type: nil,
    options: {},
    actor: nil
  )
    with_write do
      AddMembersTeamOrchestration.create(
        actor: actor,
        business_id: team.business&.id,
        team: team,
        data: {
          caller_type: caller_type,
          options: options
        },
        data_user_ids: encode(user_ids.compact),
      )
    end
  end

  sig do
    params(
      team: BusinessTeam,
      business_id: Integer,
      organization_ids: T::Array[Integer],
      actor: T.nilable(GH::Auth::Actor),
      skip_instrumentation: T::Boolean
    )
      .returns(AddOrganizationsBusinessTeamOrchestration)
  end
  def self.add_business_team_organizations(
    team:,
    business_id:,
    organization_ids:,
    actor: nil,
    skip_instrumentation: false
  )
    with_write do
      AddOrganizationsBusinessTeamOrchestration.create(
        actor: actor,
        business_id:,
        team: team,
        data_organization_ids: encode(organization_ids.compact),
        data: {
          skip_instrumentation: skip_instrumentation
        }
      )
    end
  end

  sig do
    params(
      team: BusinessTeam,
      business_id: Integer,
      user_ids: T::Array[Integer],
      options: T::Hash[Symbol, T.untyped],
      actor: T.nilable(GH::Auth::Actor),
    )
      .returns(RemoveMembersBusinessTeamOrchestration)
  end
  def self.remove_business_team_members(
    team:,
    business_id:,
    user_ids:,
    options: {},
    actor: nil
  )
    with_write do
      RemoveMembersBusinessTeamOrchestration.create(
        actor: actor,
        business_id:,
        team: team,
        data: {
          options: options
        },
        data_user_ids: encode(user_ids.compact),
      )
    end
  end

  sig do
    params(
      team: Team,
      user_ids: T::Array[Integer],
      caller_type: T.nilable(Symbol),
      options: T::Hash[Symbol, T.untyped],
      actor: T.nilable(GH::Auth::Actor),
    )
      .returns(RemoveMembersTeamOrchestration)
  end
  def self.remove_team_members(
    team:,
    user_ids:,
    caller_type: nil,
    options: {},
    actor: nil
  )
    with_write do
      RemoveMembersTeamOrchestration.create(
        actor: actor,
        business_id: team.business&.id,
        team: team,
        data: {
          caller_type: caller_type,
          options: options
        },
        data_user_ids: encode(user_ids.compact),
      )
    end
  end

  sig do
    params(
      team: BusinessTeam,
      business_id: Integer,
      organization_ids: T::Array[Integer],
      actor: T.nilable(GH::Auth::Actor),
    )
      .returns(RemoveOrganizationsBusinessTeamOrchestration)
  end
  def self.remove_business_team_organizations(
    team:,
    business_id:,
    organization_ids:,
    actor: nil
  )
    with_write do
      RemoveOrganizationsBusinessTeamOrchestration.create(
        actor: actor,
        business_id:,
        team: team,
        data_organization_ids: encode(organization_ids.compact),
      )
    end
  end

  sig do
    params(
      team: BusinessTeam,
      business_id: Integer,
      actor: T.nilable(GH::Auth::Actor),
    )
      .returns(OrgSelectionTypeChangedBusinessTeamOrchestration)
  end
  def self.org_selection_type_changed(
    team:,
    business_id:,
    actor: nil
  )
    with_write do
      OrgSelectionTypeChangedBusinessTeamOrchestration.create(
        actor: actor,
        business_id:,
        team: team,
      )
    end
  end

  sig { params(feature: Symbol).returns(T::Boolean) }
  def feature_enabled?(feature)
    return T.must(business).feature_flag_enabled_or_raise?(feature) if business.present? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    false
  end

  sig { returns(T::Boolean) }
  def log_staff_owned
    if business.present?
      T.must(business).staff_owned?
    else
      false
    end
  end

  sig { returns(T::Boolean) }
  def log_batch_action
    false
  end

  sig { returns(Team) }
  memoize def orchestration_team
    Team.with_business_teams.find(team_id)
  end
end
