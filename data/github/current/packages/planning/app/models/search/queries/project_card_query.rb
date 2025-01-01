# typed: true
# frozen_string_literal: true

module Search
  module Queries

    # The ProjectCardQuery is used to search project cards.
    #
    class ProjectCardQuery < ::Search::Query
      # The set of fields that can be queried when performing a project card search
      def self.field_list
        [
          :assignee,
          :author,
          :label,
          :repo,
          :state,
        ].freeze
      end

      # A set of terms that have mutually exclusive values.
      def self.unique_field_list
        [
          :assignee,
          :author,
          :repo,
          :state,
        ]
      end

      def initialize(opts = {}, &block)
        super(opts, &block)
        @index = Elastomer::Indexes::ProjectCards.new
        @project_id = opts.fetch(:project_id)
        @card_type = opts.fetch(:card_type)
      end

      # Internal: Constructs the actual `:query` portion of the query
      # document. This will later be wrapped in a filtered query if search
      # qualifiers were also used.
      #
      # Returns the search query Hash.
      def query_doc
        return if escaped_query.empty?

        {
          query_string: {
            query: escaped_query,
            fields: ["title^1.2", "title.ngram"],
            default_operator: "AND",
          },
        }
      end

      def query_params
        { type: "project_card" }
      end

      # Internal: Build the filters required for the query.
      #
      # Returns the Hash of filter hashes.
      def filter_hash
        return @filter_hash if defined? @filter_hash

        qualifiers[:project_id].clear.must(@project_id)
        qualifiers[:type].clear.must(@card_type)

        @filter_hash = {
          assignee_ids: builder.user_filter(:assignee_ids, :assignee, missing: :none, exclude_private_profiles: false),
          author: builder.user_filter(:author_id, :author, exclude_private_profiles: false),
          type: builder.term_filter(:type),
          labels: builder.term_filter(:labels, :label, execution: :and, missing: :none) { |label| label.downcase },
          project_id: builder.term_filter(:project_id, :project_id),
          state: builder.term_filter(:state),
        }

        # This is a temporary hack because of a bug with searching note cards
        # in private repo projects. Ideally, card_type would always be checked
        # in the phrase.
        unless @card_type == "note"
          @filter_hash[:repo_id] = builder.repository_filter(current_user, nil, "issues", user_session: user_session, ip: remote_ip)
        end

        @filter_hash
      end

      def valid_query?
        return false unless super

        if project&.readable_by?(current_user)
          true
        else
          @invalid_reason = "An invalid project was specified."

          false
        end
      end

      private

      def project
        return @project if defined? @project

        @project = Project.find_by(id: @project_id)
      end
    end
  end
end
