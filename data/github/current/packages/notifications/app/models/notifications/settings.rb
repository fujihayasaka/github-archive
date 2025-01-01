# typed: strict
# frozen_string_literal: true

# The high level API for global routing settings owned by notifyd.
#
# The API offers the methods needed by the API users in a
# straightforward way and converts those simple calls into
# the necessary scaffolding to access the relevant data.
#
# The API has two differentiated set of operations:
# - Write operations, that return a boolean indicating whether
#   the operation was succesful or not.
# - Read operations, that return a plain data object with
#   the requested information if successful or nothing.
#
# NOTE(abeaumont 2025-06-11): Currently the API is just an indirection layer to
# group and abstract the existing calls to the notification settings that will
# eventually be owned by notifyd. As such, the current implementation has a lot
# of room for improvement and will get tamed over time.
module Notifications
  module Settings
    sig { params(user: User).returns(T::Boolean) }
    def self.disable_vulnerability_email(user)
      GitHub.tracer.in_span("disable_vulnerability_email", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.settings.disable_vulnerability_email") do
          response = GitHub.newsies.get_and_update_settings user do |settings|
            settings.vulnerability_email = false

            next if GitHub.enterprise?

            GitHub.dogstats.distribution_time("notifications.notifyd.settings.disable_vulnerability_email") do
              success = Notifyd::Settings::RoutingSettingsService.replace(
                user.id,
                [
                  Notifyd::Settings::VulnerabilitySettings.to_routing_setting(
                    VulnerabilitySettings.new(email: false, web: settings.vulnerability_web)
                  )
                ],
                [Notifyd::Settings::VulnerabilitySettings.custom_field_group]
              )
              GitHub.dogstats.increment("notifications.notifyd.settings.disable_vulnerability_email.count", tags: ["success:#{success}"])
            end
          end
          GitHub.dogstats.increment("notifications.settings.disable_vulnerability_email.count", tags: ["success:#{response.success?}"])
          response.success?
        end
      end
    end

    sig { params(user: User).returns(T::Boolean) }
    def self.disable_all(user)
      GitHub.tracer.in_span("disable_all", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.settings.disable_all") do
          response = GitHub.newsies.get_and_update_settings user do |settings|
            settings.participating_settings.clear
            settings.subscribed_settings.clear
            settings.vulnerability_cli = false
            settings.vulnerability_web = false
            settings.vulnerability_email = false
            settings.continuous_integration_web = false
            settings.continuous_integration_email = false

            next if GitHub.enterprise?

            GitHub.dogstats.distribution_time("notifications.notifyd.settings.disable_all") do
              routing_settings = [
                Notifyd::Settings::ParticipantSettings.to_routing_setting(
                  ParticipantSettings.new(email: false, web: false),
                ),
                Notifyd::Settings::WatcherSettings.to_routing_setting(
                  WatcherSettings.new(email: false, web: false),
                ),
                Notifyd::Settings::ActionsSettings.to_routing_setting(
                  ActionsSettings.new(
                    email: false,
                    web: false,
                    failures: settings.continuous_integration_failures_only?,
                  ),
                ),
                Notifyd::Settings::VulnerabilitySettings.to_routing_setting(
                  VulnerabilitySettings.new(email: false, web: false),
                )
              ]
              groups = [
                Notifyd::Settings::ParticipantSettings.custom_field_group,
                Notifyd::Settings::WatcherSettings.custom_field_group,
                Notifyd::Settings::ActionsSettings.custom_field_group,
                Notifyd::Settings::VulnerabilitySettings.custom_field_group
              ]
              success = Notifyd::Settings::RoutingSettingsService.replace(user.id, routing_settings, groups)
              GitHub.dogstats.increment("notifications.notifyd.settings.disable_all.count", tags: ["success:#{success}"])
            end
          end
          GitHub.dogstats.increment("notifications.settings.disable_all.count", tags: ["success:#{response.success?}"])
          response.success?
        end
      end
    end

    # Update web channel in global routing settings for a user.
    #
    # NOTE(abeaumont): This method has several issues being addressed in
    # https://github.com/github/notifyd/issues/4835
    # For now, we migrate things verbatim, including the mobile push setting
    # that shouldn't belong here, but it'll be handled in
    # https://github.com/github/notifyd/issues/4834
    sig do
      params(
        user: User,
        watcher: T.nilable(T::Boolean),
        participant: T.nilable(T::Boolean),
        vulnerability: T.nilable(T::Boolean),
      ).returns(T::Boolean)
    end
    def self.set_web(user, watcher: nil, participant: nil, vulnerability: nil)
      GitHub.tracer.in_span("set_web", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.settings.set_web") do
          response = GitHub.newsies.get_and_update_settings(user) do |settings|
            routing_settings = []
            groups = []
            unless watcher.nil?
              settings.subscribed_web = watcher
              routing_settings << Notifyd::Settings::WatcherSettings.to_routing_setting(
                WatcherSettings.new(email: settings.subscribed_email?, web: settings.subscribed_web?),
              )
              groups << Notifyd::Settings::WatcherSettings.custom_field_group
            end
            unless participant.nil?
              settings.participating_web = participant
              routing_settings << Notifyd::Settings::ParticipantSettings.to_routing_setting(
                ParticipantSettings.new(email: settings.participating_email?, web: settings.participating_web?),
              )
              groups << Notifyd::Settings::ParticipantSettings.custom_field_group
            end
            unless vulnerability.nil?
              settings.vulnerability_web = vulnerability
              routing_settings << Notifyd::Settings::VulnerabilitySettings.to_routing_setting(
                VulnerabilitySettings.new(email: settings.vulnerability_email?, web: settings.vulnerability_web?),
              )
              groups << Notifyd::Settings::VulnerabilitySettings.custom_field_group
            end

            next if routing_settings.empty?
            next if GitHub.enterprise?

            GitHub.dogstats.distribution_time("notifications.notifyd.settings.set_web") do
              success = Notifyd::Settings::RoutingSettingsService.replace(user.id, routing_settings, groups)
              GitHub.dogstats.increment("notifications.notifyd.settings.set_web.count", tags: ["success:#{success}"])
            end
          end
          GitHub.dogstats.increment("notifications.settings.set_web.count", tags: ["success:#{response.success?}"])
          response.success?
        end
      end
    end

    # Update email channel in global routing settings for a user.
    #
    # NOTE(abeaumont): This currently only considers participant and watcher
    # settings and should be extended. At the time of writing this (2025-06)
    # it's only used in Stafftools and usage is minimal, so it shouldn't be
    # much of a problem.
    sig { params(user: User, enabled: T::Boolean).returns(T::Boolean) }
    def self.set_email(user, enabled)
      GitHub.tracer.in_span("set_email", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.settings.set_email") do
          response = GitHub.newsies.get_and_update_settings user do |settings|
            if enabled
              settings.participating_settings << "email"
              settings.subscribed_settings << "email"
            else
              settings.participating_settings.delete("email")
              settings.subscribed_settings.delete("email")
            end

            next if GitHub.enterprise?

            GitHub.dogstats.distribution_time("notifications.notifyd.settings.set_email") do
              routing_settings = [Notifyd::Settings::ParticipantSettings.to_routing_setting(
                ParticipantSettings.new(email: enabled, web: settings.participating_web?),
              ), Notifyd::Settings::WatcherSettings.to_routing_setting(
                WatcherSettings.new(email: enabled, web: settings.subscribed_web?),
              )]
              groups = [
                Notifyd::Settings::ParticipantSettings.custom_field_group,
                Notifyd::Settings::WatcherSettings.custom_field_group,
              ]
              success = Notifyd::Settings::RoutingSettingsService.replace(user.id, routing_settings, groups)
              GitHub.dogstats.increment("notifications.notifyd.settings.set_email.count", tags: ["success:#{success}"])
            end
          end
          GitHub.dogstats.increment("notifications.settings.set_email.count", tags: ["success:#{response.success?}"])
          response.success?
        end
      end
    end

    sig { params(user: User, settings: ParticipantSettings).returns(T::Boolean) }
    def self.set_participant(user, settings)
      GitHub.tracer.in_span("set_participant", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.settings.set_participant") do
          response = GitHub.newsies.get_and_update_settings(user) do |newsies_settings|
            handlers = []
            handlers << Newsies::HANDLER_EMAIL if settings.email
            handlers << Newsies::HANDLER_WEB if settings.web
            newsies_settings.participating_settings = handlers

            next if GitHub.enterprise?

            GitHub.dogstats.distribution_time("notifications.notifyd.settings.set_participant") do
              success = Notifyd::Settings::RoutingSettingsService.replace(
                user.id,
                [Notifyd::Settings::ParticipantSettings.to_routing_setting(settings)],
                [Notifyd::Settings::ParticipantSettings.custom_field_group],
              )
              GitHub.dogstats.increment("notifications.notifyd.settings.set_participant.count", tags: ["success:#{success}"])
            end
          end
          GitHub.dogstats.increment("notifications.settings.set_participant.count", tags: ["success:#{response.success?}"])
          response.success?
        end
      end
    end

    sig { params(user: User, settings: WatcherSettings).returns(T::Boolean) }
    def self.set_watcher(user, settings)
      GitHub.tracer.in_span("set_watcher", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.settings.set_watcher") do
          response = GitHub.newsies.get_and_update_settings(user) do |newsies_settings|
            handlers = []
            handlers << Newsies::HANDLER_EMAIL if settings.email
            handlers << Newsies::HANDLER_WEB if settings.web
            newsies_settings.subscribed_settings = handlers

            next if GitHub.enterprise?

            GitHub.dogstats.distribution_time("notifications.notifyd.settings.set_watcher") do
              success = Notifyd::Settings::RoutingSettingsService.replace(
                user.id,
                [Notifyd::Settings::WatcherSettings.to_routing_setting(settings)],
                [Notifyd::Settings::WatcherSettings.custom_field_group],
              )
              GitHub.dogstats.increment("notifications.notifyd.settings.set_watcher.count", tags: ["success:#{success}"])
            end
          end
          GitHub.dogstats.increment("notifications.settings.set_watcher.count", tags: ["success:#{response.success?}"])
          response.success?
        end
      end
    end

    sig { params(user: User, settings: ActionsSettings).returns(T::Boolean) }
    def self.set_actions(user, settings)
      GitHub.tracer.in_span("set_actions", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.settings.set_actions") do
          response = GitHub.newsies.get_and_update_settings(user) do |newsies_settings|
            newsies_settings.continuous_integration_web = settings.web
            newsies_settings.continuous_integration_email = settings.email
            newsies_settings.continuous_integration_failures_only = settings.failures

            next if GitHub.enterprise?

            GitHub.dogstats.distribution_time("notifications.notifyd.settings.set_actions") do
              success = Notifyd::Settings::RoutingSettingsService.replace(
                user.id,
                [Notifyd::Settings::ActionsSettings.to_routing_setting(settings)],
                [Notifyd::Settings::ActionsSettings.custom_field_group],
              )
              GitHub.dogstats.increment("notifications.notifyd.settings.set_actions.count", tags: ["success:#{success}"])
            end
          end
          GitHub.dogstats.increment("notifications.settings.set_actions.count", tags: ["success:#{response.success?}"])
          response.success?
        end
      end
    end

    sig { params(user: User, settings: VulnerabilitySettings).returns(T::Boolean) }
    def self.set_vulnerability(user, settings)
      GitHub.tracer.in_span("set_vulnerability", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.settings.set_vulnerability") do
          response = GitHub.newsies.get_and_update_settings(user) do |newsies_settings|
            newsies_settings.vulnerability_web = settings.web
            newsies_settings.vulnerability_email = settings.email

            next if GitHub.enterprise?

            GitHub.dogstats.distribution_time("notifications.notifyd.settings.set_vulnerability") do
              success = Notifyd::Settings::RoutingSettingsService.replace(
                user.id,
                [
                  Notifyd::Settings::VulnerabilitySettings.to_routing_setting(
                    VulnerabilitySettings.new(
                      email: newsies_settings.vulnerability_email?,
                      web: newsies_settings.vulnerability_web?
                    )
                  )
                ],
                [Notifyd::Settings::VulnerabilitySettings.custom_field_group],
              )
              GitHub.dogstats.increment("notifications.notifyd.settings.set_vulnerability.count", tags: ["success:#{success}"])
            end
          end
          GitHub.dogstats.increment("notifications.settings.set_vulnerability.count", tags: ["success:#{response.success?}"])
          response.success?
        end
      end
    end

    sig { params(user: User, organization_id: Integer, settings: MemberFeatureRequestsSettings).returns(T::Boolean) }
    def self.set_member_feature_requests(user, organization_id, settings)
      GitHub.tracer.in_span("set_member_feature_requests", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.settings.set_member_feature_requests") do
          # Member feature requests settings have an unusual behaviour,
          # the setting is only used to mute features.
          custom_field_groups = [Notifyd::Settings::MemberFeatureRequestsSettings.custom_field_group(user_id: user.id, organization_id:)]
          success = if settings.features.length == MemberFeatureRequest::Feature.values.length
            # All the features are enabled, removing any muting.
            Notifyd::Settings::RoutingSettingsService.delete(user.id, custom_field_groups)
          else
            routing_setting = Notifyd::Settings::MemberFeatureRequestsSettings.to_routing_setting(
              settings,
              user_id: user.id,
              organization_id:
            )
            Notifyd::Settings::RoutingSettingsService.replace(
              user.id,
              [routing_setting],
              custom_field_groups
            )
          end
          GitHub.dogstats.increment("notifications.settings.set_member_feature_requests.count", tags: ["success:#{success}"])
          success
        end
      end
    end

    sig { params(user: User, settings: SecurityCampaignsSettings).returns(T::Boolean) }
    def self.set_security_campaigns(user, settings)
      GitHub.tracer.in_span("set_security_campaigns", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.settings.set_security_campaigns") do
          success = Notifyd::Settings::RoutingSettingsService.replace(
            user.id,
            [Notifyd::Settings::SecurityCampaignsSettings.to_routing_setting(settings)],
            [Notifyd::Settings::SecurityCampaignsSettings.custom_field_group],
          )
          GitHub.dogstats.increment("notifications.settings.set_security_campaigns.count", tags: ["success:#{success}"])
          success
        end
      end
    end

    sig do
      params(
        user: User,
        issue_comment: T::Boolean,
        pull_request_review: T::Boolean,
        pull_request_push: T::Boolean,
        own: T::Boolean,
      ).returns(T::Boolean)
    end
    def self.set_custom_email(user, issue_comment:, pull_request_review:, pull_request_push:, own:)
      GitHub.tracer.in_span("set_custom_email", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.settings.set_custom_email") do
          response = GitHub.newsies.get_and_update_settings(user) do |settings|
            settings.notify_own_via_email = own
            settings.notify_comment_email = issue_comment
            settings.notify_pull_request_push_email = pull_request_push
            settings.notify_pull_request_review_email = pull_request_review
          end
          GitHub.dogstats.increment("notifications.settings.set_custom_email.count", tags: ["success:#{response.success?}"])
          response.success?
        end
      end
    end

    sig { params(user: User, settings: MobileSettings).returns(T::Boolean) }
    def self.set_mobile(user, settings)
      GitHub.tracer.in_span("set_mobile", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.settings.set_mobile") do
          flags = Notifyd::Flags.new(user)

          routing_settings = []
          groups = []
          if flags.push_ci_activity?
            routing_settings << Notifyd::Settings::MobileActionsSettings.to_routing_setting(settings.actions)
            groups << Notifyd::Settings::MobileActionsSettings.custom_field_group
          end
          if flags.push_releases?
            routing_settings << Notifyd::Settings::MobileReleasesSettings.to_routing_setting(settings.releases)
            groups << Notifyd::Settings::MobileReleasesSettings.custom_field_group
          end
          return true if routing_settings.empty?

          success = Notifyd::Settings::RoutingSettingsService.replace(user.id, routing_settings, groups)
          GitHub.dogstats.increment("notifications.settings.set_mobile.count", tags: ["success:#{success}"])
          success
        end
      end
    end

    # Return true if the user has email enabled in watcher settings, false
    # otherwise, including failing to retrieve the setting.
    sig { params(user: User).returns(T::Boolean) }
    def self.watcher_email?(user)
      GitHub.tracer.in_span("watcher_email", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.settings.watcher_email") do
          settings = GitHub.newsies.settings(user)&.value
          settings && settings.subscribed_email?
        end
        GitHub.dogstats.increment("notifications.settings.watcher_email.count", tags: ["result:#{result}"])
        result
      end
    end

    # Return true if the user has email enabled in participant settings, false
    # otherwise, including failing to retrieve the setting.
    sig { params(user: User).returns(T::Boolean) }
    def self.participant_email?(user)
      GitHub.tracer.in_span("participant_email", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.settings.participant_email") do
          settings = GitHub.newsies.settings(user)&.value
          settings && settings.participating_email?
        end
        GitHub.dogstats.increment("notifications.settings.participant_email.count", tags: ["result:#{result}"])
        result
      end
    end

    # Return true if the user has notifications for own activity via email
    # enabled, false otherwise, including failing to retrieve the setting.
    sig { params(user: User).returns(T::Boolean) }
    def self.own_email?(user)
      GitHub.tracer.in_span("own_email", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.settings.own_email") do
          settings = GitHub.newsies.settings(user)&.value
          settings && settings.notify_own_via_email?
        end
        GitHub.dogstats.increment("notifications.settings.own_email.count", tags: ["result:#{result}"])
        result
      end
    end

    # Return true if the user has web enabled in in any setting, false
    # otherwise, including failing to retrieve the setting.
    sig { params(user: User).returns(T::Boolean) }
    def self.web?(user)
      GitHub.tracer.in_span("web", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.settings.web") do
          settings = self.settings(user)
          next false unless settings

          !!(settings.watcher&.web || settings.participant&.web || settings.vulnerability&.web || settings.actions&.web)
        end
        GitHub.dogstats.increment("notifications.settings.web.count", tags: ["result:#{result}"])
        result
      end
    end

    sig { params(user: User, organization_id: Integer).returns(T.nilable(MemberFeatureRequestsSettings)) }
    def self.member_feature_requests(user, organization_id)
      GitHub.tracer.in_span("member_feature_requests", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.member_feature_requests") do
          Notifyd::Settings::RoutingSettingsService.get_member_feature_requests_settings(user.id, organization_id)
        end
        GitHub.dogstats.increment("notifications.settings.member_feature_requests.count", tags: ["success:#{result.present?}"])
        result
      end
    end

    # Return the settings for a user or nil on failure.
    #
    # For optimization purposes, Newsies settings can be provided if the caller
    # has already fetched them, potentially preventing a second fetch.
    sig { params(user: User, settings: T.nilable(Newsies::Settings)).returns(T.nilable(Settings)) }
    def self.settings(user, settings: nil)
      GitHub.tracer.in_span("settings", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.settings.settings") do
          if settings.nil?
            response = GitHub.newsies.settings(user)
            next nil unless response.success?
            settings = T.let(response.value, Newsies::Settings)
          end

          # TODO(abeaumont): Merge all routing settings service calls into one.
          actions = if GitHub.enterprise?
            ActionsSettings.new(
              email: settings.continuous_integration_email?,
              web: settings.continuous_integration_web?,
              failures: settings.continuous_integration_failures_only?
            )
          else
            actions = GitHub.dogstats.distribution_time("notifications.notifyd.settings.actions") do
              Notifyd::Settings::RoutingSettingsService.get_actions_settings(user.id)
            end
            GitHub.dogstats.increment("notifications.notifyd.settings.actions.count", tags: ["success:#{actions.present?}"])
            next nil if actions.nil?
            actions
          end

          security_campaigns = if !GitHub.enterprise?
            campaigns = GitHub.dogstats.distribution_time("notifications.notifyd.settings.security_campaigns") do
              Notifyd::Settings::RoutingSettingsService.get_security_campaigns_settings(user.id)
            end
            GitHub.dogstats.increment("notifications.notifyd.settings.security_campaigns.count", tags: ["success:#{campaigns.present?}"])
            next nil if campaigns.nil?
            campaigns
          end

          watcher = WatcherSettings.new(
            email: settings.subscribed_email?,
            web: settings.subscribed_web?
          )
          participant = ParticipantSettings.new(
            email: settings.participating_email?,
            web: settings.participating_web?
          )
          vulnerability = VulnerabilitySettings.new(
            email: settings.vulnerability_email?,
            web: settings.vulnerability_web?,
          )

          Settings.new(
            watcher: watcher,
            participant: participant,
            vulnerability: vulnerability,
            actions: actions,
            pull_request_review_email: settings.notify_pull_request_review_email?,
            pull_request_push_email: settings.notify_pull_request_push_email?,
            issue_comment_email: settings.notify_comment_email?,
            own_email: settings.notify_own_via_email?,
            security_campaigns: security_campaigns,
          )
        end
        GitHub.dogstats.increment("notifications.settings.settings.count", tags: ["success:#{!result.nil?}"])
        result
      end
    end

    # Return the subscription settings (watcher and participant settings) for a
    # set of users or nil on failure.
    #
    # The caller is responsible to make the batch size reasonable, please
    # contact the notifications team if in doubt.
    sig { params(user_ids: T::Array[Integer]).returns(T.nilable(T::Hash[Integer, Settings])) }
    def self.batch_subscription_settings(user_ids)
      GitHub.tracer.in_span("batch_subscription_settings", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.settings.batch_subscription_settings") do
          response = GitHub.newsies.load_user_settings(user_ids)
          next nil unless response.success?

          settings = {}
          response.value.each do |setting|
            settings[setting.id] = Settings.new(
              watcher: WatcherSettings.new(
                email: setting.subscribed_email?,
                web: setting.subscribed_web?
              ),
              participant: ParticipantSettings.new(
                email: setting.participating_email?,
                web: setting.participating_web?
              ),
            )
          end
          settings
        end
        GitHub.dogstats.increment("notifications.settings.batch_subscription_settings.count", tags: ["success:#{!result.nil?}"])
        result
      end
    end

    # NOTE(abeaumont): This is not a general purpose API method, it's only
    # intended to be called from DeliveryNotificationsJob to support deliveries
    # until they are migrated to notifyd at which point this method will be
    # removed. The implementation is tightly coupled to the current usage.
    #
    # Return a subset of settings for a sequence for a set of users or nil on
    # failure.
    #
    # The subset of settings to requests is predefined and limited to the
    # use cases needed by DeliverNotificationsJob, on purpose.
    sig { params(user_ids: T::Array[Integer], subset: T.nilable(Subset)).returns(T.nilable(T::Hash[Integer, Settings])) }
    def self.batch_settings(user_ids, subset)
      # Currently all the settings come from Newsies, even if some of them are
      # partially migrated:
      # - Actions settings are fully migrated (except for GHES), but delivery
      #   is equally migrated, so only Newsies settings may ever be needed.
      # - Watcher and participant settings are partially sync-ed but they are
      #   also available in Newsies and that's how they have been accessed.
      GitHub.tracer.in_span("batch_settings", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.settings.batch_settings") do
          response = GitHub.newsies.load_user_settings(user_ids)
          next nil unless response.success?

          settings = {}
          response.value.each do |setting|
            settings[setting.id] = case subset
            when Subset::Actions
              Settings.new(actions: ActionsSettings.new(
                email: setting.continuous_integration_email,
                web: setting.continuous_integration_web,
                failures: setting.continuous_integration_failures_only,
              ))
            when Subset::ParticipantWatcher
              Settings.new(
                participant: ParticipantSettings.new(
                  email: setting.participating_email?,
                  web: setting.participating_web?,
                ),
                watcher: WatcherSettings.new(
                  email: setting.subscribed_email?,
                  web: setting.subscribed_web?,
                ),
              )
            when Subset::ParticipantWatcherIssueCommentEmail
              Settings.new(
                participant: ParticipantSettings.new(
                  email: setting.participating_email?,
                  web: setting.participating_web?,
                ),
                watcher: WatcherSettings.new(
                  email: setting.subscribed_email?,
                  web: setting.subscribed_web?,
                ),
                issue_comment_email: setting.notify_comment_email,
              )
            when Subset::ParticipantWatcherPullRequestPushEmail
              Settings.new(
                participant: ParticipantSettings.new(
                  email: setting.participating_email?,
                  web: setting.participating_web?,
                ),
                watcher: WatcherSettings.new(
                  email: setting.subscribed_email?,
                  web: setting.subscribed_web?,
                ),
                pull_request_push_email: setting.notify_pull_request_push_email,
              )
            when Subset::ParticipantWatcherPullRequestReviewEmail
              Settings.new(
                participant: ParticipantSettings.new(
                  email: setting.participating_email?,
                  web: setting.participating_web?,
                ),
                watcher: WatcherSettings.new(
                  email: setting.subscribed_email?,
                  web: setting.subscribed_web?,
                ),
                pull_request_review_email: setting.notify_pull_request_review_email
              )
            when Subset::Vulnerability
              Settings.new(vulnerability: VulnerabilitySettings.new(
                email: setting.vulnerability_email,
                web: setting.vulnerability_web,
              ))
            when Subset::VulnerabilityWatcher
              Settings.new(
                vulnerability: VulnerabilitySettings.new(
                  email: setting.vulnerability_email,
                  web: setting.vulnerability_web,
                ),
                watcher: WatcherSettings.new(
                  email: setting.subsribed_email?,
                  web: setting.subscribed_web?,
                ),
              )
            else Settings.new
            end
          end
          settings
        end
        GitHub.dogstats.increment("notifications.settings.batch_settings.count", tags: ["success:#{!result.nil?}"])
        result
      end
    end

    # Return the settings for a user or nil on failure.
    sig { params(user: User).returns(T.nilable(MobileSettings)) }
    def self.mobile(user)
      GitHub.tracer.in_span("mobile", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.settings.mobile") do
          Notifyd::Settings::RoutingSettingsService.get_mobile_settings(user.id)
        end
        GitHub.dogstats.increment("notifications.settings.mobile.count", tags: ["success:#{result.present?}"])
        result
      end
    end

    # Supported subsets for batch_settings
    class Subset < T::Enum
      enums do
        Actions = new
        ParticipantWatcher = new
        ParticipantWatcherIssueCommentEmail = new
        ParticipantWatcherPullRequestPushEmail = new
        ParticipantWatcherPullRequestReviewEmail = new
        Vulnerability = new
        VulnerabilityWatcher = new
      end
    end

    # Plain data objects for settings and its components.
    class ParticipantSettings < T::Struct
      const :email, T::Boolean
      const :web, T::Boolean
    end

    class WatcherSettings < T::Struct
      const :email, T::Boolean
      const :web, T::Boolean
    end

    class ActionsSettings < T::Struct
      const :email, T::Boolean
      const :web, T::Boolean
      const :failures, T::Boolean
    end

    class VulnerabilitySettings < T::Struct
      const :email, T::Boolean
      const :web, T::Boolean
    end

    class SecurityCampaignsSettings < T::Struct
      const :email, T::Boolean
    end

    class Settings < T::Struct
      const :watcher, T.nilable(WatcherSettings)
      const :participant, T.nilable(ParticipantSettings)
      const :vulnerability, T.nilable(VulnerabilitySettings)
      const :actions, T.nilable(ActionsSettings)
      const :pull_request_push_email, T.nilable(T::Boolean)
      const :pull_request_review_email, T.nilable(T::Boolean)
      const :issue_comment_email, T.nilable(T::Boolean)
      const :own_email, T.nilable(T::Boolean)
      const :security_campaigns, T.nilable(SecurityCampaignsSettings)
    end

    class MobileActionsSettings < T::Struct
      const :push, T::Boolean
      const :failures, T::Boolean
    end

    class MobileReleasesSettings < T::Struct
      const :push, T::Boolean
    end

    class MobileSettings < T::Struct
      const :actions, MobileActionsSettings
      const :releases, MobileReleasesSettings
    end

    class MemberFeatureRequestsSettings < T::Struct
      const :features, T::Array[MemberFeatureRequest::Feature]
    end
  end
end
