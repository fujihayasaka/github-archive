# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class GistComments < Resolvers::Base

      argument :order_by, Inputs::GistCommentOrder,
        "Ordering options for gist comments returned from the connection.",
        required: false,
        visibility: :internal

      type Connections.define(Objects::GistComment), null: false

      def resolve(order_by: nil)
        case object
        when Gist
          if context[:permission].async_can_list_gist_comments?(object).sync
            object.async_comments.then do
              relation = object.comments.filter_spam_for(context[:viewer])

              if order_by
                field = order_by[:field]
                direction = order_by[:direction]
                relation = relation.order(field => direction)
              end

              relation
            end
          end
        when User
          # Replicates permissions for Gists
          if context[:permission].async_can_list_gist_comments?(object).sync && context[:permission].can_list_user_secret_gists?(owner: object)
            relation = object.gist_comments
          else # No scope needed for public Gist comments
            relation = object.gist_comments
                             .joins(:gist)
                             .merge(Gist.are_public)
                             .from("`gist_comments` IGNORE INDEX FOR ORDER BY (PRIMARY)")
          end

          relation.filter_spam_for(context[:viewer])

          if order_by
            field = order_by[:field]
            direction = order_by[:direction]
            relation = relation.order(field => direction)
          end

          relation
        end
      end
    end
  end
end
