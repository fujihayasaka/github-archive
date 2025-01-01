# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class DeleteProjectCard
      attr_reader :card, :context, :project

      def initialize(card, context)
        @card = card
        @project = card.project
        @context = context
      end

      def check_permissions
        context[:permission].typed_can_modify?("DeleteProjectCard", card: card).sync
        context[:permission].authorize_content(:project, :destroy, project: project)

        unless project.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to delete project cards on this project.")
        end

        if ProjectCardRedactor.check_one(context[:viewer], card).redacted?
          raise Errors::Forbidden.new("#{context[:viewer].display_login} cannot delete the project card because they do not have access to the associated content.")
        end
      end

      def delete_card
        check_permissions
        card.destroy
        project.notify_subscribers(
          action: "card_destroy",
          message: "#{context[:viewer].display_login} removed a card.",
        )
      end
    end
  end
end
