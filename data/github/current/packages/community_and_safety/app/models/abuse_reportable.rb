# typed: false
# frozen_string_literal: true

module AbuseReportable
  extend ActiveSupport::Concern

  included do
    has_many :abuse_reports, as: :reported_content
  end

  def async_viewer_relationship(viewer)
    return Promise.resolve(:none) unless viewer && respond_to?(:repository)
    return Promise.resolve(@viewer_relationship) if defined?(@viewer_relationship)

    @viewer_relationship = async_repository.then do |repository|
      repository.async_user_relationship(viewer)
    end
  end

  # Public: The number of abuse reports for this content.
  #
  # Returns an Integer.
  def report_count
    return @report_count if defined? @report_count
    async_report_count.sync
  end

  # Public: The number of abuse reports for this content.
  #
  # Returns a Promise<Integer>.
  def async_report_count
    async_abuse_reports.then do |reports|
      reports.count
    end
  end

  # Public: The most frequent reason this content was reported.
  #
  # Returns a String|nil.
  def top_report_reason
    return @top_report_reason if defined? @top_report_reason
    async_top_report_reason.sync
  end

  # Public: The most frequent reason this content was reported.
  #
  # Returns a Promise<String|nil>.
  def async_top_report_reason
    Platform::Loaders::TopReportedAbuseReason.load(self).then do |reason|
      next unless reason.present?
      reason.humanize(capitalize: false)
    end
  end

  # Public: The timestamp of the last abuse report received for this content.
  #
  # Returns an ActiveSupport::TimeWithZone|nil.
  def last_reported_at
    return @last_reported_at if defined? @last_reported_at
    async_last_reported_at.sync
  end

  # Public: The timestamp of the last abuse report received for this content.
  #
  # Returns a Promise<ActiveSupport::TimeWithZone|nil>.
  def async_last_reported_at
    Platform::Loaders::LastAbuseReportedAt.load(self)
  end

  # Public: Defaults false, but is overridden in classes that belong to top-level content that can be marked as spam:
  # IssueComment, DiscussionComment, PullRequestReview, and PullRequestReviewComment
  #
  # Returns a Boolean.
  def belongs_to_spammy_content?
    false
  end

  # Public: Indicates if a viewer is able to report this content.
  #         See https://github.com/github/ce-community-and-safety/issues/1338#issuecomment-548590108
  #         for decision tree on who can report in what circumstances
  #
  # viewer - The User to check.
  #
  # Returns a Promise<Boolean>.
  def async_viewer_can_report?(viewer)
    return Promise.resolve(false) unless GitHub.can_report?

    return Promise.resolve(false) unless viewer
    return Promise.resolve(false) unless self.respond_to?(:repository)
    return Promise.resolve(false) unless self.is_a?(UserContentEditable)
    return Promise.resolve(false) unless self.respond_to?(:user_id)

    @async_viewer_can_report ||= {}
    return @async_viewer_can_report[viewer] if @async_viewer_can_report.has_key?(viewer)

    @async_viewer_can_report[viewer] = async_repository.then do |repository|
      repository.async_user_can_report?(viewer).then do |user_can_report_on_repo|
        next user_can_report_on_repo unless user_can_report_on_repo.nil?

        async_user.then do |author|
          (author ? author.async_blocking?(viewer) : Promise.resolve(false)).then do |viewer_blocked_by_author|
            next false if viewer_blocked_by_author

            repository.async_contributor?(viewer).then do |contributor|
              next true if contributor
              next async_edited_by_another_user? if viewer.id == author&.id
              next true if repository.tiered_reporting_all_users_explicitly_enabled?

              false
            end
          end
        end
      end
    end
  end

  # Public: Indicates if a specified viewer is able to report this content to a repository maintainer.
  #
  # viewer - The User to check.
  #
  # Returns a Promise<Boolean>.
  def async_viewer_can_report_to_maintainer?(viewer)
    @async_viewer_can_report_to_maintainer ||= {}
    return @async_viewer_can_report_to_maintainer[viewer] if @async_viewer_can_report_to_maintainer.has_key?(viewer)

    @async_viewer_can_report_to_maintainer[viewer] = async_viewer_can_report?(viewer).then do |can_report|
      next false unless can_report

      # Those who can report may report to maintainer if the repo has the feature enabled,
      # the viewer is not an admin, and the repo is owned by an organization
      (self.is_a?(PullRequest) ? self.async_issue : Promise.resolve(self)).then do |object|
        object.async_repository.then do |repository|
          next false if !repository.tiered_reporting_explicitly_enabled? && !repository.tiered_reporting_all_users_explicitly_enabled?

          repository.cached_async_adminable_by?(viewer).then do |adminable|
            next false if adminable

            async_user.then do |author|
              repository.cached_async_adminable_by?(author).then do |adminable|
                next false if adminable

                repository.async_owner.then do |owner|
                  next false unless owner.present?
                  owner.organization?
                end
              end
            end
          end
        end
      end
    end
  end
end
