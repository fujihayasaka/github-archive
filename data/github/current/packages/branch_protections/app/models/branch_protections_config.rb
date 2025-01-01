# typed: strict
# frozen_string_literal: true

class BranchProtectionsConfig

  include BranchProtectionEvaluation::Configurable

  # BP configurables are currently stored associated with a repository
  sig { returns(String) }
  def configuration_entry_type
    "Repository"
  end

  # Override to avoid base `configuration_entry_id` from requiring `ApplicationRecord::Base` ancestry
  sig { returns(Integer) }
  def configuration_entry_id
    T.must(repository.id)
  end

  # Leverage the repository's cached config
  sig { returns(Configuration) }
  def config
    T.cast(repository, Repository).config # rubocop:todo GitHub/AvoidCast
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

  sig { returns(Repositories::IRepository) }
  attr_reader :repository

  sig { params(repository: Repositories::IRepository).void }
  def initialize(repository)
    @repository = repository
  end
end
