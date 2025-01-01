# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      field_class Objects::Base::Field
      extend Platform::Helpers::Url
      include Platform::Objects::Base::MapToService
      extend Platform::Objects::Base::FeatureFlag
      extend Platform::Objects::Base::RequiredCapabilities
      extend Platform::Objects::Base::Scopes
      extend Platform::Objects::Base::SiteAdminCheck
      extend Platform::Objects::Base::Visibility
      extend Platform::Objects::Base::LimitActorsTo
      extend Platform::Objects::Base::ClassBasedEdgeType
      extend Platform::Objects::Base::FieldShortcuts
      extend Platform::Objects::Base::Node
      include Platform::Helpers::Enterprise

      def self.inherited(child_cls)
        # Setup a type-specific error so that needles can be properly identified
        child_cls.const_set(:ViewerMayNotSee, Class.new(Platform::Errors::ViewerMayNotSee))
        super
      end

      def self.visible?(context)
        visibility_from_context(context)
      end

      # Figure out, for this GraphQL type, is this Ruby `object` allowed in this `context`?
      def self.authorized?(object, context)
        context[:permission].check_actor_limiter(self, context)

        # since the checks will occur inside promises, grab the current GraphQL path now
        current_path = context.namespace(:interpreter)[:current_path]
        # grab the current field to find service catalog
        current_field = context.namespace(:interpreter)[:current_field]
        context[:permission].typed_can_access?(self, object).then do |accessible|
          if accessible
            context[:permission].typed_can_see?(self, object).then do |can_read_result|
              if can_read_result
                true
              else
                error = self::ViewerMayNotSee.new(object, self, context, current_path, current_field)
                fail_softer = GitHub.flipper[:graphql_fail_softer_viewer_may_not_see].enabled?

                GitHub.dogstats.increment("graphql.viewer_may_not_see", tags: ["operation:#{error.operation_name}", "type:#{self.name}", "fail_softer:#{fail_softer}"])

                if fail_softer
                  # Raising an internal execution error will allow for a partial response
                  error.set_backtrace(caller(0))
                  raise Platform::Errors::InternalExecution, error
                else
                  raise error # rubocop:disable GitHub/UsePlatformErrors
                end
              end
            end
          else
            false
          end
        end
      end

      def self.async_viewer_can_see?(permission, object)
        # rubocop:disable GitHub/UsePlatformErrors
        raise NotImplementedError, <<~MSG
          `#{self}.async_viewer_can_see?` should be implemented to check if
          the current viewer (#{permission.viewer.inspect}) may see
          this object (#{object.inspect}).

          (GraphQL type: #{graphql_name})
        MSG
        # rubocop:enable GitHub/UsePlatformErrors
      end

      sig do
        params(
          args: T.untyped,
          kwargs: T.untyped,
          block: T.nilable(T.proc.bind(Platform::Objects::Base::Field).params(arg0: Platform::Objects::Base::Field).void)
        ).returns(Platform::Objects::Base::Field)
      end
      def self.field(*args, **kwargs, &block)
        if mutation = kwargs[:mutation]
          kwargs[:feature_flag] = mutation.feature_flag
        end

        super
      end

      def self.model_name(model_class_name = nil)
        if model_class_name
          @model_name = model_class_name
        elsif defined?(@model_name)
          @model_name
        else
          @model_name = self.name.split("::").last
        end
      end

      # Returns type name extracted from the class name egz. `Platform::Objects::Issue` -> `Issue`
      def self.type_name
        class_name = self.name
        if i = class_name.rindex("::")
          class_name[(i + 2)..-1]
        else
          class_name
        end
      end

      # Currently this is defaulting to the same behavior as the legacy
      # id lookup.  In the future, this method needs to be modified
      # to  look up objects based on the ownership information in
      # the passed in GlobalID.
      def self.load_from_next_global_id(parsed_id)
        load_from_global_id(parsed_id.id)
      end

      def self.load_from_global_id(id)
        model_class = model_name.constantize
        Platform::Objects.async_find_record_by_id(model_class, id).then do |object|
          if object.respond_to?(:platform_type_name=)
            object.platform_type_name = self.type_name
          end
          object
        end
      end

      def self.public?
        visibility.any? { |v| v == :public }
      end

      def self.allow_legacy_global_id_implementation
        @allow_legacy_global_id_implementation = true
      end

      def self.allow_legacy_global_id_implementation?
        !!@allow_legacy_global_id_implementation
      end

      def self.implements(*new_interfaces, **options)
        if !called_from_implements_node? && !allow_legacy_global_id_implementation? && public? && new_interfaces.any? { |i| i == Platform::Interfaces::Node }
          raise ArgumentError, (<<~MSG) # rubocop:disable GitHub/UsePlatformErrors
          Cannot call implement Platform::Interfaces::Node directly on #{self.name}.

          Use `implements_node` instead.
          MSG
        else
          super
        end
      end
    end
  end
end
