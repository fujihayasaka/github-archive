# typed: strict
# frozen_string_literal: true

module Notifyd
  module Settings
    class RoutingSettingsService
      include Notifyd::NetworkHelper
      include GitHub::Tracing

      # Routing Settings (RS) namespace
      RS = Notifyd::Proto::RoutingSettingsV2

      sig do
        params(
          user_id: Integer,
          thread_type: String,
          thread_id: Integer
        ).returns(T.nilable(MuteSetting))
      end
      def self.thread_mute_setting(user_id, thread_type, thread_id)
        response = get(user_id, [RS::CustomFieldGroup.new(
          fields: [
            RS::CustomField.new(name: "thread_type", value: thread_type),
            RS::CustomField.new(name: "thread_id", value: thread_id.to_s)
          ]
        )])

        return nil if response.nil?
        muted = T.let(false, T::Boolean)
        created_at = T.let(nil, T.nilable(Integer))
        response.routing_setting.each do |setting|
          # New format
          # @see https://github.com/github/notifyd/blob/main/docs/proposals/2022-11-15-ignore-thread-setting.md
          rule = setting.filters.map(&:match_rules).flatten.compact.find do |rule|
            rule.attribute == "thread_participant_activity" && rule.value == "true" && rule.match_rule == "eq"
          end
          if rule
            setting.channels.each do |channel|
              if channel.name.downcase == "all" && !channel.enabled
                muted = true
                created_at ||= setting.created_at
                created_at = setting.created_at if setting.created_at < created_at
              end
            end
          end

          # Old format
          ignore_reasons = Set.new(%w[author comment manual])
          reasons = setting.filters.map(&:reason).to_set

          if reasons == ignore_reasons
            setting.channels.each do |channel|
              if channel.name.downcase == "all" && !channel.enabled
                muted = true
                created_at ||= setting.created_at
                created_at = setting.created_at if setting.created_at < created_at
              end
            end
          end
        end

        MuteSetting.new(muted:, created_at:)
      end

      sig { params(user_id: Integer).returns(T.nilable(Notifications::Settings::ActionsSettings)) }
      def self.get_actions_settings(user_id)
        # Defaults
        email = T.let(true, T::Boolean)
        # https://github.com/github/notifyd/blob/6a156283871b76d39fbdc6b27592194a2e4989b5/internal/pkg/routing/default.go#L7-L20
        web = T.let(user_id < 16589632 || user_id >= 107241421, T::Boolean)
        failures = T.let(true, T::Boolean)

        # NOTE(abeaumont): The current implementation of get doesn't distinguish
        # between an error or no results, which forces us to mark the request
        # as primary instead. This may change in the future.
        routing_settings = get(user_id, [ActionsSettings.custom_field_group])
        return nil if routing_settings.nil?

        routing_settings.routing_setting.each do |setting|
          setting.channels.each do |channel|
            case channel.name.downcase.to_sym
            when :web
              web = channel.enabled
            when :email
              email = channel.enabled
            when :all
              web = channel.enabled
              email = channel.enabled
            end
          end

          setting.filters.each do |filter|
            if filter.reason == "ci_activity"
              # CI Activity filter is present, default no longer applies.
              failures = false
              filter.match_rules.each do |rule|
                failures = true if rule.match_rule == "eq" && rule.attribute == "failed" && rule.value == "true"
              end
            end
          end
        end

        Notifications::Settings::ActionsSettings.new(email:, web:, failures:)
      end

      sig { params(user_id: Integer, organization_id: Integer).returns(T.nilable(Notifications::Settings::MemberFeatureRequestsSettings)) }
      def self.get_member_feature_requests_settings(user_id, organization_id)
        routing_settings = get(user_id, [MemberFeatureRequestsSettings.custom_field_group(user_id:, organization_id:)])
        return nil if routing_settings.nil?

        # Remove muted features, if any
        to_delete = T.let([], T::Array[MemberFeatureRequest::Feature])
        routing_settings.routing_setting.each do |setting|
          setting.filters.each do |filter|
            if filter.trigger == "any"
              to_delete = MemberFeatureRequest::Feature.values
            else
              feature = MemberFeatureRequest::Feature.from_string(filter.trigger)
              to_delete << feature if feature
            end
          end
        end

        features = MemberFeatureRequest::Feature.values - to_delete
        Notifications::Settings::MemberFeatureRequestsSettings.new(features:)
      end

      sig { params(user_id: Integer).returns(T.nilable(Notifications::Settings::SecurityCampaignsSettings)) }
      def self.get_security_campaigns_settings(user_id)
        # Defaults
        email = T.let(true, T::Boolean)

        routing_settings = get(user_id, [SecurityCampaignsSettings.custom_field_group])
        return nil if routing_settings.nil?
        routing_settings.routing_setting.each do |setting|
          setting.channels.each do |channel|
            case channel.name.downcase.to_sym
            when :email
              email = channel.enabled
            when :all
              email = channel.enabled
            end
          end
        end

        Notifications::Settings::SecurityCampaignsSettings.new(email:)
      end

      sig { params(user_id: Integer).returns(T.nilable(Notifications::Settings::MobileSettings)) }
      def self.get_mobile_settings(user_id)
        # Defaults
        actions = T.let(false, T::Boolean)
        failures = T.let(false, T::Boolean)
        releases = T.let(false, T::Boolean)

        flags = Notifyd::Flags.new(User.new(id: user_id))

        # TODO(abeaumont): Merge these two custom field groups into a single request once the v2 API is in place.
        if flags.push_ci_activity?
          routing_settings = get(user_id, [MobileActionsSettings.custom_field_group])
          return nil if routing_settings.nil?
          routing_settings.routing_setting.each do |setting|
            setting.channels.each do |channel|
              case channel.name.downcase.to_sym
              when :push, :all
                actions = channel.enabled
              end
            end
            setting.filters.each do |filter|
              if filter.reason == "ci_activity"
                # CI Activity filter is present, default no longer applies.
                failures = false
                filter.match_rules.each do |rule|
                  failures = true if rule.match_rule == "eq" && rule.attribute == "failed" && rule.value == "true"
                end
              end
            end
          end
        end

        if flags.push_releases?
          routing_settings = get(user_id, [MobileReleasesSettings.custom_field_group])
          return nil if routing_settings.nil?

          routing_settings.routing_setting.each do |setting|
            setting.channels.each do |channel|
              case channel.name.downcase.to_sym
              when :push, :all
                releases = channel.enabled
              end
            end
          end
        end

        Notifications::Settings::MobileSettings.new(
          actions: Notifications::Settings::MobileActionsSettings.new(
            push: actions,
            failures: failures,
          ), releases: Notifications::Settings::MobileReleasesSettings.new(
            push: releases,
          ),
        )
      end

      sig do
        params(
          user_id: Integer,
          settings: T::Array[RS::Setting],
          custom_field_groups: T::Array[RS::CustomFieldGroup]
        ).returns(T::Boolean)
      end
      def self.replace(user_id, settings, custom_field_groups)
        GitHub.tracer.in_span("notifyd.routing_settings_service.replace",
          kind: :internal,
          attributes: { "gh.user.id" => user_id },
        ) do
          request = RS::ReplaceRequest.new(user_id:, settings:, custom_field_groups:)
          response = request(T.must(request.class.name)) do
            # NOTE(abeaumont): Unfortunately we client is not guaranteed here,
            # as this may be called from creation of ghost and staff users
            # while testing. I tried to address that but it's too big of a rabbit
            # hole for now.
            Notifyd.client&.routing_settings_v2&.replace(request)
          end
          response.present?
        end
      end

      sig { params(user_id: Integer, custom_field_groups: T::Array[RS::CustomFieldGroup]).returns(T::Boolean) }
      def self.delete(user_id, custom_field_groups)
        return false if custom_field_groups.empty?

        GitHub.tracer.in_span("notifyd.routing_settings_service.delete",
          kind: :internal,
          attributes: { "gh.user.id" => user_id }
        ) do
          request = RS::DeleteRequest.new(user_id:, custom_field_groups:)
          response = request(T.must(request.class.name)) do
            Notifyd.client.routing_settings_v2.delete(request)
          end
          response.present?
        end
      end

      sig { params(user_id: Integer, custom_field_groups: T::Array[RS::CustomFieldGroup]).returns(T.nilable(RS::GetResponse)) }
      private_class_method def self.get(user_id, custom_field_groups)
        GitHub.tracer.in_span("notifyd.routing_settings_service.get", kind: :internal, attributes: { "gh.user.id" => user_id }) do
          request = RS::GetRequest.new(
            custom_field_groups: custom_field_groups,
            user_id: user_id,
          )

          response = request(T.must(request.class.name)) do
            Notifyd.client.routing_settings_v2.get(request)
          end

          return nil unless response.present?
          response.data
        end
      end

      sig do
        params(
          request_class_name: String,
          block: T.proc.returns(T.nilable(Twirp::ClientResp[T.any(
            Notifyd::Proto::RoutingSettingsV2::GetResponse,
            Google::Protobuf::Empty
          )]))
        ).returns(T.nilable(Twirp::ClientResp[T.any(
          Notifyd::Proto::RoutingSettingsV2::GetResponse,
          Google::Protobuf::Empty
        )]))
      end
      private_class_method  def self.request(request_class_name, &block)
        GitHub.tracer.in_span(
          "notifyd.network_helper",
          kind: :internal,
          attributes: { "code.namespace" => request_class_name.to_s }
        ) do
          ResponseHandler.new(request_class_name: request_class_name, raise_error: false, tags: []).execute do
            block.call
          end
        end
      end
    end
  end
end
