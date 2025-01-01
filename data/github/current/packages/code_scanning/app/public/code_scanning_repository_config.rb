# typed: strict
# frozen_string_literal: true

class CodeScanningRepositoryConfig
  include Configurable
  include Configurable::CodeScanning
  include Configurable::CodeScanningAutofix

  sig { returns(Repositories::IRepository) }
  attr_reader :repository

  sig { params(repository: Repositories::IRepository).void }
  def initialize(repository)
    @repository = repository
  end

  # Configurables are currently stored associated with a repository
  sig { returns(String) }
  def configuration_entry_type
    "Repository"
  end

  sig { returns(::ActiveRecord::Relation) }
  def configuration_entries
    ::Configuration::Entry.where(target_id: repository.id, target_type: "Repository")
  end

  # Override to avoid base `configuration_entry_id` from requiring `ApplicationRecord::Base` ancestry
  sig { returns(Integer) }
  def configuration_entry_id
    T.must(repository.id)
  end

  # Internal: Get the configuration owner.
  # values for a Repository can be cascaded from (or overridden by) the repo owner
  sig { returns(T.nilable(Users::IUser)) }
  def configuration_owner
    repository.owner
  end

  # Internal: Get the configuration owner asynchronously.
  # values for a Repository can be cascaded from (or overridden by) the repo owner
  sig { returns(Promise[T.nilable(Users::IUser)]) }
  def async_configuration_owner
    repository.async_owner
  end
end
