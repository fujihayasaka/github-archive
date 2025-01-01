# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class NotifydView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

      sig { returns(::User) }
      attr_reader :user

      sig { returns(String) }
      def page_title
        "#{user.login} - Notifyd subscriptions and routing settings"
      end

      sig { returns(T::Boolean) }
      def routing_settings_available?
        notifyd_routing_settings.routing_setting.any?
      end

      sig { returns(T::Boolean) }
      def subscriptions_available?
        notifyd_subscriptions.subscriptions.any?
      end

      sig do
        returns(
          Google::Protobuf::RepeatedField[Notifyd::Proto::Subscriptions::Subscription]
        )
      end
      def subscriptions
        notifyd_subscriptions.subscriptions
      end

      sig do
        returns(
          Google::Protobuf::RepeatedField[Notifyd::Proto::RoutingSettings::RoutingSetting]
        )
      end
      def routing_settings
        notifyd_routing_settings.routing_setting
      end

      sig { returns(T::Array[Notifyd::Proto::Subscriptions::Subscription]) }
      def list_susbcriptions
        subscriptions.select do |s|
          s.custom_fields.any? do |cf|
            cf.name == "category" && cf.value == "all"
          end
        end
      end

      sig { returns(T::Array[Notifyd::Proto::Subscriptions::Subscription]) }
      def thread_type_subscriptions
        subscriptions.select do |s|
          s.custom_fields.any? do |cf|
            cf.name == "category" && cf.value == "thread_type"
          end
        end
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def thread_subscriptions
        matched = subscriptions.select do |s|
          s.custom_fields.any? do |cf|
            cf.name == "category" && cf.value == "thread"
          end
        end

        result = []
        matched.each do |s|
          thread_type_cf = s.custom_fields.detect do |cf|
            cf.name == "thread_type"
          end

          thread_id_cf = s.custom_fields.detect do |cf|
            cf.name == "thread_id"
          end

          thread_obj = nil
          if thread_type_cf.present? && thread_id_cf.present?
            klass = thread_type_cf.value.camelize&.constantize

            begin
              if klass.present?
                thread_obj = klass.find(thread_id_cf.value)
              end
            rescue => e # rubocop:todo Lint/GenericRescue
              GitHub.logger.error(e)
            end
          end

          result << {
            subscription: s,
            thread_type: thread_type_cf&.value,
            thread_id: thread_id_cf&.value,
            thread_title: thread_obj&.try(:title),
            thread_premalink: thread_obj&.try(:permalink),
          }
        end

        result
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def thread_ignore_settings
        matched = routing_settings.select do |s|
          s.custom_fields.any? do |cf|
            cf.name == "category" && cf.value == "thread"
          end
        end

        result = []
        matched.each do |s|
          thread_type_cf = s.custom_fields.detect do |cf|
            cf.name == "thread_type"
          end

          thread_id_cf = s.custom_fields.detect do |cf|
            cf.name == "thread_id"
          end

          thread_obj = nil
          if thread_type_cf.present? && thread_id_cf.present?
            klass = thread_type_cf.value.camelize&.constantize

            begin
              if klass.present?
                thread_obj = klass.find(thread_id_cf.value)
              end
            rescue => e # rubocop:todo Lint/GenericRescue
              GitHub.logger.error(e)
            end
          end

          result << {
            routing_setting: s,
            thread_type: thread_type_cf&.value,
            thread_id: thread_id_cf&.value,
            thread_title: thread_obj&.try(:title),
            thread_premalink: thread_obj&.try(:permalink),
          }
        end

        result
      end

      sig { returns(T::Array[Notifyd::Proto::RoutingSettings::RoutingSetting]) }
      def list_ignore_settings
        routing_settings.select do |r|
          r.custom_fields.any? do |cf|
            cf.name == "category" && cf.value == "all"
          end
        end
      end

      sig { returns(T::Array[Notifyd::Proto::RoutingSettings::RoutingSetting]) }
      def settings
        routing_settings.select do |r|
          !r.custom_fields.any? do |cf|
            cf.value == "thread" || cf.value == "all"
          end
        end
      end

      private

      sig { returns(Notifyd::Proto::Subscriptions::GetResponse) }
      def notifyd_subscriptions
        subscriptions_service = Notifyd::SubscriptionsService.new(user, false)

        # we should add pagination for stafftools at some point
        @notifyd_subscriptions ||= T.let(subscriptions_service.get([]), T.nilable(Notifyd::Proto::Subscriptions::GetResponse))
      end

      sig { returns(Notifyd::Proto::RoutingSettings::GetResponse) }
      def notifyd_routing_settings
        rs_service = Notifyd::RoutingSettingsService.new(user, false)

        # we should add pagination for stafftools at some point
        @notifyd_routing_settings ||= T.let(rs_service.get([]), T.nilable(Notifyd::Proto::RoutingSettings::GetResponse))
      end
    end
  end
end
