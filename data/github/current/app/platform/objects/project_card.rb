# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectCard < Platform::Objects::Base
      description "A card in a project."

      implements_node templates: [[:oppc, :org_id, :project_id, :project_card_id], [:uppc, :user_id, :project_id, :project_card_id], [:rppc, :repo_id, :project_id, :project_card_id]], as: "PRC", ready_date: "2021-07-09" do |project_card|
        project_card.async_project.then do |project|
          ids = {
            project_id: project.id,
            project_card_id: project_card.id
          }

          project.async_owner.then do |owner|
            case project.owner_type
            when "Organization"
              ids.merge({ prefix: :oppc, org_id: owner.id })
            when "User"
              ids.merge({ prefix: :uppc, user_id: owner.id })
            when "Repository"
              ids.merge({ prefix: :rppc, repo_id: owner.id })
            else
              raise Platform::Errors::Internal, "Unexpected project owner: #{owner.inspect}"
            end
          end
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, project_card)
        project_card.async_project.then do |project|
          permission.typed_can_access?("Project", project)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        if object.is_a?(ProjectCardRedactor::RedactedCard)
          # Previously, this object was completely ignored by authorization.
          # Should there be a different check here?
          true
        else
          object.async_readable_by?(permission.viewer)
        end
      end

      minimum_accepted_scopes ["public_repo"]

      field :project, Platform::Objects::Project, method: :async_project, description: "The project that contains this card.", null: false

      url_fields description: "The HTTP URL for this card" do |card|
        card.async_url
      end

      field :state, Enums::ProjectCardState, description: "The state of ProjectCard", null: true

      def state
        if @object.redacted?
          "REDACTED"
        elsif @object.content_id.nil?
          "NOTE_ONLY"
        else
          Loaders::ActiveRecord.load(::Issue, @object.content_id).then do |issue|
            T.must(issue).async_readable_by?(@context[:viewer]).then do |is_readable|
              is_readable ? "CONTENT_ONLY" : "REDACTED"
            end
          end
        end
      end

      database_id_field

      created_at_field

      updated_at_field

      field :column, Platform::Objects::ProjectColumn, method: :async_column, description: <<~MD, null: true do
          The project column this card is associated under. A card may only belong to one
          project column at a time. The column field will be null if the card is created
          in a pending state and has yet to be associated with a column. Once cards are
          associated with a column, they will not become pending in the future.
        MD
      end

      field :note, String, "The card note", null: true

      field :content, Unions::ProjectCardItem, description: "The card content item", null: true

      def content
        if @object.content_id.nil?
          nil
        else
          # TODO: This needs to become polymorphic as soon as we support more than issues in the field
          Loaders::ActiveRecord.load(::Issue, @object.content_id).then do |issue|
            T.must(issue).async_readable_by?(@context[:viewer]).then do |is_readable|
              next nil unless is_readable

              T.must(issue).async_pull_request.then do |pull_request|
                pull_request || issue
              end
            end
          end
        end
      end

      field :creator, description: "The actor who created this card", resolver: Resolvers::ActorCreator
      field :is_archived, Boolean, "Whether the card is archived", method: :archived?, null: false
    end
  end
end
