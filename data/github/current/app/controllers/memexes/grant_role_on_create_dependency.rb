# typed: strict
# frozen_string_literal: true
module Memexes
  # This module ensures that any controller which includes this module must define a
  # `grant_role_on_create` method which grants the requisite permissions to an actor
  # upon creating a memex project. For example, granting admin permissions to the user
  # who initially creates an organization project.
  module GrantRoleOnCreateDependency
    extend T::Helpers
    extend T::Sig
    interface!

    # Grants the requisite permissions to an actor upon creating a memex project.
    #
    # memex - the newly created MemexProject model.
    #
    # Returns: true if the role was successfully granted, false otherwise.
    sig { abstract.params(memex: MemexProject).returns(T::Boolean) }
    def grant_role_on_create(memex); end
  end
end
