# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class StafftoolsQuery < Search::Queries::Audit::Query

      # The set of fields that will be searched.
      SEARCHABLE_FIELDS = [
        :actor, :actor_ip, :user, :org, :repo, :action, :staff_actor,
        :"data.email", :"data.old_name", :"data.old_login", :"data.old_user",
        :"data.old_user_id", :"data.team", :"data.oauth_application_id",
        :"data.request_id", :"staff.minimize_comment", :"data.comment_id",
        :"data.minimized", :"data.gist_id"
      ].freeze

      def initialize(options = {}, &block)
        @direction = options.delete(:direction) == "ASC" ? :asc : :desc
        @index_name = options.fetch(:index_name, GitHub.audit.searcher.index.name)
        super(options, &block)
      end

      def query_params
        {
          index: @index_name,
          type: "audit_entry",
        }
      end

      # This portion is scored, and should default to a match_all this way
      def query_doc
      end

      # This portion is not scored; using a query string here is suboptimal
      # but hard to avoid without larger parser -> query gen refactors
      def build_query_filter
        if phrase.present?
          {
            query_string: {
              query: phrase,
              fields: SEARCHABLE_FIELDS,
              default_operator: "AND",
            },
          }
        end
      end

      def build_sort
        {
          :@timestamp => {
            order: @direction,
          },
        }
      end

      # Override ::Search::Query#valid_query? since StafftoolsQuery uses
      # `query_string`.  We're relying on elasticsearch to validate our string
      def valid_query?
        true
      end
    end
  end
end
