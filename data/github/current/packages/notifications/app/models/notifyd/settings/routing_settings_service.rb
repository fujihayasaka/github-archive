# typed: strict
# frozen_string_literal: true

module Notifyd
  module Settings
    class RoutingSettingsService
      include Notifyd::NetworkHelper
      include GitHub::Tracing

      # Routing Settings (RS) namespace
      RS = Notifyd::Proto::RoutingSettingsV2
      NS = Notifications::Settings

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

      sig { params(user_id: Integer).returns(T.nilable(NS::ParticipantSettings)) }
      def self.participant_settings(user_id)
        settings = get(user_id, [ParticipantSettings.custom_field_group])
        return nil if settings.nil?

        to_settings(user_id, settings.routing_setting.to_a).participant
      end

      sig { params(user_id: Integer).returns(T.nilable(NS::WatcherSettings)) }
      def self.watcher_settings(user_id)
        settings = get(user_id, [WatcherSettings.custom_field_group])
        return nil if settings.nil?

        to_settings(user_id, settings.routing_setting.to_a).watcher
      end

      sig { params(user_id: Integer).returns(T.nilable(NS::ActionsSettings)) }
      def self.actions_settings(user_id)
        settings = get(user_id, [ActionsSettings.custom_field_group])
        return nil if settings.nil?

        to_settings(user_id, settings.routing_setting.to_a).actions
      end

      sig { params(user_id: Integer).returns(T.nilable(NS::VulnerabilitySettings)) }
      def self.vulnerability_settings(user_id)
        settings = get(user_id, [VulnerabilitySettings.custom_field_group])
        return nil if settings.nil?

        to_settings(user_id, settings.routing_setting.to_a).vulnerability
      end

      sig { params(user_id: Integer).returns(T.nilable(T::Boolean)) }
      def self.own_email_settings(user_id)
        settings = get(user_id, [SelfActivityEmailSettings.custom_field_group])
        return nil if settings.nil?

        to_settings(user_id, settings.routing_setting.to_a).own_email
      end

      sig { params(user_id: Integer, organization_id: Integer).returns(T.nilable(NS::MemberFeatureRequestsSettings)) }
      def self.member_feature_requests_settings(user_id, organization_id)
        settings = get(user_id, [MemberFeatureRequestsSettings.custom_field_group(user_id:, organization_id:)])
        return nil if settings.nil?

        # Remove muted features, if any
        to_delete = T.let([], T::Array[MemberFeatureRequest::Feature])
        settings.routing_setting.each do |setting|
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
        NS::MemberFeatureRequestsSettings.new(features:)
      end

      sig { params(user_id: Integer).returns(T.nilable(NS::SecurityCampaignsSettings)) }
      def self.security_campaigns_settings(user_id)
        settings = get(user_id, [SecurityCampaignsSettings.custom_field_group])
        return nil if settings.nil?

        to_settings(user_id, settings.routing_setting.to_a).security_campaigns
      end


      # Return the settings for a user or nil on failure.
      #
      # Optionally, a sequence of custom field groups can also be provided.
      # In such case, only the settings matching those groups will be returned.
      sig { params(user_id: Integer, groups: T.nilable(T::Array[RS::CustomFieldGroup])).returns(T.nilable(NS::Settings)) }
      def self.settings(user_id, groups = nil)
        if groups.nil?
          groups = [
            ParticipantSettings.custom_field_group,
            WatcherSettings.custom_field_group,
            ActionsSettings.custom_field_group,
            VulnerabilitySettings.custom_field_group,
            IssueCommentsEmailSettings.custom_field_group,
            PullRequestReviewsEmailSettings.custom_field_group,
            PullRequestPushesEmailSettings.custom_field_group,
            SelfActivityEmailSettings.custom_field_group,
            SecurityCampaignsSettings.custom_field_group,
          ]
        end
        settings = get(user_id, groups)
        return nil if settings.nil?

        to_settings(user_id, settings.routing_setting.to_a)
      end

      sig { params(user_ids: T::Array[Integer]).returns(T.nilable(T::Hash[Integer, NS::Settings])) }
      def self.batch_subscription_settings(user_ids)
        batch_settings(user_ids, NS::Subset::ParticipantWatcher)
      end

      sig do
        params(
          user_ids: T::Array[Integer],
          subset: T.nilable(NS::Subset)
        ).returns(T.nilable(T::Hash[Integer, NS::Settings]))
      end
      def self.batch_settings(user_ids, subset)
        # TODO(abeaumont): We should never allow to subset to be nil.
        # For now, we simply return early with empty settings for
        # compatibility with the settings API.
        return Hash.new { NS::Settings.new } if subset.nil?

        groups = case subset
        when NS::Subset::Actions
          # Actions are delivered by notifyd, they shouldn't be asked for.
          return nil
        when NS::Subset::ParticipantWatcher
          [
            ParticipantSettings::custom_field_group,
            WatcherSettings::custom_field_group,
          ]
        when NS::Subset::ParticipantWatcherIssueCommentEmail
          [
            ParticipantSettings.custom_field_group,
            WatcherSettings.custom_field_group,
            IssueCommentsEmailSettings.custom_field_group,
          ]
        when NS::Subset::ParticipantWatcherPullRequestReviewEmail
          [
            ParticipantSettings.custom_field_group,
            WatcherSettings.custom_field_group,
            PullRequestReviewsEmailSettings.custom_field_group,
          ]
        when NS::Subset::ParticipantWatcherPullRequestPushEmail
          [
            ParticipantSettings.custom_field_group,
            WatcherSettings.custom_field_group,
            PullRequestPushesEmailSettings.custom_field_group,
          ]
        when NS::Subset::Vulnerability
          [VulnerabilitySettings.custom_field_group]
        end

        routing_settings = batch_get(user_ids, groups)
        return nil if routing_settings.nil?

        settings_hash = routing_settings.routing_setting.group_by(&:user_id)
        settings = {}
        user_ids.each do |user_id|
          settings[user_id] = to_settings(user_id, settings_hash[user_id].to_a)
        end

        # Leave only the requested settings. While not strictly necessary,
        # it should make it easier to detect bugs.
        settings.each do |user_id, setting|
          settings[user_id] = case subset
          when NS::Subset::ParticipantWatcher
            NS::Settings.new(
              watcher: setting.watcher,
              participant: setting.participant
            )
          when NS::Subset::ParticipantWatcherIssueCommentEmail
            NS::Settings.new(
              watcher: setting.watcher,
              participant: setting.participant,
              issue_comment_email: setting.issue_comment_email,
            )
          when NS::Subset::ParticipantWatcherPullRequestReviewEmail
            NS::Settings.new(
              watcher: setting.watcher,
              participant: setting.participant,
              pull_request_review_email: setting.pull_request_review_email,
            )
          when NS::Subset::ParticipantWatcherPullRequestPushEmail
            NS::Settings.new(
              watcher: setting.watcher,
              participant: setting.participant,
              pull_request_push_email: setting.pull_request_push_email,
            )
          when NS::Subset::Vulnerability
            NS::Settings.new(vulnerability: setting.vulnerability)
          end
        end

        settings
      end

      sig { params(user_id: Integer).returns(T.nilable(NS::MobileSettings)) }
      def self.mobile_settings(user_id)
        # Defaults
        actions = T.let(false, T::Boolean)
        failures = T.let(false, T::Boolean)
        releases = T.let(false, T::Boolean)
        live_activity_copilot_coding_agent = T.let(false, T::Boolean)

        user = User.new(id: user_id)
        flags = Notifyd::Flags.new(user)

        custom_field_groups = [MobileActionsSettings.custom_field_group]
        custom_field_groups << MobileReleasesSettings.custom_field_group if flags.push_releases?
        custom_field_groups << MobileLiveActivityCopilotCodingAgentSettings.custom_field_group if flags.push_live_activity_copilot_coding_agent?

        if custom_field_groups.any?
          routing_settings = get(user_id, custom_field_groups)
          return nil if routing_settings.nil?

          routing_settings.routing_setting.each do |setting|
            case setting.custom_fields
            when MobileActionsSettings.custom_fields
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
            when MobileReleasesSettings.custom_fields
              setting.channels.each do |channel|
                case channel.name.downcase.to_sym
                when :push, :all
                  releases = channel.enabled
                end
              end
            when MobileLiveActivityCopilotCodingAgentSettings.custom_fields
              # Only consider the main setting and ignore mute routing settings
              if setting.filters.any? { |filter| filter.reason == "live_activity_copilot_coding_agent" }
                setting.channels.each do |channel|
                  case channel.name.downcase.to_sym
                  when :push, :all
                    live_activity_copilot_coding_agent = channel.enabled
                  end
                end
              end
            end
          end
        end

        NS::MobileSettings.new(
          actions: NS::MobileActionsSettings.new(
            push: actions,
            failures: failures,
          ), releases: NS::MobileReleasesSettings.new(
            push: releases,
          ), live_activity: Notifications::Settings::MobileLiveActivitySettings.new(
            copilot_coding_agent: Notifications::Settings::MobileLiveActivityCopilotCodingAgentSettings.new(
              push: live_activity_copilot_coding_agent,
            ),
          )
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
          user_ids: T::Array[Integer],
          custom_field_groups: T::Array[RS::CustomFieldGroup]
        ).returns(T.nilable(RS::BatchGetResponse))
      end
      private_class_method def self.batch_get(user_ids, custom_field_groups)
        GitHub.tracer.in_span("notifyd.routing_settings_service.batch_get", kind: :internal) do
          request = RS::BatchGetRequest.new(
            user_ids: user_ids,
            custom_field_groups: custom_field_groups,
          )

          response = request(T.must(request.class.name)) do
            Notifyd.client.routing_settings_v2.batch_get(request)
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
      private_class_method def self.request(request_class_name, &block)
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

      sig { params(user_id: Integer, routing_settings: T::Array[RS::RoutingSetting]).returns(NS::Settings) }
      private_class_method def self.to_settings(user_id, routing_settings)
        web = web_default_enabled?(user_id)
        participant = NS::ParticipantSettings.new(email: true, web:)
        watcher = NS::WatcherSettings.new(email: true, web:)
        actions = NS::ActionsSettings.new(email: true, web:, failures: true)
        vulnerability = NS::VulnerabilitySettings.new(email: true, web:)
        issue_comment_email = T.let(true, T::Boolean)
        pull_request_review_email = T.let(true, T::Boolean)
        pull_request_push_email = T.let(true, T::Boolean)
        own_email = T.let(false, T::Boolean)
        security_campaigns = NS::SecurityCampaignsSettings.new(email: true)

        routing_settings.each do |setting|
          channels = channels(setting)
          case setting.custom_fields
          when ParticipantSettings.custom_fields
            participant = NS::ParticipantSettings.new(
              email: channels.email.nil? ? participant.email : T.must(channels.email),
              web: channels.web.nil? ? participant.web : T.must(channels.web)
            )
          when WatcherSettings.custom_fields
            watcher = NS::WatcherSettings.new(
              email: channels.email.nil? ? watcher.email : T.must(channels.email),
              web: channels.web.nil? ? watcher.web : T.must(channels.web)
            )
          when ActionsSettings.custom_fields
            failures = T.let(nil, T.nilable(T::Boolean))
            setting.filters.each do |filter|
              if filter.reason == "ci_activity"
                # CI Activity filter is present, default no longer applies.
                failures = false
                filter.match_rules.each do |rule|
                  failures = true if rule.match_rule == "eq" && rule.attribute == "failed" && rule.value == "true"
                end
              end
            end

            actions = NS::ActionsSettings.new(
              email: channels.email.nil? ? actions.email : T.must(channels.email),
              web: channels.web.nil? ? actions.web : T.must(channels.web),
              failures: failures.nil? ? actions.failures : failures
            )
          when VulnerabilitySettings.custom_fields
            vulnerability = NS::VulnerabilitySettings.new(
              email: channels.email.nil? ? vulnerability.email : T.must(channels.email),
              web: channels.web.nil? ? vulnerability.web : T.must(channels.web)
            )
          when IssueCommentsEmailSettings.custom_fields
            issue_comment_email = T.must(channels.email) unless channels.email.nil?
          when PullRequestReviewsEmailSettings.custom_fields
            pull_request_review_email = T.must(channels.email) unless channels.email.nil?
          when PullRequestPushesEmailSettings.custom_fields
            pull_request_push_email = T.must(channels.email) unless channels.email.nil?
          when SelfActivityEmailSettings.custom_fields
            own_email = T.must(channels.email) unless channels.email.nil?
          when SecurityCampaignsSettings.custom_fields
            security_campaigns = NS::SecurityCampaignsSettings.new(
              email: channels.email.nil? ? security_campaigns.email : T.must(channels.email),
            )
          end
        end

        NS::Settings.new(
          participant:, watcher:, actions:, vulnerability:, issue_comment_email:,
          pull_request_review_email:, pull_request_push_email:, own_email:, security_campaigns:
        )
      end

      sig { params(setting: RS::RoutingSetting).returns(Channels) }
      private_class_method def self.channels(setting)
        email = T.let(nil, T.nilable(T::Boolean))
        web = T.let(nil, T.nilable(T::Boolean))
        push = T.let(nil, T.nilable(T::Boolean))

        setting.channels.each do |channel|
          case channel.name.downcase.to_sym
          when :web
            web = channel.enabled
          when :email
            email = channel.enabled
          when :push
            push = channel.enabled
          when :all
            web = channel.enabled
            email = channel.enabled
            push = channel.enabled
          end
        end

        Channels.new(email:, web:, push:)
      end

      sig { params(user_id: Integer).returns(T::Boolean) }
      private_class_method def self.web_default_enabled?(user_id)
        # https://github.com/github/notifyd/blob/6a156283871b76d39fbdc6b27592194a2e4989b5/internal/pkg/routing/default.go#L7-L20
        user_id < 16589632 || user_id >= 107241421
      end

      class Channels < T::Struct
        const :email, T.nilable(T::Boolean)
        const :web, T.nilable(T::Boolean)
        const :push, T.nilable(T::Boolean)
      end
    end
  end
end
