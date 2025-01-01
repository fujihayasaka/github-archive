# typed: true
# frozen_string_literal: true

# Decorates a Stratocaster::Attributes::Issues event with view logic.
#
# Examples
#
#   # equivalent ways to render the event's html
#   render_event(Events::IssuesView.new(event))
#
#   # or
#   render_event(Events::View.for(event))
module Events
  class IssuesView < View
    BODY_MAX_LENGTH = 150
    NON_TIMELINE_ACTIONS = %w(assigned unassigned unlabeled).freeze

    def should_render?
      return false if NON_TIMELINE_ACTIONS.include?(action)
      super
    end

    def title_text
      parts = if labeled_event?
        [
          actor_text,
          actor_bot_identifier_text,
          action,
          "an issue with",
          T.unsafe(self).label_name,
          "in",
          repo_text,
        ]
      else
        [actor_text, actor_bot_identifier_text, action, "an issue in", repo_text]
      end
      parts.compact.join(" ")
    end

    def labeled_event?
      Stratocaster::Event.labeled_event?(action)
    end

    # Returns the subject String of this issue.
    def subject
      case payload[:issue]
      when Hash
        payload[:issue][:title]
      else
        issue.try(:title)
      end
    end

    # Returns the String name of the event's octicon for display in the view template
    def octicon_name
      if Stratocaster::Event.labeled_event?(action)
        if T.unsafe(self).issue_state == "open"
          "issue-opened"
        elsif T.unsafe(self).issue_state == "closed"
          "issue-closed"
        end
      else
        "issue-#{action}"
      end
    end

    # The first 150 characters of the issue's HTML body.
    #
    # Returns a String or nil.
    def formatted_issue_body
      if T.unsafe(self).issue_body.present?
        truncate_html(T.unsafe(self).issue_body, BODY_MAX_LENGTH)
      end
    end

    # Public: Returns the Integer issue number that users reference, not the issue's
    # database id.
    def number
      case payload[:issue]
      when Hash
        payload[:issue][:number]
      else
        payload[:number] || issue.try(:number)
      end
    end

    # Public: Returns the String URL to this issue's page.
    def url
      "/#{T.unsafe(self).repo_nwo}/issues/#{number}"
    end

    def icon
      "issues_#{action}"
    end

    private

    # Do not call this. We need to update old issue events to the latest
    # payload schema so this database query can be removed.
    #
    # Deal with multiple payload versions:
    #
    #     {:issue => 123}
    #     {:issue => {:id => 123}}
    #
    # Returns an Issue, or nil.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def issue
      @issue ||= unless defined?(@issue)
        case payload[:issue]
        when Integer
          Issue.find_by(id: payload[:issue])
        when Hash
          Issue.find_by(id: payload[:issue][:id])
        else
          nil
        end
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator
  end
end
