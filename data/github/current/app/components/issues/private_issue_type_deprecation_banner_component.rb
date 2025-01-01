# typed: strict
# frozen_string_literal: true

module Issues
  class PrivateIssueTypeDeprecationBannerComponent < ApplicationComponent
    include ApplicationComponent::Rescuable
    include GitHub::Memoizer
    include ResilienceHelper

    DEPRECATION_NOTICE = "private_issue_type_deprecation_notice"

    rescue_from ActiveRecord::ActiveRecordError, with: :nothing

    sig { returns(String) }
    def banner_message
      "Issue types for private repositories only will be retired and removed on March 26, 2025. Please unselect the “Private repositories only” setting to continue using these issue types."
    end

    sig { returns(String) }
    def learn_more_link_text
      "See the changelog."
    end

    sig { returns(String) }
    def learn_more_link
      "https://gh.io/private-issue-types-changelog"
    end

    sig { returns(User) }
    attr_reader :org

    private

    sig { returns(T.nilable(User)) }
    attr_reader :user

    sig { params(org: User, user: T.nilable(User)).void }
    def initialize(org:, user:)
      @org = org
      @user = user
    end

    sig { returns(T::Boolean) }
    def has_private_issue_types?
      all_issue_types = org.issue_types
      all_issue_types.any?(&:private?)
    end

    sig { returns(T.nilable(T::Boolean)) }
    def has_dismissed?
      user&.dismissed_notice?(DEPRECATION_NOTICE)
    end

    sig { returns(T::Boolean) }
    def render?
      return false if GitHub.enterprise?
      return false unless user&.feature_enabled?("issue_types_announce_private_deprecation")
      return false unless org.adminable_by?(user)
      return false unless org.issue_types_enabled?
      return false if has_dismissed?

      return false unless has_private_issue_types?

      true
    end
  end
end
