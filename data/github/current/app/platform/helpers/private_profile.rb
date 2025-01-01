# typed: false
# frozen_string_literal: true

module Platform::Helpers::PrivateProfile
  extend ActiveSupport::Concern

  def private_profile_boolean
    return false if private_profile_graphql_enabled? && object.private_profile_for?(context[:viewer])
    yield
  end

  class_methods do
    def private_profile_collection(klass)
      private_profile_field(klass, Platform::ArrayWrapper.new([]))
    end

    def private_profile_field(klass, fallback = nil)
      subclass = Class.new(klass) do
        def resolve(**args)
          if object.is_a?(::User) && object.private_profile_for?(context[:viewer]) && private_profile_graphql_enabled?
            return _get_fallback_value
          end
          super
        end

        private

        def private_profile_graphql_enabled?
          GitHub.flipper[:private_profile_graphql].enabled? ||
          GitHub.flipper[:private_profile_graphql].enabled?(context[:viewer])
        end
      end

      subclass.define_method(:_get_fallback_value) { fallback }

      subclass
    end
  end

  private

  def private_profile_graphql_enabled?
    GitHub.flipper[:private_profile_graphql].enabled? ||
    GitHub.flipper[:private_profile_graphql].enabled?(context[:viewer])
  end
end
