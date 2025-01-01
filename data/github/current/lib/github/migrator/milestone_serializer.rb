# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class MilestoneSerializer < BaseSerializer
      def scope
        Milestone.preload(:repository, :created_by)
      end

      def as_json(options = {})
        {
          type: "milestone",
          url: url,
          repository: repository,
          user: user,
          title: title,
          description: description,
          state: state,
          due_on: due_on,
          created_at: created_at,
          updated_at: updated_at,
          closed_at: closed_at,
        }
      end

      private

      def repository
        url_for_model(model.repository)
      end

      def user
        url_for_model(model.created_by)
      end

      def title
        model.title
      end

      def description
        model.description
      end

      def state
        model.state
      end

      def due_on
        time(model.due_on)
      end

      def closed_at
        time(model.closed_at)
      end
    end
  end
end
