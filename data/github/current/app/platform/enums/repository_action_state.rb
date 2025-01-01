# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryActionState < Platform::Enums::Base
      description "The possible states of a repository action"
      visibility :internal

      value "LISTED", "An action listed in the Marketplace.", value: :listed
      value "UNLISTED", "An action that has not been listed in the Marketplace.", value: :unlisted
      value "DELISTED", "An action that was delisted from the Marketplace.", value: :delisted
    end
  end
end
