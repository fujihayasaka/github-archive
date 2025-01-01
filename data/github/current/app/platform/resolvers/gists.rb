# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Gists < Resolvers::Base
      argument :privacy, Enums::GistPrivacy, "Filters Gists according to privacy.", required: false
      argument :order_by, Inputs::GistOrder, "Ordering options for gists returned from the connection", required: false

      type Connections.define(Objects::Gist), null: false

      def resolve(privacy: nil, order_by: nil)
        if !context[:permission].can_list_gists?(owner: object)
          return ::Gist.none
        end

        relation = object.gists.active.filter_spam_for(context[:viewer])

        gist_privacy = privacy || "public"

        can_see_secret_gists = (context[:viewer].try(:site_admin?) && context[:permission].has_scope?("site_admin")) ||
          context[:permission].can_list_user_secret_gists?(owner: object)

        # REST API doesn't seem to handle this case
        if object.is_a?(Organization) && object.adminable_by?(context[:viewer])
          can_see_secret_gists = context[:permission].has_scope?("gist")
        end

        case gist_privacy
        when "all"
          if can_see_secret_gists
            # leave scope as is
          else
            relation = relation.are_public
          end
        when "secret"
          if can_see_secret_gists
            relation = relation.are_secret
          else
            relation = ::Gist.none
            context.errors << GraphQL::ExecutionError.new("You don't have permission to see gists.")
          end
        when "public"
          relation = relation.are_public
        end

        if order_by
          relation = relation.order("gists.#{order_by[:field]}" => order_by[:direction])
        end

        relation
      end
    end
  end
end
