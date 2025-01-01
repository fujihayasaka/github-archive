# typed: true
# frozen_string_literal: true

module Platform
  module Subscriptions
    # A class for specific subscriptions to inherit from.
    class Base < GraphQL::Schema::Subscription
      class BasePayload < Platform::Objects::Base
        # Anyone who can run this subscription can see the payload
        def self.async_viewer_can_see?(*)
          true
        end

        def self.async_api_can_access?(*)
          true
        end
      end
      extend Platform::Objects::Base::MapToService
      extend Platform::Objects::Base::FeatureFlag
      extend Platform::Objects::Base::RequiredCapabilities
      extend Platform::Objects::Base::LimitActorsTo
      extend Platform::Objects::Base::SiteAdminCheck
      extend Platform::Objects::Base::Scopes
      extend Platform::Objects::Base::Visibility
      include Platform::Helpers::Enterprise

      object_class Platform::Subscriptions::Base::BasePayload
      field_class Platform::Objects::Base::Field
      argument_class Platform::Objects::Base::Argument

      def authorized?(**object)
        current_user = context[:viewer]
        raise Errors::Forbidden.new("Not allowed") if context[:operation_id].nil? && context[:persisted_query].nil?
        raise Errors::Forbidden.new("Not allowed") unless context[:origin] == Platform::ORIGIN_API
        raise Errors::Forbidden.new("Not allowed") if context[:viewer].blank?

        true
      end

      def stats_event_name
        self.class.name.split("::").last.underscore
      end

      def self.visible?(context)
        visibility_from_context(context)
      end
    end
  end
end
