# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    class RulesetTargetContext
      extend T::Sig

      include Targetable

      sig { override.returns(T.nilable(Repository)) }
      attr_reader :repository

      sig do
        params(
          repository: T.nilable(Repository),
          organization: T.nilable(Organization),
          ref_update: T.nilable(Git::Ref::Update),
          ref_name: T.nilable(String)
        ).void
      end
      def initialize(repository: nil, organization: nil, ref_update: nil, ref_name: nil)
        @repository = repository
        @organization = organization
        @ref_update = ref_update
        @ref_name = ref_name
      end

      sig { override.returns(T.nilable(Organization)) }
      def organization
        return @organization if @organization
        owner = @repository&.owner
        owner if owner.is_a?(Organization)
      end

      sig { override.returns(T.nilable(String)) }
      def ref_name
        @ref_update&.refname || @ref_name
      end
    end
  end
end
