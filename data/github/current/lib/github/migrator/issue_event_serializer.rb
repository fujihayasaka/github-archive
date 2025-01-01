# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class IssueEventSerializer < BaseSerializer
      def scope
        IssueEvent.preload(:actor, :commit_repository, issue: :pull_request, referencing_issue: :pull_request)
      end

      def as_json(options = {})
        hash = {
          type: "issue_event",
          url: url,
        }

        if pull_request
          hash[:pull_request] = pull_request
        else
          hash[:issue] = issue
        end

        hash.merge!({ actor: actor, event: event })
        hash.merge!(issue_event_meta_data)
        hash[:created_at] = created_at
        hash
      end

      private

      def issue
        url_for_model(model.issue)
      end

      def pull_request
        url_for_model(model.issue.pull_request)
      end

      def actor
        url_for_model(model.actor)
      end

      def subject
        url_for_model(model.subject)
      end

      def event
        model.event
      end

      def issue_event_meta_data
        hash = {}

        # ick
        if model.label_id
          if label = Label.where(id: model.label_id.to_i).first
            hash[:label] = url_for_model(label)
          end
        end

        [:label_name, :label_color, :label_text_color,
         :milestone_title, :title_was, :title_is, :deployment_id,
         :ref, :before_commit_oid, :after_commit_oid].each do |key|

          if value = model.send(key)
            hash[key] = value
          end
        end

        if model.subject_id
          hash[:subject] = subject
          hash[:actor] = actor

          if model.subject_type == "Project"
            hash[:column_name] = model.column_name
            hash[:previous_column_name] = model.previous_column_name
          end
        end

        if referencing_issue = model.referencing_issue
          if referencing_issue.pull_request
            hash[:referencing_pull_request] = url_for_model(referencing_issue.pull_request)
          else
            hash[:referencing_issue] = url_for_model(referencing_issue)
          end
        end

        if model.commit_id
          hash[:commit_id] = model.commit_id
        end

        if model.commit_repository
          hash[:commit_repository] = url_for_model(model.commit_repository)
        end

        if model.lock_reason
          hash[:lock_reason] = model.lock_reason
        end

        if model.milestone_id
          milestone = Milestone.find_by(id: model.milestone_id)
          hash[:milestone_number] = milestone.number if milestone
        end

        hash
      end

      def update_model_before_serialization(model)
        model.tap do |m|
          m.actor = User.ghost unless m.actor
        end
      end
    end
  end
end
