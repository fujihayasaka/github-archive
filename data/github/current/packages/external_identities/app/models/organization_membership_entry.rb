# typed: true
# frozen_string_literal: true

class OrganizationMembershipEntry < ApplicationRecord::Domain::Users
  include GitHub::BatchedScope

  enum :adder_type, { admin: 0, external_team: 1, enterprise_team: 2 }

  belongs_to :user
  belongs_to :organization
  validates :user_id, presence: true
  validates :organization_id, presence: true
  validates :adder_id, presence: true
  validates :adder_type, presence: true, inclusion: { in: adder_types.keys }
  validates :ability_id, presence: true

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

  def self.bulk_create_entry(abilities:,  organization_id:, adder_id:, derived:, adder_type: :admin)
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

  def self.remove_entry(user:, organization_id:, ability_id:, derived:, adder_id: nil, adder_type: :admin)
    return unless user.user?

    if enterprise_team_enabled?(organization_id)
      if adder_type == :admin
        entries = where(user_id: user.id, organization_id: organization_id, adder_type: adder_type, ability_id: ability_id)
        with_write { entries.delete_all }
      else
        return if adder_id.nil?
        entries = where(user_id: user.id, organization_id: organization_id, adder_id: adder_id, adder_type: adder_type, ability_id: ability_id)
        with_write { entries.delete_all }
      end
    else
      return if derived && adder_id.nil?
      if !derived
        entries = where(user_id: user.id, organization_id: organization_id, adder_type: :admin, ability_id: ability_id)
        with_write { entries.delete_all }
      else
        entries = where(user_id: user.id, organization_id: organization_id, adder_id: adder_id, adder_type: :external_team, ability_id: ability_id)
        with_write { entries.delete_all }
      end
    end
  end

  # Returns whether the given user currently has explicit membership to the organization
  def self.explicit?(user:, organization_id:, ability_id:, db_connection: :reading)
    return false unless user.user?

    ActiveRecord::Base.connected_to(role: db_connection) do
      where(user_id: user.id, organization_id: organization_id, adder_type: :admin, ability_id: ability_id).any?
    end
  end

  # Returns whether the given user currently has derived membership to the organization
  def self.derived?(user:, organization_id:, ability_id:, db_connection: :reading)
    return false unless user.user?

    ActiveRecord::Base.connected_to(role: db_connection) do
      where(user_id: user.id, organization_id: organization_id, adder_type: :external_team, ability_id: ability_id).any?
    end
  end

  # Returns whether the given user currently has enterprise team membership to the organization
  def self.enterprise_team_managed?(user:, organization_id:, ability_id:, db_connection: :reading)
    return false unless user.user?

    ActiveRecord::Base.connected_to(role: db_connection) do
      where(user_id: user.id, organization_id: organization_id, adder_type: :enterprise_team, ability_id: ability_id).any?
    end
  end

  # Returns whether the given user currently has any membership to the organization
  def self.any?(user:, organization_id:, ability_id:, db_connection: :reading)
    return false unless user.user?

    ActiveRecord::Base.connected_to(role: db_connection) do
      where(user_id: user.id, organization_id: organization_id, ability_id: ability_id).any?
    end
  end

  sig { params(organization_id: T.nilable(Integer)).returns(T::Boolean) }
  def self.enterprise_team_enabled?(organization_id)
    organization = Organization.find_by(id: organization_id)
    !!(organization && EnterpriseTeam.enabled_for_organizations?(business: organization.business))
  end
end
