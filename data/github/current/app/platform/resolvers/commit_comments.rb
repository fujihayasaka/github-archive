# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class CommitComments < Resolvers::Base
      include Scientist

      VALID_ORDERING_FIELD = "updated_at"

      argument :order_by, Inputs::CommitCommentOrder,
        "Ordering options for commit comments returned from the connection.",
        required: false,
        visibility: :internal

      type Connections::CommitComment, null: false

      def resolve(order_by: nil)
        field = T.let(nil, T.nilable(String))
        direction = T.let(nil, T.nilable(String))

        commit_comment_promise = case object
        when Repository
          context[:permission].async_can_list_commit_comments?(object).then do |can_list_commit_comments|
            if can_list_commit_comments
              relation = ::CommitComment.where(repository_id: object.id).filter_spam_for(context[:viewer])

              if order_by
                field = order_by[:field]
                direction = order_by[:direction]
                relation = relation.order(field => direction)
              end

              relation
            else
              ::CommitComment.none
            end
          end
        when CommitCommentThread
          comments = object.comments

          visible_comments = comments.reject do |comment|
            comment.hide_from_user?(context[:viewer])
          end

          if order_by
            field = order_by[:field]
            direction = order_by[:direction]

            if field == VALID_ORDERING_FIELD
              sorter = if direction == "ASC"
                lambda { |a, b| a.updated_at <=> b.updated_at }
              else
                lambda { |a, b| (a.updated_at <=> b.updated_at) * -1 }
              end
              visible_comments = visible_comments.sort(&sorter)
            end
          end

          Promise.resolve(ArrayWrapper.new(visible_comments))
        when User
          relation = context[:permission].
            filter_permissible_repository_resources(object, object.commit_comments, resource: "contents", filter_spam: true)

          if order_by
            field = order_by[:field]
            direction = order_by[:direction]
            relation = relation.order(field => direction)
          end

          Promise.resolve(relation)
        else
          relation = ::CommitComment.none

          if object.respond_to?(:repository)
            context[:permission].async_can_list_commit_comments?(object.repository).then do |can_list_commit_comments|
              if can_list_commit_comments
                relation = ::CommitComment.where({
                  repository_id: object.repository.id,
                  commit_id: object.oid,
                }).filter_spam_for(context[:viewer])

                if order_by
                  field = order_by[:field]
                  direction = order_by[:direction]
                  relation = relation.order(field => direction)
                end

                relation
              else
                relation
              end
            end
          else
            Promise.resolve(relation)
          end
        end

        commit_comment_promise.then { |commit_comment| commit_comment }
      end
    end
  end
end
