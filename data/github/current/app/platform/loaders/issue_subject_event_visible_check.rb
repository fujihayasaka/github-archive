# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueSubjectEventVisibleCheck < Platform::Loader
      include Scientist

      def self.load(viewer, issue_event_id, cap_filter: nil)
        self.for(viewer, cap_filter).load(issue_event_id)
      end

      def initialize(viewer, cap_filter)
        @viewer = viewer
        @cap_filter = cap_filter
      end

      def fetch(issue_event_ids)
        subject_issue_id_by_issue_event_id = ::IssueEventDetail.where({
          issue_event_id: issue_event_ids,
          subject_type: "Issue",
        }).pluck(:issue_event_id, :subject_id).to_h

        result = Hash.new(false)

        Promise.all(
          subject_issue_id_by_issue_event_id.map do |issue_event_id, subject_issue_id|
            Platform::Loaders::ActiveRecord.load(::Issue, subject_issue_id).then do |subject_issue|
              [issue_event_id, subject_issue]
            end
          end
        ).then do |subject_issues_by_issue_event_id|
          subject_issues_by_issue_event_id = subject_issues_by_issue_event_id.to_h

          if @cap_filter
            subject_issues = subject_issues_by_issue_event_id.values
            cap_filtered_subject_issues = @cap_filter.authorized_resources(subject_issues).to_set
            subject_issues_by_issue_event_id = subject_issues_by_issue_event_id.filter { |_, subject_issue| cap_filtered_subject_issues.include?(subject_issue) }
          end

          Promise.all(subject_issues_by_issue_event_id.map do |issue_event_id, subject|
            next false unless subject
            subject.async_repository.then do |repo|
              unless violated_oauth_app_policy?(@viewer, repo)
                subject.async_readable_by?(@viewer).then do |visible|
                  result[issue_event_id] = visible
                end
              end
            end
          end)
        end.sync

        result
      end

      def violated_oauth_app_policy?(viewer, repository)
        return false unless viewer&.using_oauth_application? && GitHub.oauth_application_policies_enabled?
        return false unless repository

        !OauthApplicationPolicy::Application.new(repository, viewer.oauth_application).satisfied?
      end
    end
  end
end
