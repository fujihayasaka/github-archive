# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      class Argument < GraphQL::Schema::Argument
        include Platform::Objects::Base::Deprecated
        include Platform::Objects::Base::MarkForUpcomingTypeChange
        include Platform::Objects::Base::Visibility

        def initialize(*args, visibility: nil, **kwargs, &block)
          @feature_flag = kwargs.delete(:feature_flag)
          @required_capabilities = kwargs.delete(:required_capabilities)

          if kwargs.key?(:default_value) && kwargs[:required]
            raise Platform::Errors::Internal, <<~ERR
              Use `required: true` _or_ a `default_value:`, but not both.

              (A required argument will never apply a default value, so using both doesn't make sense)
            ERR
          end
          visibility_from_config(visibility)

          super(*T.unsafe(args), **T.unsafe(kwargs), &block)
        end

        def visible?(context)
          visibility_from_context(context)
        end

        # @return [nil, Symbol] If present, an HTTP header which must be present to access this field
        attr_accessor :feature_flag
        attr_accessor :required_capabilities
      end
    end
  end
end
