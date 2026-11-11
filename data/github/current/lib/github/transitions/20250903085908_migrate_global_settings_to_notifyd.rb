# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    NS = Notifications::Settings

    class Settings < T::Struct
      const :watcher, NS::WatcherSettings
      const :participant, NS::ParticipantSettings
      const :vulnerability, NS::VulnerabilitySettings
      const :issue_comment_email, T::Boolean
      const :pull_request_review_email, T::Boolean
      const :pull_request_push_email, T::Boolean
      const :own_email, T::Boolean
    end

    class MigrateGlobalSettingsToNotifyd < Base
      class NotificationUserSetting < ApplicationRecord::Domain::Notifications
        self.table_name = :notification_user_settings
      end

      iterate_over :database_table, params: {
        model_class: NotificationUserSetting,
        columns: [
          :participating_web,
          :participating_email,
          :subscribed_web,
          :subscribed_email,
          :vulnerability_email,
          :vulnerability_web,
          :notify_comment_email,
          :notify_pull_request_review_email,
          :notify_pull_request_push_email,
          :notify_own_via_email,
        ],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        return if GitHub.enterprise?

        log("Processing batch of size #{items.size}, for users between #{items.keys.min} and #{items.keys.max}")
        users = User.where(id: items.keys.uniq).index_by(&:id)
        items.each do |id, columns|
          log("Processing item #{id} with columns: #{columns}")
          user = users[id]
          if user.present? && user.login != "ghost"
            settings = Settings.new(
              participant: NS::ParticipantSettings.new(email: columns[:participating_email], web: columns[:participating_web]),
              watcher: NS::WatcherSettings.new(email: columns[:subscribed_email], web: columns[:subscribed_web]),
              vulnerability: NS::VulnerabilitySettings.new(email: columns[:vulnerability_email], web: columns[:vulnerability_web]),
              issue_comment_email: columns[:notify_comment_email],
              pull_request_review_email: columns[:notify_pull_request_review_email],
              pull_request_push_email: columns[:notify_pull_request_push_email],
              own_email: columns[:notify_own_via_email],
            )
            if arguments[:only_mismatches]
              if same?(settings, Notifyd::Settings::RoutingSettingsService.settings(id.to_i))
                log("Ignore matching settings for user: #{id}")
                next
              end
              log("Mismatched settings for user: #{id}")
            end
            save(user.id, settings)
          end
        end
      end

      private

      sig { params(user_id: Integer, settings: Settings).void }
      def save(user_id, settings)
        log("Save settings for user user: #{user_id}")
        begin
          routing_settings = [
            Notifyd::Settings::ParticipantSettings.to_routing_setting(settings.participant),
            Notifyd::Settings::WatcherSettings.to_routing_setting(settings.watcher),
            Notifyd::Settings::VulnerabilitySettings.to_routing_setting(settings.vulnerability),
          ]

          unless settings.issue_comment_email
            routing_settings << Notifyd::Settings::IssueCommentsEmailSettings.to_routing_setting
          end

          unless settings.pull_request_review_email
            routing_settings << Notifyd::Settings::PullRequestReviewsEmailSettings.to_routing_setting
          end

          unless settings.pull_request_push_email
            routing_settings << Notifyd::Settings::PullRequestPushesEmailSettings.to_routing_setting
          end

          if settings.own_email
            routing_settings << Notifyd::Settings::SelfActivityEmailSettings.to_routing_setting(user_id: user_id)
          end

          groups = [
            Notifyd::Settings::ParticipantSettings.custom_field_group,
            Notifyd::Settings::WatcherSettings.custom_field_group,
            Notifyd::Settings::VulnerabilitySettings.custom_field_group,
            Notifyd::Settings::IssueCommentsEmailSettings.custom_field_group,
            Notifyd::Settings::PullRequestReviewsEmailSettings.custom_field_group,
            Notifyd::Settings::PullRequestPushesEmailSettings.custom_field_group,
            Notifyd::Settings::SelfActivityEmailSettings.custom_field_group,
          ]

          if dry_run?
            log("Skip: saving settings for user: #{user_id}")
            return
          end

          if Notifyd::Settings::RoutingSettingsService.replace(user_id, routing_settings, groups)
            log("Success: saved settings for user: #{user_id}")
          else
            # Routing settings service returns false in case if error
            log("Error: Failed to save settings for user: #{user_id}")
          end
        rescue => e # rubocop:todo Lint/GenericRescue
          log("Error: Failed to make call to Notifyd for user: #{user_id}, error: #{e}")
        end
      end

      sig { params(newsies: Settings, notifyd: T.nilable(NS::Settings)).returns(T::Boolean) }
      def same?(newsies, notifyd)
        if notifyd.nil?
          log("Mismatch: notifyd nil")
          return false
        end
        if newsies.participant.email != notifyd.participant&.email
          log("Mismatch: participant_email #{newsies.participant.email} != #{notifyd.participant&.email}")
          return false
        end
        if newsies.participant.web != notifyd.participant&.web
          log("Mismatch: participant_web #{newsies.participant.web} != #{notifyd.participant&.web}")
          return false
        end
        if newsies.watcher.email != notifyd.watcher&.email
          log("Mismatch: watcher_email #{newsies.watcher.email} != #{notifyd.watcher&.email}")
          return false
        end
        if newsies.watcher.web != notifyd.watcher&.web
          log("Mismatch: watcher_web #{newsies.watcher.web} != #{notifyd.watcher&.web}")
          return false
        end
        if newsies.vulnerability.email != notifyd.vulnerability&.email
          log("Mismatch: vulnerability_email #{newsies.vulnerability.email} != #{notifyd.vulnerability&.email}")
          return false
        end
        if newsies.vulnerability.web != notifyd.vulnerability&.web
          log("Mismatch: vulnerability_web #{newsies.vulnerability.web} != #{notifyd.vulnerability&.web}")
          return false
        end
        if newsies.issue_comment_email != notifyd.issue_comment_email
          log("Mismatch: issue_comment_email #{newsies.issue_comment_email} != #{notifyd.issue_comment_email}")
          return false
        end
        if newsies.pull_request_review_email != notifyd.pull_request_review_email
          log("Mismatch: pull_request_review_email #{newsies.pull_request_review_email} != #{notifyd.pull_request_review_email}")
          return false
        end
        if newsies.pull_request_push_email != notifyd.pull_request_push_email
          log("Mismatch: pull_request_push_email #{newsies.pull_request_push_email} != #{notifyd.pull_request_push_email}")
          return false
        end
        if newsies.own_email != notifyd.own_email
          log("Mismatch: own_email #{newsies.own_email} != #{notifyd.own_email}")
          return false
        end
        true
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # Default arguments parsed for any instance:
  #
  # - `write`              - Enables writes, defaults to false,
  #                          pass `--write` to enable.
  # - `verbose`            - Log verbose output, defaults to true.
  # - `start_id`           - ID to start processing, default for database
  #                          table iterations is `MIN(table.id)`.
  # - `end_id`             - ID to end processing, default for database
  #                          table iterations is `MAX(table.id)`.
  # - `read_batch_size`    - Number of rows to read at a time, default for
  #                          database table iterations is
  #                          `DEFAULT_READ_BATCH_SIZE`.
  # - `process_batch_size` - Number of rows to process at a time, default for
  #                          database table iterations is
  #                          `DEFAULT_PROCESS_BATCH_SIZE`.
  # - `workers`            - Worker count for parallelization, default for
  #                          custom iterators is 1 (disabling
  #                          parallelization). For databse table iterations,
  #                          the default is `DEFAULT_WORKER_COUNT` defined in
  #                          the `Iterators::DatabaseTable` class. The maximum
  #                          is `MAX_WORKER_COUNT` defined in the same class.
  # - `only_mismatches`    - Enables limiting writes for settings that don't match,
  #                          pass `--only_mistmatches true` to enable.
  args = GitHub::Transitions::Arguments.parse(ARGV,
    additional_arguments: %w(only_mismatches)
  )

  GitHub::Transitions::MigrateGlobalSettingsToNotifyd.new(args).run
end
