# typed: true
# frozen_string_literal: true

# Wrapper class that applies ELM migration state configuration to a repository.
# Use this instead of including Configurable::RepositoryElmMigrationState
# directly on Repository.
#
# Usage:
#   config = ElmMigrationStateConfig.new(repository)
#   config.elm_migration_source?
#   config.set_elm_migration_state("started")
class ElmMigrationStateConfig
  include Configurable::RepositoryElmMigrationState

  sig { returns(String) }
  def configuration_entry_type
    "Repository"
  end

  sig { returns(Integer) }
  def configuration_entry_id
    T.must(repository.id)
  end

  sig { returns(Configuration) }
  def config
    T.cast(repository, Repository).config # rubocop:todo GitHub/AvoidCast
  end

  sig { returns(T.nilable(Users::IUser)) }
  def configuration_owner
    repository.owner
  end

  sig { returns(Promise[T.nilable(Users::IUser)]) }
  def async_configuration_owner
    repository.async_owner
  end

  sig { returns(Repositories::IRepository) }
  attr_reader :repository

  sig { params(repository: Repositories::IRepository).void }
  def initialize(repository)
    @repository = repository
  end
end
