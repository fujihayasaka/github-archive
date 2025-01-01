# typed: true
# frozen_string_literal: true

class ForkGroupSetting < RepositoryGroupSetting
  DENY = "deny".freeze
  EXTERNAL = "external".freeze
  INTERNAL = "internal".freeze
  USERS = "users".freeze

  def populate_attributes
    self.value ||= { "#{DENY}": [] }
    self.inherited ||= {}
    self.composite ||= {}
  end

  def allow_all
    value[DENY] = []
  end

  def deny_all
    value[DENY] |= %w[EXTERNAL INTERNAL USERS]
  end

  def deny_external
    value[DENY] |= [EXTERNAL]
  end

  def deny_internal
    value[DENY] |= [INTERNAL]
  end

  def deny_users
    value[DENY] |= [USERS]
  end

  def allow_all?
    composite[DENY]&.empty?
  end

  def deny_all?
    deny_external? && deny_internal? && deny_users?
  end

  def deny_any?
    value[DENY].any?
  end

  def deny_external?
    composite[DENY]&.include?(EXTERNAL)
  end

  def deny_internal?
    composite[DENY]&.include?(INTERNAL)
  end

  def deny_users?
    composite[DENY]&.include?(USERS)
  end

  def apply(actor:, repository:)
    # regardless of the higher level setting, this repository is managed by a group setting now,
    # so we should make sure the repo-level fork setting is enabled
    repository.clear_private_repository_forking_setting(actor: actor)
  end
end
