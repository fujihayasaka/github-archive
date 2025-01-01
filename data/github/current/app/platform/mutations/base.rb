# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class Base < GraphQL::Schema::RelayClassicMutation
      field_class Platform::Objects::Base::Field
      argument_class Platform::Objects::Base::Argument
      input_object_class Platform::Inputs::Base
      object_class Platform::Mutations::Base::BasePayload

      extend Platform::Objects::Base::MapToService
      extend Platform::Objects::Base::FeatureFlag
      extend Platform::Objects::Base::RequiredCapabilities
      extend Platform::Objects::Base::LimitActorsTo
      extend Platform::Objects::Base::SiteAdminCheck
      extend Platform::Objects::Base::Scopes
      extend Platform::Objects::Base::Visibility
      extend Platform::Objects::Base::ReadArgumentsFromReplicas
      extend Platform::Objects::Base::ReadMutationFieldsFromReplicas
      include Platform::Helpers::Enterprise
      include Platform::Helpers::TenantContext

      # Hook into RelayClassicMutation's wrapper around the resolve method
      # so we can skip promise/association loading requirements here
      def resolve_with_support(**kwargs)
        client_permits_replicas = context[:client_permits_replicas] || false
        context[:read_arguments_from_replicas] = self.class.read_arguments_from_replicas?(client_permits_replicas: client_permits_replicas)
        # Clear any existing loaders
        GraphQL::Batch::Executor.current.clear
        wrap_in_read_if_enforced do
          with_viewer_timezone do
            if !self.class.allow_anonymous_viewer && context[:viewer].blank? && context[:oauth_app].blank?
              raise Platform::Errors::Unauthenticated.new("The `#{self.class.graphql_name.camelize(:lower)}` mutation cannot be run anonymously.")
            end
            if context[:block_mutations]
              raise Platform::Errors::Unauthenticated.new("The #{self.class.graphql_name.camelize(:lower)} mutation is not allowed.")
            end
            Platform::Helpers::ActorLimiter.check(self.class, context)
            GraphQL::Batch::Executor.current.without_caching do
              Platform::LoaderTracker.ignore_association_loads do
                # MT mode: try to resolve the tenant through the mutation args, or explicitly unscope queries from this
                # point on if the mutation has been marked as exempt.
                # We want to do this before node loading and authorization so that we have the correct scopes to perform
                # those checks within and can fail on tenant boundary issues before getting down to the resolve method.
                set_graphql_tenant_context(kwargs[:input].to_kwargs) do
                  result = super
                  # If it's a promise or something, we want to resolve it before moving on.
                  context.schema.sync_lazy(result)
                end
              end
            end
          end
        end
      ensure
        # Make sure we remove anything that the current mutation loaded.
        GraphQL::Batch::Executor.current.clear
      end

      def self.visible?(context)
        visibility_from_context(context)
      end

      def wrap_in_read_if_enforced
        return yield unless context[:read_arguments_from_replicas]

        ActiveRecord::Base.connected_to(role: :reading) do
          yield
        end
      end

      # this method can be used to modify the arguments before they are passed to the resolve method
      # if `read_arguments_from_replicas` is enabled, this will use a reading role
      # note: any code in `before_resolve` will run synchronously before `resolve` is called
      def before_resolve(**args)
        args
      end

      # Respect the viewer's specified timezone. Ensures contributes
      # are reflected for the correct date with respect to their zone.
      def with_viewer_timezone
        old_zone = Time.zone

        Time.zone = context[:viewer].time_zone if context[:viewer]
        Time.zone ||= ActiveSupport::TimeZone["UTC"]

        yield
      ensure
        Time.zone = old_zone
      end

      # Default to allowing through requests only if the mutation is
      # `:internal` and the current request is not a GraphQL API request
      def self.async_api_can_modify?(permission, **_)
        permission.hidden_from_public?(self)
      end

      def authorized?(**object)
        type_name = self.class.name.try(:demodulize)

        mutation_permission_object = context[:permission].dup
        mutation_permission_object.mutation = true
        mutation_permission_object.freeze

        auth_check = self.class.async_api_can_modify?(mutation_permission_object, **object)
        GitHub.dogstats.time("platform.authorization.can_modify.time", tags: ["type_name:#{type_name}"]) do
          Promise.resolve(auth_check).then do |accessible|
            if accessible == false
              raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have the correct permissions to execute `#{type_name}`")
            elsif accessible == true
              true
            else
              # The resolved value was neither `true` nor `false`,
              # it might be some kind of accident
              err = Errors::Internal.new("Platform::Authorization::Permission##{type_name} resolved to an instance of #{accessible.class}, but it should resolve to `true` or `false`.")
              if Rails.env.production?
                Failbot.report(err)
                false
              else
                raise err # rubocop:disable GitHub/UsePlatformErrors
              end
            end
          end
        end
      end

      # Override GraphQL-Ruby's built-in error to raise one like our other NotFound errors
      def load_application_object_failed(err)
        uuid = err.id
        loaded_type = @arguments_by_keyword[err.argument.keyword]&.loads&.graphql_name
        raise Errors::NotFound, "Could not resolve to #{loaded_type} node with the global id of '#{uuid}'."
      end

      class << self
        if Rails.env.test?
          # The override in Objects::Base::FeatureFlag doesn't work here
          def feature_flag=(new_flag)
            payload_type.feature_flag = new_flag
            input_type.feature_flag = new_flag
            @feature_flag = new_flag
          end
        end
      end

      def self.allow_anonymous_viewer(setting = nil)
        if !setting.nil?
          @allow_anonymous_viewer = setting
        end
        @allow_anonymous_viewer
      end

      def self.error_fields
        # When this method is called on a subclass,
        # add a module that wraps its `#resolve` method with error path checking
        self.prepend(Platform::UserErrors::VerifyPathAfterResolve)
        # Add add a field to expose user errors
        field :errors,
          [Platform::Interfaces::UserError],
          null: false,
          visibility: :under_development,
          description: "If this mutation fails due to invalid inputs, errors will show up in this list."
      end

      # RelayClassicMutation.arguments returns the arguments of the input object;
      # This is equivalent to the arguments of the derived field
      def self.real_arguments
        @real_arguments ||= {
          "input" => Platform::Objects::Base::Argument.new(name: :input, type: input_type, required: true, owner: self),
        }
      end
    end
  end
end
