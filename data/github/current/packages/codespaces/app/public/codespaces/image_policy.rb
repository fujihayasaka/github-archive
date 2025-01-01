# typed: strict
# frozen_string_literal: true

module Codespaces
  module ImagePolicy
    extend T::Sig
    extend PolicyFilter

    sig { params(image_name: T.nilable(String), billable_owner: T.nilable(User), repository: T.nilable(Repository)).returns(T::Boolean) }
    def self.image_allowed?(image_name:, billable_owner:, repository:)
      return true unless image_name && billable_owner && repository

      value_allowed?(
        value_name: image_name,
        billable_owner: billable_owner,
        repository: repository,
      )
    end

    sig { override.returns(String) }
    def self.policy_name
      Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES
    end
  end
end
