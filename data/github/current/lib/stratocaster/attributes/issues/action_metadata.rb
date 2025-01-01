# typed: false
# frozen_string_literal: true

class Stratocaster::Attributes::Issues
  module ActionMetadata
    DISPATCHABLE_ACTIONS = %i(opened closed reopened labeled).freeze

    def dispatchable_action?
      DISPATCHABLE_ACTIONS.include? @action
    end

    private

    def metadata_from_payload(payload)
      case payload[:action]
      when :labeled, :unlabeled
        payload.slice(:label)
      when :assigned, :unassigned
        expand_metadata(assignee_id: payload.dig(:assignee, :id))
      when :review_requested, :review_request_removed
        payload.slice payload.has_key?(:requested_team) ? :requested_team : :requested_reviewer
      else
        {}
      end
    end

    def expand_metadata(assignee_id: nil, label_id: nil, subject_id: nil, subject_type: nil)
      case @action
      when :labeled, :unlabeled
        label = Label.find_by_id label_id

        if label
          { label: Api::Serializer.serialize(:label_hash, label, repo: label.repository) }
        else
          {}
        end
      when :assigned, :unassigned
        assignee = User.find_by_id assignee_id
        if assignee
          { assignee: Api::Serializer.serialize(:user_hash, assignee) }
        else
          {}
        end
      when :review_requested, :review_request_removed
        if subject_type == "Team"
          team = Team.find_by_id subject_id
          team ? { requested_team: Api::Serializer.serialize(:team_hash, team) } : {}
        else
          user = User.find_by_id subject_id
          user ? { requested_reviewer: Api::Serializer.serialize(:user_hash, user) } : {}
        end
      else
        {}
      end
    end
  end
end
