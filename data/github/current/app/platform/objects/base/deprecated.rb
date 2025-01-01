# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module Deprecated
        include Kernel

        class InvalidDeprecationError < ArgumentError; end

        def initialize(*args, deprecated: nil, **kwargs, &block)
          super(*T.unsafe(args), **T.unsafe(kwargs), &block)

          # Do this _after_ `super` so that `@deprecation_reason` isn't overridden
          if deprecated
            self.deprecated(**deprecated)
          end
        end

        attr_reader :upcoming_change

        # Public: Used to deprecate a GraphQL schema member
        #
        # schema_member - The schema item (field, object, mutation, etc) being
        #                 targeted.
        #
        # reason        - The reason why this field is being deprecated.
        #
        # start_date    - The date on which this field will be / was deprecated.
        #
        # superseded_by - A string describing an alternative
        #                 to the deprecated member.
        #
        # Examples
        #
        #   deprecated(
        #     start_date: Date.new(2018, 1, 15),
        #     reason: "We do not use databaseID anymore.",
        #     superseded_by: "Use `Node.id` instead.",
        #   )
        #
        # This would then generate the following IDL for deprecatable members:
        #
        #   databaseId: ID! @deprecated(reason: "`databaseID` will be removed. Use `Node.id` instead. Removal on 2017-07-01 UTC.")
        #
        def deprecated(**kwargs)
          if is_a?(Platform::Objects::Base::Argument) && type.non_null?
            message = "Cannot deprecate a required argument. Start by making the change to an optional argument. " +
              "If its not possible, you may have to deprecate the whole field."
            raise InvalidDeprecationError, message # rubocop:disable GitHub/UsePlatformErrors
          end

          unless reason = kwargs[:reason]
            raise Platform::Errors::Schema, "[#{self.graphql_name}] You must provide a `reason` when" \
              " deprecating a schema member. More info: docs_url"
          end

          if start_date = kwargs[:start_date]
            if !(start_date.is_a?(Date) || start_date.is_a?(DateTime))
              raise Platform::Errors::Schema, "[#{self.graphql_name}] Argument `start_date` must be a valid `Date` or `DateTime` object."
            end
          else
            raise Platform::Errors::Schema, "[#{self.graphql_name}] You must provide `start_date`, the day on which you" \
              " deprecate this field. More info: docs_url"
          end

          if !kwargs.key?(:superseded_by)
            raise Platform::Errors::Schema, "[#{self.graphql_name}] Must provide an alternative to the deprecated member" \
               " using `superseded_by`. Use explicit `nil` to ignore."
          else
            superseded_by = kwargs[:superseded_by]
          end

          if !kwargs.key?(:owner)
            raise Platform::Errors::Schema, "[#{self.graphql_name}] Must provide an owner for a GraphQL deprecation."
          else
            owner = kwargs[:owner]
          end

          url = kwargs[:url]

          if override_sunset_date = kwargs[:override_sunset_date]
            if !(override_sunset_date.is_a?(Date) || override_sunset_date.is_a?(DateTime))
              raise Platform::Errors::Schema, "[#{self.graphql_name}] Argument `override_sunset_date` must be a valid `Date` or `DateTime` object."
            end
          end

          # Build the change object describing the upcoming removal
          # of this deprecated member
          @upcoming_change = Platform::Evolution::Change.build_removal_change(
            self,
            added_on: start_date,
            reason: reason,
            superseded_by: superseded_by,
            owner: owner,
            override_sunset_date: override_sunset_date,
          )

          if self.is_a?(GraphQL::Schema::Argument)
            # If the member can't be deprecated per the spec,
            # simply add the upcoming change description
            # to the IDL description.
            self.description = [
              self.description,
              @upcoming_change.idl_description,
            ].compact.join("\n\n")
          elsif self.is_a?(GraphQL::Schema::Field) || self.is_a?(GraphQL::Schema::EnumValue)
            # If the member can be deprecated, add the deprecated directive
            self.deprecation_reason = [
              @upcoming_change.reason,
              superseded_by,
              "Removal on #{@upcoming_change.apply_on.strftime("%F UTC")}.",
            ].compact.join(" ")
          else
            raise Platform::Errors::Schema, "[#{self.graphql_name}] Cannot deprecate a `#{self.name}`. " \
              "If you do have a use case to deprecate it, come talk to us in #graphql."
          end
        end
      end
    end
  end
end
