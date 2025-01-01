# typed: true
# frozen_string_literal: true

module Notifyd
  # This class tries to aggregate all the available feature flags used by
  # `notifyd`, and serves as an entrypoint for them.
  #
  # New feature flags should be added here, documented, and removed when
  # unused.
  #
  # If you find a feature flag related  with notifyd in the wild, please add it
  # here!
  class Flags

    Actor = T.type_alias { T.any(String, Integer, ::User) }

    # Can be initialized as
    #
    # - Flags.new => Will use no actor (for globally toggleable flags)
    # - Flags.new(1) => Will use User.new(id: 1) as the actor
    # - Flags.new("1") => Will use User.new(id: "1") as the actor
    # - Flags.new(current_user) => Where current_user is an `User` object. Will
    #   use such user as the actor
    sig { params(actor: T.nilable(Actor)).void }
    def initialize(actor = nil)
      @actor =
        case actor
        when ::User
          actor
        when Integer, String
          User.new(id: actor)
        else
          nil
        end
    end

    # NOTE: (@franciscoj 30/11/2022) added for:
    #
    # Controls whether the settings for CI activity push notifications are
    # read/written in notifyd or only defaults are returned instead.
    #
    # The mobile team uses them to gradually rollout this new push
    # notification.
    sig { returns(T::Boolean) }
    def push_ci_activity?
      FeatureFlag.vexi.enabled?(:notifyd_mobile_push_ci_activity, actor, default: true)
    end

    # NOTE: (@mrtazz 16/12/2022) added for:
    # https://github.com/github/notifyd/issues/2064
    #
    # Controls whether the settings for sending notifications for
    # participating activity should be written to notify
    def enable_issue_thread_subscriptions?
      FeatureFlag.vexi.enabled?(:notifyd_enable_issue_thread_subscriptions, actor, default: false)
    end

    # This flag was added on 14/11/2022.
    # It controls whether email and web notifications for issues should be sent
    # via notifyd, and whether notifyd should be the primary source of truth
    # for issues related subscriptions and settings.
    def enable_issue_notifications?
      FeatureFlag.vexi.enabled?(:notifyd_issue_watch_activity_notify, actor, default: false)
    end

    # NOTE(abeaumont): This flag was added on 26/02/2024.
    # It controls whether notifyd delivers email/web notifications for pull requests.
    # See https://github.com/github/github/pull/314072
    def enable_pull_request_notifications?
      FeatureFlag.vexi.enabled?(:notifyd_pull_request_notify_email_and_web, actor, default: false)
    end

    # NOTE: (@stevepopovich 12/7/2023) added for:
    #
    # Controls whether the settings for repository releases push notifications are
    # read/written in notifyd or only defaults are returned instead.
    #
    # The mobile team uses them to gradually rollout this new push
    # notification.
    sig { returns(T::Boolean) }
    def push_releases?
      FeatureFlag.vexi.enabled?(:notifyd_mobile_push_watched_activity, actor, default: false)
    end

    # This flag was added on 20/01/2023
    #
    # This flag enables label subscriptions functionality: ui in watch dropdown
    # for a repository and a related backend logic
    #
    # NOTE: This check also uses the repository in order to filter by its organization
    sig { params(repository: T.nilable(Repository)).returns(T::Boolean) }
    def label_subscriptions?(repository)
      return true if FeatureFlag.vexi.enabled?(:notifyd_label_subscriptions, actor, default: false)
      return false unless repository

      repository.owner&.organization? &&
        FeatureFlag.vexi.enabled?(:notifyd_label_subscriptions, repository.owner, default: false) &&
        T.cast(repository.owner, T.nilable(Organization))&.member?(actor)
    end

    private

    sig { returns(T.nilable(::User)) }
    attr_reader :actor
  end
end
