# typed: true
# frozen_string_literal: true

class OrganizationMembershipEntry < ApplicationRecord::Domain::Users
  include GitHub::BatchedScope

  BATCH_SIZE = 200

  enum :adder_type, { admin: 0, external_team: 1, enterprise_team: 2 }

  belongs_to :user
  belongs_to :organization
  validates :user_id, presence: true
  validates :organization_id, presence: true
  validates :adder_id, presence: true
  validates :adder_type, presence: true, inclusion: { in: adder_types.keys }
  validates :ability_id, presence: true

  sig do
    params(
      user: User,
      organization_id: T.nilable(Integer),
      adder_id: T.nilable(Integer),
      ability_id: T.nilable(Integer),
      derived: T::Boolean,
      adder_type: Symbol,
    )
    .returns(T.nilable(OrganizationMembershipEntry))
  end
  def self.create_entry(user:, organization_id:, adder_id:, ability_id:, derived:, adder_type: :admin)
    return unless user.user?

    if enterprise_team_enabled?(organization_id)
      # we'll just create it with the given adder type if it is passed in. :admin can't have more than 1 entry though
      return if adder_type == :admin && explicit?(user: user, organization_id: organization_id, ability_id: ability_id)
    else
      if !derived
        return if explicit?(user: user, organization_id: organization_id, ability_id: ability_id)
        adder_type = :admin
      else
        adder_type = :external_team
      end
    end

    create!(user_id: user.id, organization_id: organization_id, adder_id: adder_id, adder_type: adder_type, ability_id: ability_id)
  end

  sig do
    params(
      abilities: T.any(ActiveRecord::Relation, T::Array[Ability]),
      organization_id: Integer,
      adder_id: Integer,
      derived: T::Boolean,
      adder_type: Symbol,
    )
    .void
  end
  def self.bulk_create_entry(abilities:, organization_id:, adder_id:, derived:, adder_type: :admin)
    unless enterprise_team_enabled?(organization_id)
      if !derived
        adder_type = :admin
      else
        adder_type = :external_team
      end
    end

    batch = abilities.map { |ability| { user_id: ability.actor_id, organization_id: organization_id, adder_id: adder_id, adder_type: adder_type, ability_id: ability.id } }
    OrganizationMembershipEntry.insert_all(batch)
  end

  sig do
    params(
      user: User,
      organization_id: Integer,
      ability_id: Integer,
      derived: T::Boolean,
      adder_id: T.nilable(Integer),
      adder_type: Symbol,
    )
    .returns(Integer)
  end
  def self.remove_entry(user:, organization_id:, ability_id:, derived:, adder_id: nil, adder_type: :admin)
    return 0 unless user.user?

    if enterprise_team_enabled?(organization_id)
      if adder_type == :admin
        entries = where(user_id: user.id, organization_id: organization_id, adder_type: adder_type, ability_id: ability_id)
        with_write { entries.delete_all }
      else
        return 0 if adder_id.nil?
        entries = where(user_id: user.id, organization_id: organization_id, adder_id: adder_id, adder_type: adder_type, ability_id: ability_id)
        with_write { entries.delete_all }
      end
    else
      return 0 if derived && adder_id.nil?
      if !derived
        entries = where(user_id: user.id, organization_id: organization_id, adder_type: :admin, ability_id: ability_id)
        with_write { entries.delete_all }
      else
        entries = where(user_id: user.id, organization_id: organization_id, adder_id: adder_id, adder_type: :external_team, ability_id: ability_id)
        with_write { entries.delete_all }
      end
    end
  end

  sig do
    params(
      user_ids: T::Array[Integer],
      organization_id: Integer,
      derived: T::Boolean,
      adder_id: T.nilable(Integer),
      adder_type: T.nilable(Symbol),
    )
    .returns(T::Array[Integer])
  end
  def self.bulk_remove_entry(user_ids:, organization_id:, derived:, adder_id: nil, adder_type: :admin)
    return [] unless user_ids.any?

    enterprise_team_enabled = enterprise_team_enabled?(organization_id)
    return [] if enterprise_team_enabled && adder_type != :admin && adder_id.nil?
    return [] if !enterprise_team_enabled && derived && adder_id.nil?

    removed_user_ids = T.let([], T::Array[Integer])

    user_ids.each_slice(BATCH_SIZE) do |ids|
      entries = if enterprise_team_enabled
        if adder_type == :admin
          where(user_id: ids, organization_id: organization_id, adder_type: adder_type)
        else
          where(user_id: ids, organization_id: organization_id, adder_id: adder_id, adder_type: adder_type)
        end
      else
        if !derived
          where(user_id: ids, organization_id: organization_id, adder_type: :admin)
        else
          where(user_id: ids, organization_id: organization_id, adder_id: adder_id, adder_type: :external_team)
        end
      end

      removed_user_ids += entries.pluck(:user_id)
      with_write { entries.delete_all }
    end

    removed_user_ids
  end

  # Returns whether the given user currently has explicit membership to the organization
  sig do
    params(
      user: User,
      organization_id: T.nilable(Integer),
      ability_id: T.any(T::Array[Integer], T.nilable(Integer)),
      db_connection: Symbol,
    )
    .returns(T::Boolean)
  end
  def self.explicit?(user:, organization_id:, ability_id:, db_connection: :reading)
    return false unless user.user?

    ActiveRecord::Base.connected_to(role: db_connection) do
      where(user_id: user.id, organization_id: organization_id, adder_type: :admin, ability_id: ability_id).any?
    end
  end

  # Returns whether the given user currently has derived membership to the organization
  sig do
    params(
      user: User,
      organization_id: Integer,
      ability_id: T.any(T::Array[Integer], Integer),
      db_connection: Symbol,
    )
    .returns(T::Boolean)
  end
  def self.derived?(user:, organization_id:, ability_id:, db_connection: :reading)
    return false unless user.user?

    ActiveRecord::Base.connected_to(role: db_connection) do
      where(user_id: user.id, organization_id: organization_id, adder_type: :external_team, ability_id: ability_id).any?
    end
  end

  # Returns an array of user_ids that have derived membership to the organization
  sig do
    params(
      user_ids: T::Array[User],
      organization_id: Integer,
      db_connection: Symbol,
    )
    .returns(T::Array[Integer])
  end
  def self.derived_user_ids(user_ids:, organization_id:, db_connection: :reading)
    return [] unless user_ids.any?

    ActiveRecord::Base.connected_to(role: db_connection) do
      where(user_id: user_ids, organization_id: organization_id, adder_type: :external_team).pluck(:user_id).uniq
    end
  end

  # Returns whether the given user currently has enterprise team membership to the organization
  sig do
    params(
      user: User,
      organization_id: Integer,
      ability_id: T.any(T::Array[Integer], Integer),
      db_connection: Symbol,
    )
    .returns(T::Boolean)
  end
  def self.enterprise_team_managed?(user:, organization_id:, ability_id:, db_connection: :reading)
    return false unless user.user?

    ActiveRecord::Base.connected_to(role: db_connection) do
      where(user_id: user.id, organization_id: organization_id, adder_type: :enterprise_team, ability_id: ability_id).any?
    end
  end

  # Returns a list of user ids that currently have enterprise team membership to the organization
  sig do
    params(
      user_ids: T::Array[User],
      organization_id: Integer,
      db_connection: Symbol,
    )
    .returns(T::Array[Integer])
  end
  def self.enterprise_team_managed_user_ids(user_ids:, organization_id:, db_connection: :reading)
    return [] unless user_ids.any?

    ActiveRecord::Base.connected_to(role: db_connection) do
      where(user_id: user_ids, organization_id: organization_id, adder_type: :enterprise_team).pluck(:user_id).uniq
    end
  end

  # Returns whether the given user currently has any membership to the organization
  sig do
    params(
      user: User,
      organization_id: Integer,
      ability_id: T.any(T::Array[Integer], Integer),
      db_connection: Symbol,
    )
    .returns(T::Boolean)
  end
  def self.any?(user:, organization_id:, ability_id:, db_connection: :reading)
    return false unless user.user?

    ActiveRecord::Base.connected_to(role: db_connection) do
      where(user_id: user.id, organization_id: organization_id, ability_id: ability_id).any?
    end
  end

  # Returns an array of user_ids that have any membership to the organization
  sig do
    params(
      user_ids: T::Array[User],
      organization_id: Integer,
      db_connection: Symbol,
    )
    .returns(T::Array[Integer])
  end
  def self.any_user_ids(user_ids:, organization_id:, db_connection: :reading)
    return [] unless user_ids.any?

    ActiveRecord::Base.connected_to(role: db_connection) do
      where(user_id: user_ids, organization_id: organization_id).pluck(:user_id)
    end
  end

  sig { params(organization_id: T.nilable(Integer)).returns(T::Boolean) }
  def self.enterprise_team_enabled?(organization_id)
    organization = Organization.find_by(id: organization_id)
    !!(organization && EnterpriseTeam.enabled_for_organizations?(business: organization.business))
  end
end
