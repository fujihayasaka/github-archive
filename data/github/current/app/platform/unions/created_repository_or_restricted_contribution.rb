# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class CreatedRepositoryOrRestrictedContribution < Platform::Unions::Base
      docs_category :users

      description "Represents either a repository the viewer can access or a restricted contribution."

      possible_types Objects::CreatedRepositoryContribution, Objects::RestrictedContribution
    end
  end
end
