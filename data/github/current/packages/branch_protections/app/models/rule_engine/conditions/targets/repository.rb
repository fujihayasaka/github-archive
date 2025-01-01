# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    # Helper to create a targetable object for a Repository
    # Long-term, it may make sense to have Repository implement Targetable directly if we choose to use
    # Targetable as a universal interface for all targetable objects
    class Targets::Repository

      include Targetable

      sig { params(repository: Repository, repo_create_custom_properties: T.nilable(T::Hash[String, T.untyped])).void }
      def initialize(repository:, repo_create_custom_properties: nil)
        @repository = repository
        @repo_create_custom_properties = repo_create_custom_properties
      end

      sig { override.returns(T::Hash[RuleEngine::Conditions::Targetable::Attribute, T.untyped]) }
      def targetable_attributes
        {
          Attribute::Repository => @repository,
          Attribute::RepositoryCreateCustomProperties => @repo_create_custom_properties,
        }
      end

      sig { override.returns(Promise[T.nilable(RuleEngine::Conditions::Targetable)]) }
      def async_targetable_parent
        @repository.async_owner.then do |owner|
          next nil if owner.nil?
          if owner.is_a?(Organization)
            Targets::Organization.new(organization: owner)
          else
            Targets::User.new(user: owner)
          end
        end
      end
    end
  end
end
