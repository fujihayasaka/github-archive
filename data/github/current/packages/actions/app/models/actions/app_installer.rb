# typed: true
# frozen_string_literal: true

# Actions App specific functionality for repositories
class Actions::AppInstaller
  extend T::Helpers
  extend ActiveSupport::Concern

  class InstallationError < StandardError
    attr_reader :reason
    def initialize(message, reason = nil)
      @reason = reason
      super(message)
    end
  end

  sig { params(repo: Repositories::IRepository).void }
  def initialize(repo)
    @repo = repo
    @repo_owner = T.must(repo.owner)
  end

  sig { returns(Repositories::IRepository) }
  attr_reader :repo

  sig { returns(Users::IUser) }
  attr_reader :repo_owner

  def enable_actions_app(actor: nil, entry_point:)
    installer = app_installer(actor)
    performed_automatically = automatic_installation?(actor)

    owner_installation = GitHub.launch_github_app.installations_on(repo_owner).first

    result = if owner_installation.present?
      IntegrationInstallation::Editor.append(
        owner_installation,
        repositories: [T.cast(repo, Repository)], # rubocop:todo GitHub/AvoidCast
        editor: installer,
        performed_automatically: performed_automatically,
        entry_point: entry_point,
      )
    else
      trigger_id = performed_automatically ? automatic_installation_trigger_id : nil
      GitHub.launch_github_app.install_on(
        repo_owner,
        repositories: [T.cast(repo, Repository)], # rubocop:todo GitHub/AvoidCast
        installer: installer,
        trigger_id: trigger_id,
        entry_point: entry_point
      )
    end

    # rubocop:todo GitHub/AvoidCast
    T.cast(repo, Repository).persist_existing_workflows(disable_scheduled_workflows_on_fork: true)
    # rubocop:enable GitHub/AvoidCast
    result
  end

  private

  def automatic_installation?(actor)
    # To prevent the wrong user from showing up in audit logs, we should treat
    # all installations as automatic unless there's a valid actor who can install the app
    actor.nil? || !T.cast(repo_owner, User).adminable_by?(actor)
  end

  def app_installer(actor)
    automatic_installation?(actor) ? default_installer : actor
  end

  def default_installer
    # REF https://github.com/github/github/pull/124773#discussion_r326824344
    owner = T.cast(repo_owner, User)
    owner.organization? ? owner.admins.first : owner
  end

  def automatic_installation_trigger_id
    trigger = IntegrationInstallTrigger.latest(integration: GitHub.launch_github_app, install_type: :actions_automatic_installation)
    return nil unless trigger.present?

    trigger.id
  end
end
