# typed: true
# frozen_string_literal: true

module CommandPalette
  module Icons
    class Octicon < CommandPalette::Icon
      include OcticonsHelper

      # Fetch appropriate icon for given object. When no icon is found, returns
      # default icon. Right now, supports issues and pull requests.
      def self.for(object)
        icon =
          case object
          when Issue then for_issue(object)
          when PullRequest then for_pull_request(object)
          when Repository then for_repository(object)
          when Discussion then for_discussion(object)
          end

        icon || default_icon
      end

      def self.default_icon
        new(name: "dash")
      end

      def self.for_issue(issue)
        return self.for(issue.pull_request) if issue.pull_request?

        case issue.state
        when "open"
          Icons::Octicon.issue_open
        when "closed"
          Icons::Octicon.issue_closed
        end
      end

      def self.for_pull_request(pull_request)
        return git_pull_request_draft if pull_request.draft?

        case pull_request.state
        when :open then git_pull_request_open
        when :closed then git_pull_request_closed
        when :merged then git_pull_request_merged
        end
      end

      def self.for_repository(repository)
        if repository.public?
          new(name: "repo")
        else
          private_repo
        end
      end

      def self.for_discussion(discussion)
        return discussion_default unless discussion.closed?

        reason = discussion_state_reasons_by_value[discussion.state_reason]
        new(name: reason.octicon, classes: "color-fg-#{reason.octicon_color}")
      end

      # These are some named octicons which will produce colour correct icons.
      #
      # Example usage:
      # CommandPalette::Icons::Octicon.issue_open # => produces a green open issue octicon
      def self.copy
        new(name: "copy")
      end

      def self.discussion_default
        new(name: "comment-discussion")
      end

      def self.git_pull_request_closed
        new(name: "git-pull-request-closed", classes: "closed")
      end

      def self.git_pull_request_draft
        new(name: "git-pull-request-draft", classes: "color-fg-muted")
      end

      def self.git_pull_request_merged
        new(name: "git-merge", classes: "merged")
      end

      def self.git_pull_request_open
        new(name: "git-pull-request", classes: "open")
      end

      def self.git_pull_request_ready
        new(name: "code-review")
      end

      def self.issue_open
        new(name: "issue-opened", classes: "open")
      end

      def self.issue_closed
        new(name: "issue-closed", classes: "closed")
      end

      def self.private_repo
        new(name: "lock", classes: "repo-private-icon")
      end

      private_class_method def self.discussion_state_reasons_by_value
        @discussion_state_reasons_by_value ||= Closables::BaseComponent::DISCUSSION_REASONS.index_by(&:value)
      end

      attr_reader :name, :classes

      def initialize(name:, classes: "color-fg-muted")
        super(type: :octicon)
        @name = name
        @classes = classes
      end

      def icon
        octicon(name, height: 16, class: classes)
      end

      def id
        "#{name}-#{classes}"
      end

      def as_json(*)
        {
          type: type,
          id: id,
        }
      end
    end
  end
end
