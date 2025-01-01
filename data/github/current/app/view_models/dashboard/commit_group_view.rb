# typed: true
# frozen_string_literal: true

module Dashboard
  class CommitGroupView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    MAX_COMMITS_DISPLAYED = 2
    REF_REGEXP = /refs\/(remotes|heads|tags)\//

    attr_reader :ref, :events

    delegate :pusher_is_only_committer, to: :push_event_view

    def additional_commits_count
      commits.size - MAX_COMMITS_DISPLAYED
    end

    def visible_commits
      @visible_commits ||= commits.take(MAX_COMMITS_DISPLAYED).map do |commit|
        Events::PushView::CommitView.from(push_event_view, commit)
      end
    end

    def comparison_url
      sorted_events = events.sort_by(&:created_at)
      before = sorted_events.first.before_sha
      head = sorted_events.last.head_sha

      if before.present? && head.present?
        "/#{repo_nwo}/compare/#{before[0, 10]}...#{head[0, 10]}"
      end
    end

    def count
      events.sum { |event| event.commits.size }
    end

    def formatted_ref
      ref.sub(REF_REGEXP, "")
    end

    def instrument_view(user, organization)
      first_event.instrument_view(user, organization, grouped: true)
    end

    def push_event_view
      @push_event_view ||= Events::View.for(first_event)
    end

    def view_attributes(org_id: nil, viewer:)
      event_details = { grouped: true }
      NewsFeedAnalytics.event_view_attributes(first_event, event_details: event_details,
                                              org_id: org_id, viewer_id: viewer&.id)
    end

    private

    def first_event
      events.first
    end

    def commits
      @commits ||= events.flat_map(&:commits)
    end

    def repo_nwo
      first_event.repo_nwo
    end
  end
end
