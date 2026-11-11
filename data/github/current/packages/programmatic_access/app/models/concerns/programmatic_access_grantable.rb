# typed: true
# frozen_string_literal: true

module ProgrammaticAccessGrantable
  extend ActiveSupport::Concern

  include Ability::Actor
  include BotHydratable
  include ProgrammaticActor::PermissionGrantable

  GrantableTypes = T.type_alias do
    T.any(
      OrganizationProgrammaticAccessGrant,
      OrganizationProgrammaticAccessGrantRequest,
      UserProgrammaticAccessGrant,
      UserProgrammaticAccessGrantRequest
    )
  end

  included do
    T.bind(self, T.class_of(ActiveRecord::Base))
    scope :with_bot, ->(ids: []) { includes(user_programmatic_access: [:bot]).where(id: ids) }
  end

  def ability_delegate_owner
    T.bind(self, GrantableTypes)
    user_programmatic_access
  end

  def approvable_by?(actor)
    false
  end

  def writable_by?(actor)
    @writable_results = {} unless defined?(@writable_results)
    return @writable_results[actor] if @writable_results.key?(actor)

    T.bind(self, GrantableTypes)

    @writable_results[actor] =
      case target
      when Organization
        target&.resources.organization_personal_access_tokens.writable_by?(actor)
      else
        false
      end
  end

  def permissions_of_type(resource_type)
    "#{resource_type}::Resources".constantize.public_send(:filter, self.permissions)
  end

  def repository_selection
    return "all" if installed_on_all_repositories?
    permissions_of_type(Repository).any? ? "subset" : "none"
  end

  def target_for_conditional_access
    T.bind(self, GrantableTypes)

    self.target
  end
end
