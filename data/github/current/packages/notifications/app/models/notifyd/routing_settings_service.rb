# typed: true
# frozen_string_literal: true

module Notifyd
  class RoutingSettingsService
    include Notifyd::NetworkHelper
    include GitHub::Tracing

    # NewsiesSettingsStruct will be used to override actual Newsies settings
    # By default values are nil, only actual set true/false values will be overriden
    NewsiesSettingsStruct = Struct.new(
      :continuous_integration_email_enabled,
      :continuous_integration_failures_only_enabled,
      keyword_init: true
    )

    # Routing Settings (RS) namespace
    RS = Notifyd::Proto::RoutingSettings

    PAS = Notifyd::ParticipatingActivitySettings
    WAS = Notifyd::WatcherActivitySettings
    CIS = Notifyd::ContinuousIntegrationSettings

    attr_reader :user, :raise_error, :stat_tags

    # Convert Newsies::Settings into a collection of RoutingSetting instances
    class Converter
      # @see #from
      def self.from(settings, sections: [])
        new.from(settings, sections: sections)
      end

      # Convert Newsies::Settings into a collection of RoutingSetting instances
      # The sections argument indicates which parts of the settings to convert
      #
      # @example Convert the CI settings
      #
      #   Convert.from(settings, sections: %i[ci])
      def from(settings, sections: [])
        routings = sections.map do |section|
          case section
          when :ci
            from_newsies_ci_activity_setting(settings)
          when :participating
            from_newsies_participating_channel_settings(settings: settings)
          when :subscribed
            from_newsies_watcher_activity_settings(settings: settings)
          else
            nil
          end
        end

        routings.compact
      end

      sig { params(settings: Newsies::Settings).returns(RS::RoutingSetting) }
      def from_newsies_participating_channel_settings(settings:)
        channels = []
        channels << PAS::CHANNEL_EMAIL if settings.participating_settings.include?(Newsies::HANDLER_EMAIL)
        PAS.new(enabled_channels: channels).to_routing_setting
      end

      sig { params(settings: Newsies::Settings).returns(RS::RoutingSetting) }
      def from_newsies_watcher_activity_settings(settings:)
        channels = []
        channels << WAS::CHANNEL_EMAIL if settings.subscribed_settings.include?(Newsies::HANDLER_EMAIL)
        WAS.new(enabled_channels: channels).to_routing_setting
      end

      def from_newsies_ci_activity_setting(settings)
        CIS
        .new(continuous_integration_email: settings.continuous_integration_email?,
             continuous_integration_web: settings.continuous_integration_web?,
             continuous_integration_failures_only: settings.continuous_integration_failures_only?)
        .to_routing_setting
      end

      def routing_settings_to_newsies_stuct(notifyd_routing_settings)
        # Return default settings if no routing settings are found
        settings = NewsiesSettingsStruct.new(
          continuous_integration_email_enabled: true,
          continuous_integration_failures_only_enabled: true
        )
        ci_routing_settings_exist = notifyd_routing_settings.any? do |routing_setting|
          is_ci_activity_routing_setting?(routing_setting)
        end
        return settings unless ci_routing_settings_exist

        notifyd_routing_settings.each do |routing_setting|
          settings.continuous_integration_email_enabled = is_channel_enabled?(routing_setting, "email")
          settings.continuous_integration_failures_only_enabled = is_ci_activity_failed_only?(routing_setting)
        end

        settings
      end

      def is_channel_enabled?(routing_setting, channel_name)
        routing_setting.channels.any? do |channel|
          channel.name.downcase == channel_name.downcase && channel.enabled
        end
      end

      private

      def is_ci_activity_routing_setting?(routing_setting)
        matches_custom_fields = routing_setting.custom_fields.any? do |cf|
          cf.name == "delivery_group" && cf.value == "ci_activity"
        end

        ci_activity = routing_setting.filters.find { |filter| filter.reason == "ci_activity" }
        approval_requested = routing_setting.filters.find { |filter| filter.reason == "approval_requested" }

        matches_custom_fields && ci_activity.present? && approval_requested.present?
      end

      def is_ci_activity_failed_only?(routing_setting)
        ci_activity_filter = routing_setting.filters.find { |filter| filter.reason == "ci_activity" }
        ci_activity_filter.match_rules.any? do |match_rule|
          match_rule.match_rule == "eq" && match_rule.attribute == "failed" && match_rule.value == "true"
        end
      end
    end

    # this is a helper method to update participation handlers in notifyd both
    # from update_handlers and the save_handlers method
    #
    # Originally this was designed as a helper method on
    # NotificationsController. However the linter disallowed that due to it
    # not being a rails REST method
    #
    # It takes a newsies setting as parameter and returns nothing initially
    # while we are only background syncing data. Later on we want this to raise
    # or return an error
    sig { params(user: User, settings: Newsies::Settings).returns(T::Boolean) }
    def self.update_handlers(user:, settings:)
      # only save settings it it's enabled for the user
      return false unless Notifyd::Flags.new(user).enable_issue_thread_subscriptions?
      self.save_from_newsies(user, settings,
                             sections: %i[participating subscribed org_deploy_key],
                             stat_tags: ["participating_subscribed_org_deploy_key_handlers:true"])
    rescue Notifyd::NetworkHelper::APIError => e
      GitHub.logger.error("failed to store notification channel preferences to notifyd", {
        :exception => e,
        "code.namespace" => "NotificationsController",
        "code.function" => "update_handlers_in_notifyd",
      })
      # eventually we want to return something like a 503 here or
      # re-raise the error. For now we only log the error and continue
      false
    end

    sig { params(user: User, settings: Newsies::Settings, sections: T::Array[Symbol], stat_tags: T::Array[String]).returns(T::Boolean) }
    def self.save_from_newsies(user, settings, sections: [], stat_tags: ["ci_activity:true"])
      GitHub.tracer.in_span("notifyd.routing_settings_service.save_from_newsies", kind: :internal, attributes: { "gh.user.id" => user.id }) do
        new(user, !GitHub.enterprise?, stat_tags).save_from_newsies(settings, sections: sections)
      end
    end

    def self.fetch_from_notifyd(user, sections: [])
      GitHub.tracer.in_span("notifyd.routing_settings_service.fetch_from_notifyd", kind: :internal, attributes: { "gh.user.id" => user.id }) do
        new(user, !GitHub.enterprise?, ["ci_activity:true"]).fetch_from_notifyd(sections: sections)
      end
    end

    sig { params(user: ::User, notifyd_primary: T::Boolean, stat_tags: T::Array[String]).void }
    def initialize(user, notifyd_primary = false, stat_tags = [])
      @user = user
      # When notifyd is the primary settings store, we raise errors
      # While we are in darkship we hide them
      @raise_error = notifyd_primary
      @stat_tags = stat_tags
    end

    sig { params(settings: Newsies::Settings, sections: T::Array[Symbol]).returns(T::Boolean) }
    def save_from_newsies(settings, sections: [])
      save Converter.from(settings, sections: sections)
    end

    def fetch_from_notifyd(sections: [])
      custom_fields = sections.map do |section|
        case section
        when :ci
          { name: "delivery_group", value: "ci_activity" }
        else
          nil
        end
      end.compact

      get(custom_fields)
    end

    sig { params(routing_settings: T::Array[RS::RoutingSetting]).returns(T::Boolean) }
    def save(routing_settings)
      return false if routing_settings.empty?
      return false unless enabled?

      GitHub.tracer.in_span("notifyd.routing_settings_service.save", kind: :internal, attributes: { "gh.user.id" => user.id }) do
        # associate each routing setting with the user
        routing_settings.each { |r| r.user_id = user.id }
        results = replace_settings(user, routing_settings)
        results.all?(&:present?)
      end
    end

    sig { params(user: ::User, routing_settings: T::Array[RS::RoutingSetting]).returns(T::Array[T.untyped]) }
    def replace_settings(user, routing_settings)
      routing_settings.map do |routing_setting|
        settings_request = RS::Setting.new(
          channels: routing_setting.channels.to_a,
          topics: routing_setting.topics.to_a,
          filters: routing_setting.filters.to_a,
          custom_fields: routing_setting.custom_fields.to_a,
        )

        request = RS::BatchReplaceRequest.new(
          user_id: user.id,
          settings: [settings_request],
          replace_by_custom_fields: routing_setting.custom_fields.uniq,
        )

        make_network_request_to_notifyd(request.class.name, raise_error, stat_tags) do
          client&.routing_settings.batch_replace(request)
        end
      end
    end

    def get_thread_settings(thread_type, thread_id)
      response_data = get([
        RS::CustomField.new(name: "thread_type", value: thread_type),
        RS::CustomField.new(name: "thread_id", value: thread_id.to_s)
      ])

      response_data.routing_setting.any? ? response_data.routing_setting.first : nil
    end

    sig { params(custom_fields: T::Array[RS::CustomField]).returns(RS::GetResponse) }
    def get(custom_fields)
      empty_result = Notifyd::Proto::RoutingSettings::GetResponse.new(routing_setting: [])

      return empty_result unless enabled?

      GitHub.tracer.in_span("notifyd.routing_settings_service.get", kind: :internal, attributes: { "gh.user.id" => user.id }) do
        request = RS::GetRequest.new(
          user_id: @user.id,
          filter_by_custom_fields: custom_fields,
        )

        response = make_network_request_to_notifyd(request.class.name, raise_error, stat_tags) do
          client&.routing_settings.get(request)
        end

        empty_result = Notifyd::Proto::RoutingSettings::GetResponse.new(routing_setting: [])

        return empty_result unless response.present?
        response.data
      end
    end

    def delete(custom_fields)
      return false if custom_fields.empty?
      return false unless enabled?

      GitHub.tracer.in_span("notifyd.routing_settings_service.delete", kind: :internal, attributes: { "gh.user.id" => user.id }) do

        # associate each routing setting with the user
        data = get(custom_fields)

        # Filter the ones to delete
        to_delete = data.routing_setting.map { |routing| RS::DeleteRequest.new(id: routing.id) }

        # Delete
        request = RS::BatchCreateAndDeleteRequest.new(to_delete: to_delete, to_create: [])

        response = make_network_request_to_notifyd(request.class.name, raise_error, stat_tags) do
          client&.routing_settings.batch_create_and_delete(request)
        end

        response.present?
      end
    end

    private

    def enabled?
      return false if GitHub.enterprise?

      client.present?
    end

    def client
      @client ||= Notifyd.client
    end

    # A routing setting is a replacement of another if they have the same user and set of custom fields
    def replacement?(original, maybe)
      original.user_id == maybe.user_id && original.custom_fields.to_set == maybe.custom_fields.to_set
    end
  end
end
