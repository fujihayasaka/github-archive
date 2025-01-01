# typed: true
# frozen_string_literal: true

module Search
  module Queries

    # The ProjectQuery is used to search projects.
    #
    class ProjectQuery < ::Search::Query

      # The set of fields that can be queried when performing a project search
      def self.field_list
        [:in, :is, :name, :description, :sort, :"linked-repo"].freeze
      end

      # A set of terms that have mutually exclusive values.
      def self.unique_field_list
        [:sort, :is, :"linked-repo"]
      end

      # The mapping of user-facing sort values to the corresponding values used
      # in the search index.
      SORT_MAPPINGS = {
        "created" => "created_at",
        "updated" => "updated_at",
        "name" => "name.raw",
      }.freeze

      DEFAULT_SORT = %w[created desc].freeze

      # The maximum number of characters returned in the highlighted fragments.
      FRAGMENT_SIZE = 200

      # Scoped determines whether to include public/private repo projects within a owner level search.
      attr_reader :scoped

      # Construct a new ProjectQuery instance that will highlight search results
      # by default.
      def initialize(opts = {}, &block)
        super(opts, &block)
        @index = Elastomer::Indexes::Projects.new
        @org_id = opts.fetch(:org_id, nil)
        @repo_id = opts.fetch(:repo_id, nil)
        @user_id = opts.fetch(:user_id, nil)
        @project_type = opts.fetch(:project_type, nil)
        @state = opts.fetch(:state, nil)
        @scoped = opts.fetch(:scoped, false)
      end

      # Internal: Returns the Array of advanced search qualifiers supported by
      # this query type.
      def qualifier_fields
        self.class.field_list
      end

      # Internal: Returns the Array of fields that support aggregation queries.
      def aggregation_fields
        [:state]
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        { type: "project" }
      end

      # Internal: Returns the Array of field names that will be queried.
      def query_fields
        return @query_fields if defined? @query_fields
        @query_fields = []

        search_in.each do |field|
          case field
          when "name"; @query_fields << "name.ngram^1.5"
          when "description"; @query_fields << "body"
          end
        end

        if @query_fields.empty?
          @query_fields = ["name.ngram^1.5", "body"]
        end
        @query_fields
      end

      # Internal: Constructs the search query based on the `query` attribute.
      #
      # Returns the search query Hash.
      def query_doc
        return if escaped_query.empty?

        q = { query_string: {
          query: escaped_query,
          fields: query_fields,
          phrase_slop: 10,
          default_operator: "AND",
          analyzer: "texty_search",
        } }

        { function_score: {
          query: q,
          # This function reduces the score of documents that haven't been
          # updated recently. A document not modified in 24 weeks will have its
          # score reduced by half. Look at updated_at so that old projects
          # that get renewed aren't punished for having an old created_at.
          exp: { updated_at: {
            scale: "168d",
            offset: "14d",
            decay: 0.5,
          } },
        } }
      end

      # Internal: Returns the sorting options Array.
      def build_sort
        return if sort.blank?

        ary = build_sort_section(sort, "_score", SORT_MAPPINGS)
        ary.each do |item|
          next unless item.is_a?(Hash)

          key = item.keys.first
          if "created_at" == key || "updated_at" == key
            order = item[key]
            item[key] = { "order" => order, "unmapped_type" => "date" }
          end
        end

        ary
      end

      # Returns the default sort ordering to use in the absence of a query or
      # any other sort information.
      def default_sort
        DEFAULT_SORT
      end

      # Internal: Build the filters required for the query.
      #
      # Returns the Hash of filter hashes.
      def filter_hash
        return @filter_hash if defined? @filter_hash

        filters = {}

        filters[:name] = builder.query_filter(:"name.ngram")
        filters[:created_at] = builder.date_range_filter(:created_at, :created)
        filters[:updated_at] = builder.date_range_filter(:updated_at, :updated)

        # For now, only open and closed are supported for `is` values
        if @state.present?
          case @state
          when "closed"
            qualifiers[:state].clear.must("closed")
          when "open"
            qualifiers[:state].clear.must("open")
          end
          filters[:state] = builder.term_filter(:state)
        elsif qualifiers.key?(:is)
          case qualifiers[:is].must.first
          when "closed"
            qualifiers[:state].clear.must("closed")
          when "open"
            qualifiers[:state].clear.must("open")
          end
          filters[:state] = builder.term_filter(:state)
        end

        if @project_type == "repo" && @repo_id
          filters[:repo_id] = builder.repository_filter(current_user, @repo_id, "projects")
        elsif project_has_account_owner? && account_owner_id.present?
          # TODO: Once we add cross-owner search for projects, we'll need to
          # ensure that the current user is a member of any organizations that
          # own projects being returned by this search.
          if @org_id
            filters[:org_id] = builder.project_owner_filter(owner_id: @org_id, owner_type: "org")
          elsif @user_id
            filters[:user_id] = builder.project_owner_filter(owner_id: @user_id, owner_type: "user")
          end

          filters[:_id] = builder.project_filter(account_owner_id, current_user, scoped)
          filters[:linked_repo_ids] = builder.project_linked_repository_filter(:linked_repo_ids, :"linked-repo", missing: :none, current_user: current_user)
        else
          raise(ArgumentError, ":project_type and the corresponding owner id (:repo_id, :org_id, :user_id) must be specified")
        end

        # When scoped, don't restirct search to a specific project type.
        unless scoped
          qualifiers[:project_type].clear.must @project_type
          filters[:project_type] = builder.term_filter(:project_type)
        end

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      # Internal: Returns the highlight Hash.
      def build_highlight
        fields = {}

        if query_fields.any? { |str| str.start_with?("name") }
          # force the whole name to be included in the fragment
          fields[:"name.ngram"] = { number_of_fragments: 0 }
        end

        fields[:body] = { number_of_fragments: 0 }

        unless fields.empty?
          { encoder: :html, fields: fields, type: "plain" }
        end
      end

      def repository_filter
        filter_hash[:repo_id]
      end

      def account_owner_id
        case @project_type
        when "org"
          @org_id
        when "user"
          @user_id
        end
      end

      def project_filter
        filter_hash[:_id]
      end

      def project_has_account_owner?
        %w[user org].include?(@project_type)
      end

      # Internal: Prune results and then run the `normalizer` on the results
      # if one was provided.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the normalized Array of hits.
      def normalize(results)
        prune_results(results) unless @results_pruned
        super(results)
      end

      # Internal: Take the array of project results and remove those for which
      # the project no longer exists. We will only perform this pruning in test
      # and production; development mode is for testing out everything.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      def prune_results(results)
        project_ids = results.map { |result| result["_id"].to_i }
        projects = Project.includes(:owner).where(id: project_ids).index_by(&:id)

        results.delete_if do |result|
          doc_id = result["_id"].to_i
          project = projects[doc_id]

          # project soft delete, should already be queued up for removal from index
          if project&.deleted_at.present?
            true
          elsif project.nil? && !Rails.env.development?
            RemoveFromSearchIndexJob.perform_later("project", doc_id)
            true
          else
            result["_model"] = project
            !security_validation result
          end
        end
      end

      # Internal: validate that the user is allowed to see the given search
      # result document.
      #
      # doc - The search result Hash
      #
      # Returns a boolean indicating visibility.
      def security_validation(doc)
        project = doc["_model"]
        return true if project.nil?

        case project.owner_type
        when "Repository"
          repo = project.owner
          return true if repo.public?
          if repository_filter
            return true if repository_filter.accessible_repository?(repo)
          elsif scoped && project_filter
            @include_projects ||= project_filter.accessible_project_ids
            return true if @include_projects.include?(project.id)
          end
        when "Organization", "User"
          return true if project.public?

          if project_filter
            @include_projects ||= project_filter.accessible_project_ids
            return true if @include_projects.include?(project.id)
          end
        end

        GitHub.dogstats.increment("search.query.errors.security", { tags: ["index:#{index.name}"] })
        false
      end
    end
  end
end
