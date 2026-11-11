# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class HideContent < Platform::Mutations::Base
      docs_category :meta
      description "Hides the body of a top-level content object (Issue, Gist) as a moderation action."

      visibility :internal

      minimum_accepted_scopes %w[repo gist]

      argument :subject_id, ID, "The Node ID of the content to hide.", required: true, loads: Interfaces::Hideable, as: :subject
      argument :reason, String, "The reason the content was hidden.", required: false
      argument :classifier, Enums::ReportedContentClassifiers, "The classification reason for hiding the content.", required: true
      argument :is_staff_actor, Boolean, "Whether or not the content was hidden through stafftools.", default_value: false, required: false

      field :subject, Interfaces::Hideable, "The content that was hidden.", null: true

      def self.async_api_can_modify?(permission, subject:, **inputs)
        if subject.is_a?(::Gist)
          permission.access_allowed?(:hide_gist, resource: subject, current_org: nil, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
        else
          permission.load_repo_and_owner(subject).then do |repo|
            permission.access_allowed?(:hide_issue, repo: repo, resource: subject, current_org: nil, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(subject:, **inputs)
        subject.async_hideable_by?(context[:viewer]).then do |is_hideable|
          raise Errors::Forbidden.new("Viewer not authorized") unless is_hideable

          unless subject.is_a?(::Gist)
            check_database_resource_update_rate_limit!(resource: subject, current_user: context[:viewer])
          end

          author = subject.user || User.ghost

          if subject.set_hidden(context[:viewer], inputs[:reason], inputs[:classifier], author, inputs[:is_staff_actor])
            { subject: subject }
          else
            raise Errors::Unprocessable.new("Could not hide content.")
          end
        end
      end
    end
  end
end
