# typed: true
# frozen_string_literal: true

module Insights
  class Access
    sig { params(actor: T.untyped).returns(T::Boolean) }
    def self.enabled?(actor)
      false
    end

    def self.enabled_staging?(actor)
      GitHub.flipper[:insights_enabled_staging].enabled?(actor)
    end

    def self.publish_enabled?(actor)
      GitHub.flipper[:insights_publish_enabled].enabled?(actor)
    end

    def self.actions_enabled?(actor)
      GitHub.flipper[:insights_actions].enabled?(actor)
    end

    def self.pull_requests_publish_enabled?(actor)
      GitHub.flipper[:insights_pull_requests_publish].enabled?(actor)
    end

    def self.pull_request_reviews_publish_enabled?(actor)
      GitHub.flipper[:insights_pull_request_reviews_publish].enabled?(actor)
    end

    def self.assignments_publish_enabled?(actor)
      GitHub.flipper[:insights_assignments_publish].enabled?(actor)
    end

    def self.draft_assignments_publish_enabled?(actor)
      GitHub.flipper[:insights_draft_assignments_publish].enabled?(actor)
    end

    def self.users_publish_enabled?(actor)
      !GitHub.enterprise?
    end

    def self.formatted_timestamp_publish_enabled?(actor)
      GitHub.flipper[:insights_formatted_timestamp_publish].enabled?(actor)
    end
  end
end
