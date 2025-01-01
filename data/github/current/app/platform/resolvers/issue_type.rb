# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class IssueType < Resolvers::Base
      include GitHub::ResilienceMixin
      include ::Issues::Domain::Provider

      extend T::Sig
      type Objects::IssueType, null: true

      sig { params(name: T.nilable(String), arguments: T.untyped).returns(Promise[T.nilable(Objects::IssueType)]) }
      def resolve(name: nil, **arguments)
        with_async_database_error_fallback(
          async_has_permission?.then do |has_permission|
            type_name = object.is_a?(IssueTemplate) ? object.type : name

            next nil unless has_permission && type_name.present?

            async_repository.then do |repository|
              repository.async_owner.then do |owner|
                next nil unless @context[:viewer].present? && owner.issue_types_enabled?

                next Platform::Loaders::IssueTypeByName.load(repository, type_name)
              end
            end
          end,
           fallback: -> { raise Platform::Errors::ServiceUnavailable, "Issue types are currently unavailable." }
        )
      end

      private

      sig { returns(Promise[Repository]) }
      def async_repository
        case object
        when IssueTemplate
          object.async_repository
        when Repository
          Promise.resolve(object)
        else
          raise Platform::Errors::Internal, "don't know how to fetch issue type for #{object.class}"
        end
      end

      sig { returns(Promise[T::Boolean]) }
      def async_has_permission?
        async_repository.then do |repository|
          repository.async_owner.then do |owner|
            owner.issue_types_enabled?
          end
        end
      end
    end
  end
end
