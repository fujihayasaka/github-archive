# typed: true
# frozen_string_literal: true

class LicenseSourcer
  MEMBER = :member
  ADMIN = :admin
  COLLABORATOR = :collaborator
  COLLABORATOR_INVITE = :collaborator_invite
  INVITE = :invite

  class LicenseOrigin
    attr_reader :owner, :association

    def initialize(owner, association)
      @owner = owner
      @association = association
    end

    def to_s
      case association
      when LicenseSourcer::MEMBER
        "member of #{owner.login}"
      when LicenseSourcer::ADMIN
        "admin of #{owner.login}"
      when LicenseSourcer::COLLABORATOR
        "private repo collaborator on #{owner.login}"
      when LicenseSourcer::INVITE
        "invited to #{owner.login}"
      when LicenseSourcer::COLLABORATOR_INVITE
        "invited private repo collaborator on #{owner.login}"
      end
    end
  end

  def self.empty
    new
  end

  def self.members(org, values)
    new.add_values(org, values, MEMBER)
  end

  def self.collaborators(org, values)
    new.add_values(org, values, COLLABORATOR)
  end

  def self.admins(org, values)
    new.add_values(org, values, ADMIN)
  end

  def self.collaborator_invites(org, values)
    new.add_values(org, values, COLLABORATOR_INVITE)
  end

  def self.invites(org, values)
    new.add_values(org, values, INVITE)
  end

  delegate :[], :has_key?, to: :licenses

  def initialize(licenses = nil)
    @licenses = licenses || Hash.new { |hash, key| hash[key] = [] }
  end

  def +(other)
    self.class.new(
      licenses.merge(other.licenses) do |_key, oldval, newval|
        oldval + newval
      end,
    )
  end

  def -(other)
    self.class.new(
      licenses.reject { |key| other.has_key?(key) },
    )
  end

  def values
    @licenses.keys
  end

  def add_value(org, value, origin)
    @licenses[value].push LicenseOrigin.new(org, origin)
  end

  def add_values(org, values, origin)
    values.map { |value| add_value(org, value, origin) }
    self
  end

  protected

  attr_reader :licenses
end
