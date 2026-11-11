# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class UserNamespaceRepositoriesFilter < Platform::Enums::Base
      description "Filters user namespace repositories based on status."
      visibility :internal

      value "DELETED", "Repositories that are deleted", value: :deleted
      value "ACCESSIBLE", "Repositories the viewer can access", value: :accessible
      value "ACTIVE", "Repositories that are owned by users", value: :active
    end
  end
end
