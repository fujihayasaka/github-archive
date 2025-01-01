# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      class Field < GraphQL::Schema::Field
        module ManualConnectionArguments
          # A helper for cases when we use `connection: false`
          # to bypass GraphQL-Ruby's built-in connection wrappers
          def has_connection_arguments
            # This matches https://github.com/rmosolgo/graphql-ruby/blob/1.9-dev/lib/graphql/schema/field/connection_extension.rb
            argument :after, "String", "Returns the elements in the list that come after the specified cursor.", required: false
            argument :before, "String", "Returns the elements in the list that come before the specified cursor.", required: false
            argument :first, "Int", "Returns the first _n_ elements from the list.", required: false
            argument :last, "Int", "Returns the last _n_ elements from the list.", required: false
          end
        end
        include ManualConnectionArguments
        include Platform::Objects::Base::Deprecated
        include Platform::Objects::Base::MarkForUpcomingTypeChange
        include Platform::Objects::Base::MapToService
        include Platform::Objects::Base::Visibility

        argument_class Platform::Objects::Base::Argument

        # In local environments, make sure AR::Relations have been filtered for spam and disabled repositories
        if Rails.env.test? || Rails.env.development?
          prepend(Platform::SpamFilterCheck::ResolveWrapper)
          prepend(Platform::DisabledRepositoryFilterCheck::ResolveWrapper)
        end

        def initialize(map_to_service: nil, **kwargs, &block)
          @edge_class = kwargs.delete(:edge_class)
          @numeric_pagination_enabled = kwargs.delete(:numeric_pagination_enabled)
          @minimum_accepted_scopes = kwargs.delete(:minimum_accepted_scopes)
          @feature_flag = kwargs.delete(:feature_flag)
          @mobile_only = kwargs.delete(:mobile_only)
          @required_capabilities = kwargs.delete(:required_capabilities)
          @exempt_from_spam_filter_check = kwargs.delete(:exempt_from_spam_filter_check)
          visibility_from_config(kwargs.delete(:visibility))

          super(**kwargs, &block)

          if map_to_service
            @default_service_mapping = map_to_service
          end

          # Capitalize HTML as an acronym
          if kwargs[:name].to_s =~ /_html/
            @name = @name.sub("Html", "HTML")
          end

          if @numeric_pagination_enabled
            argument(:numeric_page, Integer, required: false,
              description: "Paginate by numeric page for API v3",
              visibility: :internal
            )
          end

          extension(GraphQlGracefulDegradationExtension)

          if connection?
            pagination_extension = CheckPaginationExtension.new(field: self, options: nil)
            # Insert this _before_ the connection tooling, so that we have access to pagination args
            @extensions.insert(1, pagination_extension)
          end
        end

        def visible?(context)
          return false unless super
          visibility_from_context(context)
        end

        # A GraphQL field gets is service mapping from either:
        # - An explicitly-given `map_to_service:` configuration
        # - Inherited from the resolver (or mutation) that implements this field
        # - Inherited from the object that this field is defined on
        def service_mapping(serviceowners: nil)
          if defined?(@default_service_mapping)
            @default_service_mapping
          else
            @default_service_mapping = if resolver && (resolver_service = resolver.service_mapping(serviceowners: serviceowners))
              resolver_service
            elsif owner && (owner_service = owner.service_mapping(serviceowners: serviceowners))
              # `owner` is always present for real GraphQL-Ruby schemas, but we have some tests that make fields manually
              owner_service
            else
              # Fields don't have their own files, no need to call `super` to check SERVICEOWNERS
              nil
            end
          end
        end

        # @return [nil, Array<String>] If present, the required OAuth scopes for accessing this field
        attr_reader :minimum_accepted_scopes

        # @return [nil, Symbol] If present, an HTTP header which must be present to access this field
        attr_accessor :feature_flag

        # @return [nil, Symbol] If present, an HTTP header which must be present to access this field
        attr_accessor :mobile_only

        attr_accessor :required_capabilities

        # @return [nil, true] If true, this field's ActiveRecord::Relation's _won't_ be checked in test/development
        #  to see whether or not they have spam filtering applied. (Use this for lists which _should_ include spammy items.)
        attr_reader :exempt_from_spam_filter_check
      end
    end
  end
end
