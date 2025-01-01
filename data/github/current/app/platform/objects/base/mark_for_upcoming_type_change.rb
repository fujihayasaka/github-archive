# typed: false
# frozen_string_literal: true
module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module MarkForUpcomingTypeChange
        def initialize(*args, mark_for_upcoming_type_change: nil, **kwargs, &block)
          super(*args, **kwargs, &block)
          if mark_for_upcoming_type_change
            self.mark_for_upcoming_type_change(**mark_for_upcoming_type_change)
          end
        end

        # Used to change the type of a GraphQL field or argument
        #
        # reason        - The reason why this type is being changed.
        #
        # start_date    - The date on which you're deciding to change this schema member
        #
        # new_type      - GraphQL Schema IDL describing the new type for this member
        #               - Example: `String!`
        #
        # Examples
        #
        #   mark_for_upcoming_type_change(
        #     start_date: Date.new(2018, 1, 15),
        #     reason: "This field may return null values",
        #     new_type: "Commit",
        #   )
        #
        # This would then generate the following IDL for deprecatable members:
        #
        #   # **Upcoming Change on 2017-07-01**
        #   # **Description:**: Type will change from `Commit!` to `Commit`.
        #   # **Reason:** This field may return null values in certain scenarios.
        #   # commit: Commit!
        #
        def mark_for_upcoming_type_change(**kwargs)
          unless reason = kwargs[:reason]
            raise Platform::Errors::Schema, "[#{self.graphql_name}] You must provide a `reason` when" \
              " changing a schema member."
          end

          if start_date = kwargs[:start_date]
            if !(start_date.is_a?(Date) || start_date.is_a?(DateTime))
              raise Platform::Errors::Schema, "[#{self.graphql_name}] Argument `start_date` must be a valid `Date` or `DateTime` object."
            end
          else
            raise Platform::Errors::Schema, "[#{self.graphql_name}] You must provide `start_date`, the day on which you" \
              " mark this member for change."
          end

          if !kwargs.key?(:new_type)
            raise Platform::Errors::Schema, "[#{self.graphql_name}] Must provide a new type for type changes."
          else
            new_type = kwargs[:new_type]
          end

          if !kwargs.key?(:owner)
            raise Platform::Errors::Schema, "[#{self.graphql_name}] Must provide an owner for a GraphQL deprecation."
          else
            owner = kwargs[:owner]
          end

          change = Platform::Evolution::Change.build_type_change(
            self,
            new_type: new_type,
            added_on: start_date,
            reason: reason,
            owner: owner,
          )

          self.description = [
            self.description,
            change.idl_description,
          ].compact.join("\n\n")

          @upcoming_change = change
        end
      end
    end
  end
end
