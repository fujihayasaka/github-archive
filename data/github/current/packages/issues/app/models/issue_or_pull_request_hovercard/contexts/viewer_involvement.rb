# typed: true
# frozen_string_literal: true

module IssueOrPullRequestHovercard::Contexts
  class ViewerInvolvement < Hovercard::Contexts::Base
    # Public: Build a ViewerInvolvement context, if the viewer is involved with
    # the issue or pull request.
    #
    # Returns a Promise that resolves to either a ViewerInvolvement object, or
    # nil.
    def self.async_resolve(issue_or_pull_request:, viewer:)
      Resolver.new(issue_or_pull_request: issue_or_pull_request, viewer: viewer).async_resolve
    end

    attr_reader :viewer

    def initialize(viewer, issue_or_pull_request, assigned:, authored:, commented:, mentioned:)
      @viewer = viewer
      @issue_or_pull_request = issue_or_pull_request
      @assigned = assigned
      @authored = authored
      @commented = commented
      @mentioned = mentioned
    end

    def message
      fragments = []
      fragments << "are assigned to" if assigned
      fragments << "were mentioned on" if mentioned
      fragments << "commented on" if commented && fragments.length < 2
      fragments << "opened" if authored && fragments.length < 2

      "You #{fragments.to_sentence} this #{@issue_or_pull_request.pull_request? ? 'pull request' : "issue"}"
    end

    def octicon
      "person"
    end

    def platform_type_name
      "ViewerHovercardContext"
    end

    private

    attr_reader :assigned, :authored, :commented, :mentioned

    class Resolver
      def initialize(issue_or_pull_request:, viewer:)
        @issue_or_pull_request = issue_or_pull_request
        @viewer = viewer
      end

      def async_resolve
        Promise.all([
          record.async_commented_on_by?(viewer),
          Platform::Loaders::ActiveRecordAssociation.load_all(record, [:assignee, :assignees, :user]),
        ]).then do |has_commented, _|
          involvement = {
            assigned: record.assigned_to?(viewer),
            authored: record.user == viewer,
            commented: has_commented,
            mentioned: record.mentioned_user_ids.include?(viewer.id),
          }

          if involvement.values.any?
            ViewerInvolvement.new(viewer, issue_or_pull_request, **involvement)
          end
        end
      end

      private

      attr_reader :issue_or_pull_request, :viewer

      def record
        issue_or_pull_request.to_issue
      end
    end
  end
end
