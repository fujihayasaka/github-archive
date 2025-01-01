# typed: false
# frozen_string_literal: true
module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module Visibility
        ALL_ENVIRONMENTS = GraphQLExtensions::VisibilityForBuiltIns::ALL_ENVIRONMENTS
        DEFAULT_VISIBILITIES = GraphQLExtensions::VisibilityForBuiltIns::DEFAULT_VISIBILITIES
        DEFAULT_ENVIRONMENT_VISIBILITIES = GraphQLExtensions::VisibilityForBuiltIns::DEFAULT_ENVIRONMENT_VISIBILITIES
        UNSET_VISIBILITIES = [].freeze

        def visibility_from_context(context)
          context.present? && context[:mask].present? ? !context[:mask].call(self, context) : true
        end

        def generate_input_type
          apply_visibility_to_class(super)
        end

        def generate_payload_type
          apply_visibility_to_class(super)
        end

        def visibility(desired_visibility = nil, environments: ALL_ENVIRONMENTS)
          return if desired_visibility == []
          desired_visibility = Array(desired_visibility)

          if desired_visibility.present?
            @unset_visibilities ||= ALL_ENVIRONMENTS.dup
            @visibilities ||= {}

            environments.each do |env|
              @unset_visibilities.delete(env)
              @visibilities[env] = desired_visibility.dup

              # Anything `:public` is _also_ `:internal`;
              # `:under_develpment` is actually a synonym for `:internal`.
              # So add `:internal` in either of those cases.
              if desired_visibility.include?(:public) || desired_visibility.include?(:under_development)
                @visibilities[env] << :internal
              end

              @visibilities[env].flatten!
              @visibilities[env].uniq!
            end

            # assume that the schema member is not visible to any environment not mentioned
            # until that environment is specifically configured.
            # (A later call to `.visibility(...)` will override the `[]` assigned here.)
            other_environments = ALL_ENVIRONMENTS - environments
            other_environments.each do |env|
              @visibilities[env] ||= []
            end
          else
            # Detect the current environment and fetch the visibility or it.
            if GitHub.enterprise?
              visibility_for(:enterprise)
            else
              visibility_for(:dotcom)
            end
          end
        end

        def environment_visibilities
          @visibilities || DEFAULT_ENVIRONMENT_VISIBILITIES
        end

        def visibility_for(env)
          if @visibilities && (vis = @visibilities[env])
            if @unset_visibilities.include?(env)
              UNSET_VISIBILITIES
            else
              vis
            end
          else
            DEFAULT_VISIBILITIES
          end
        end

        def default_visibility?
          environment_visibilities == DEFAULT_ENVIRONMENT_VISIBILITIES
        end

        private

        def visibility_from_config(visibility_config)
          case visibility_config
          when nil
            # Do nothing
          when Hash
            visibility_config.each do |vis_level, options|
              visibility(vis_level, **options)
            end
          when Symbol
            visibility(visibility_config)
          else
            raise ArgumentError, "Visibility must be Symbol or Hash, not: #{visibility_config.inspect}"  # rubocop:disable GitHub/UsePlatformErrors
          end
        end

        def apply_visibility_to_class(type_class)
          if @visibilities
            @visibilities.each do |env, config|
              type_class.visibility(config, environments: [env])
            end
          end
          type_class
        end
      end
    end
  end
end
