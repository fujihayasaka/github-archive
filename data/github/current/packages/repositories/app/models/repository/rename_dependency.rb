# typed: false
# frozen_string_literal: true

module Repository::RenameDependency
  # Add a record of this repository previously existing at a different
  # "user/repo" location. This is used to redirect requests for repositories
  # when their location changes.
  #
  # Returns a RepositoryRedirect object.
  def redirect_from_previous_location(name_with_owner)
    redirects.create(repository_name: name_with_owner)
  end

  # Destructive! Renames a repository. This only changes database state since
  # repositories are named after their id. Also adds a redirect entry for the
  # old name, regenerates public key options strings, and manages any pages
  # related tasks.
  #
  # new_name - String name.
  # actor: User object or nil (optional, defaults to actor from GitHub.context).
  #
  # Returns a Boolean indicating whether or not the rename worked.
  def rename(new_name, actor: self.actor, synchronous: false)
    begin
      orchestration = RepositoryOrchestration.rename(self, new_name:, actor:)
      unless orchestration.valid?
        unless repository.errors.any?
          self.errors.add(:name, orchestration.errors.full_messages.join(", "))
        end
        return false
      end
      orchestration.execute(synchronous: synchronous)
      return false if orchestration.skipped?

      if orchestration.failed?
        error = orchestration.error_message
        self.errors.add(:name, error) if error
        return false
      end
    rescue RenameRepositoryOrchestration::FailedRenameLockError => e
      error = e.message
      self.errors.add(:name, error) if error
      return false
    end

    true
  end

  def moving?
    locked_on_move? || network.moving?
  end

  def instrument_rename(old_name:, actor:)
    instrument :rename, old_name: old_name, actor: actor
  end
end
