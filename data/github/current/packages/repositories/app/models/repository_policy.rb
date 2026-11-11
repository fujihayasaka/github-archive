# typed: true
# frozen_string_literal: true

# Abstract base class for various repository policies.
class RepositoryPolicy
  attr_reader :repository

  # Public
  def satisfied?
    raise NotImplementedError
  end

  # Public
  def violated?
    !satisfied?
  end

  # Internal: Return the user or organization that sets the policies for the
  # repository.
  #
  # Returns a User or Organization.
  def policymaker
    repository.policymaker
  end
end
