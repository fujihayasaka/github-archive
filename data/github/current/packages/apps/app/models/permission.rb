# typed: true
# frozen_string_literal: true

# This intended use of this model is for
# lib/github/transitions/20190114134045_migrate_github_app_back_to_mysql1.rb
#
# Please do not use this anywhere else unless you chat with
# the @github/ecosystem-apps team.
#
# Thanks!
class Permission < ApplicationRecord::Permissions
  FGP_ACTORS = %w[
    IntegrationInstallation
    OauthAuthorization
    OrganizationProgrammaticAccessGrant
    OrganizationProgrammaticAccessGrantRequest
    ScopedIntegrationInstallation
    SiteScopedIntegrationInstallation
    User
    UserProgrammaticAccessGrant
    UserProgrammaticAccessGrantRequest
  ].freeze

  ACTION_RANKING = {
    read: 0,
    write: 1,
    admin: 2
  }

  # NOTE: Update Permission::Action if we add new actions.
  enum :action, { read: 0, write: 1, admin: 2 }
  enum :priority, { indirect: 0, direct: 1 }

  validates :actor_id, presence: true
  validates :actor_type, presence: true, inclusion: { in: FGP_ACTORS }
  validates :action, presence: true
  validates :subject_id, presence: true
  validates :subject_type, presence: true

  belongs_to :actor,   polymorphic: true
  belongs_to :subject, polymorphic: true

  alias_method :original_subject, :subject

  attribute :expires_at, :utc_timestamp

  def subject
    return self.original_subject unless FGP_ACTORS.include?(actor_type)

    ability_prefix = T.must(subject_type.split("/")[0..-2]).join("/")
    resource       = subject_type.split("/").last

    case ability_prefix
    when Repository::Resources::INDIVIDUAL_ABILITY_TYPE_PREFIX
      Repositories::Public.find_active!(subject_id).resources.public_send(resource)
    when Repository::Resources::ALL_ABILITY_TYPE_PREFIX
      # This will work for both users and orgs because of STI
      User.find(subject_id).repository_resources.public_send(resource)
    when Organization::Resources::ABILITY_TYPE_PREFIX, User::Resources::ABILITY_TYPE_PREFIX
      # This will work for both users and orgs because of STI
      User.find(subject_id).resources.public_send(resource)
    when ProtectedBranch::Resources::ABILITY_TYPE_PREFIX
      ProtectedBranch.find(subject_id).resources.public_send(resource)
    when Business::Resources::ABILITY_TYPE_PREFIX
      Business.find(subject_id).resources.public_send(resource)
    end
  end
end
