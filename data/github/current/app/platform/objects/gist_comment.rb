# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class GistComment < Platform::Objects::Base
      description "Represents a comment on an Gist."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, gist_comment)
        gist_comment.async_target_for_conditional_access.then do |tfca|
          org = tfca.is_a?(::Organization) ? tfca : nil
          permission.access_allowed?(
            :get_gist_comment,
            resource: gist_comment,
            tfca: tfca,
            current_org: org,
            current_repo: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: true
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.spam_check(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:ugc, :user_id, :gist_id, :id]
      ], as: "GC", ready_date: Platform::Helpers::GlobalId::COHORT_4, allow_nil_for: [:id] do |gist_comment|
        gist_comment.async_gist.then do |gist|
          {
            prefix: :ugc,
            user_id: gist_comment.user_id,
            gist_id: gist.repo_name,
            id:  gist_comment.id,
          }
        end
      end

      implements Interfaces::Comment
      implements Interfaces::Deletable
      implements Interfaces::Minimizable
      implements Interfaces::Reportable
      implements Interfaces::Updatable
      implements Interfaces::UpdatableComment

      database_id_field

      field :body, String, "Identifies the comment body.", null: false
      field :body_version, String, visibility: :internal, description: "Identifies the comment body hash.", null: false

      field :author_association, Enums::CommentAuthorAssociation, description: "Author's association with the gist.", null: false

      def author_association
        @object.async_gist.then do |gist|
          if @object.user_id == gist.user_id
            :owner
          else
            :none
          end
        end
      end

      field :gist, Objects::Gist, method: :async_gist, description: "The associated gist.", null: false

      # Overrides Platform::Interfaces::Reportable#url_fields.
      url_fields description: "The HTTP URL for this object", visibility: :internal, origin: GitHub.gist_url do |object|
        object.async_path_uri
      end

      # Overrides Platform::Interfaces::Reportable#viewer_can_report.
      def viewer_can_report
        return false unless GitHub.can_report?
        return false unless @context[:viewer]

        # Check if the viewer was blocked by the author
        @object.async_gist.then(&:async_user).then do |gist_author|
          async_viewer_blocked_by_author = if gist_author
            gist_author.async_blocking?(@context[:viewer])
          else
            Promise.resolve(false)
          end

          async_viewer_blocked_by_author.then do |viewer_blocked_by_author|
            next false if viewer_blocked_by_author

            # users can only report their own comment if someone else edited it.
            if @context[:viewer].id == @object.user_id
              object.async_edited_by_another_user?
            else
              true
            end
          end
        end
      end

      # Overrides Platform::Interfaces::Reportable#viewer_can_report_to_maintainer.
      def viewer_can_report_to_maintainer
        false
      end

      # Overrides Platform::Interfaces::Reportable#viewer_relationship.
      def viewer_relationship
        @object.async_gist.then do |gist|
          gist.async_adminable_by?(@context[:viewer]).then do |gist_is_adminable_by_viewer|
            gist_is_adminable_by_viewer ? :owner : :none
          end
        end
      end

      def self.load_from_next_global_id(parsed_id)
        load_gist_comment(parsed_id.parts[:gist_id], parsed_id.parts[:id])
      end

      def self.load_from_global_id(id)
        gist_repo_name, comment_id = id.split(":", 2)
        load_gist_comment(gist_repo_name, comment_id)
      end

      def self.load_gist_comment(gist_repo_name, comment_id)
        Promise.all([
          Loaders::ActiveRecord.load(::Gist, gist_repo_name, column: :repo_name),
          Loaders::ActiveRecord.load(::GistComment, comment_id.to_i),
          ]).then do |gist, comment|
            if gist && comment && comment.gist_id == gist.id
              comment.gist = gist
              comment
            else
              nil
            end
          end
      end
    end
  end
end
