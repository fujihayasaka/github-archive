# typed: true
# frozen_string_literal: true

module Insights
  class Access
    sig { params(actor: T.untyped).returns(T::Boolean) }
    def self.enabled?(actor)
      false
    end

    def self.enabled_staging?(actor)
      FeatureFlag.vexi.enabled?(:insights_enabled_staging, actor, default: false)
    end

    def self.publish_enabled?(actor)
      FeatureFlag.vexi.enabled?(:insights_publish_enabled, actor, default: false)
    end

    def self.actions_enabled?(actor)
      FeatureFlag.vexi.enabled?(:insights_actions, actor, default: false)
    end

    def self.pull_requests_publish_enabled?(actor)
      FeatureFlag.vexi.enabled?(:insights_pull_requests_publish, actor, default: false)
    end

    def self.pull_request_reviews_publish_enabled?(actor)
      FeatureFlag.vexi.enabled?(:insights_pull_request_reviews_publish, actor, default: false)
    end

    def self.assignments_publish_enabled?(actor)
      FeatureFlag.vexi.enabled?(:insights_assignments_publish, actor, default: false)
    end

    def self.draft_assignments_publish_enabled?(actor)
      FeatureFlag.vexi.enabled?(:insights_draft_assignments_publish, actor, default: false)
    end

    def self.users_publish_enabled?(actor)
      !GitHub.enterprise?
    end

    def self.formatted_timestamp_publish_enabled?(actor)
      FeatureFlag.vexi.enabled?(:insights_formatted_timestamp_publish, actor, default: false)
    end
  end
end
