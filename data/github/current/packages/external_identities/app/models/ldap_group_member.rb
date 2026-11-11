# typed: false
# frozen_string_literal: true

class LdapGroupMember < ApplicationRecord::Domain::Users
  include GitHub::Validations

  # the values in group_dn and member_dn are stored hashed
  # those values are populated from ldap_mapping
  belongs_to :ldap_mapping, primary_key: :dn_hash, foreign_key: :group_dn # rubocop:todo Rails/InverseOf

  validate :validate_team_mapping

  validates_presence_of :group_dn
  validates :group_dn, unicode3: true
  validates_presence_of :member_dn
  validates :member_dn, unicode3: true

  private

  def validate_team_mapping
    if !ldap_mapping || !ldap_mapping.team_mapping?
      errors.add(:ldap_mapping, "An LdapOrgMember must be associated with a 'team' LdapMapping.")
    end
  end
end
