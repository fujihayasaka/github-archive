# typed: true
# frozen_string_literal: true

module Search

  class QueryHelper
    extend T::Sig
    attr_reader :options

    # Undisputed types are those where a 1:1 ratio of type to query class
    # is maintained. This is helpful for avoiding unnecessary guesswork
    # when determining which query class to use, in cases where the
    # choice is explicitly provided and obvious.
    # I have left CODE off because it is dependent on whether or not blackbird is enabled,
    # and therefore not "undisputed"; same for
    # "ISSUE" because issues and pull requests are not the index.
    UNDISPUTED_TYPES = T.let({
      Search::Types::COMMIT => Search::Queries::CommitQuery,
      Search::Types::DISCUSSION => Search::Queries::DiscussionQuery,
      Search::Types::LABEL => Search::Queries::LabelQuery,
      Search::Types::MARKETPLACE => Search::Queries::MarketplaceQuery,
      Search::Types::REGISTRY_PACKAGE => Search::Queries::RegistryPackageQuery,
      Search::Types::REPOSITORY => Search::Queries::RepoQuery,
      Search::Types::TOPIC => Search::Queries::TopicQuery,
      Search::Types::USER => Search::Queries::UserQuery,
      Search::Types::WIKI => Search::Queries::WikiQuery,
    }, T::Hash[String, T.class_of(Search::Query)])

    def self.field_list
      fields = []
      if GitHub.use_elastomer_code_search?
        fields.concat Search::Queries::CodeQuery::field_list
      else
        fields.concat Search::Queries::BlackbirdCodeQuery::field_list
      end
      fields.concat Search::Queries::CommitQuery::field_list
      fields.concat Search::Queries::DiscussionQuery::field_list
      fields.concat Search::Queries::IssueQuery::field_list
      fields.concat Search::Queries::RepoQuery::field_list
      fields.concat Search::Queries::UserQuery::field_list
      fields.concat Search::Queries::RegistryPackageQuery::field_list
      fields.concat Search::Queries::TopicQuery::field_list
      fields.concat Search::Queries::MarketplaceQuery::field_list
      fields.concat Search::Queries::VulnerabilityQuery::field_list
      fields.concat Search::Queries::WikiQuery::field_list
      if GitHub.enterprise?
        fields.concat [:environment].freeze
      end
      fields.uniq!
      fields.freeze
    end

    # Construct a QueryHelper for managing the various query types we can
    # display on the global search page.
    #
    # phrase  - The search phrase String from the user.
    # type    - The query type String.
    # options - The options Hash passed to the Query constructors.
    #
    def initialize(phrase, type, options)
      @type    = type
      @options = options
      field_list = resolve_query_type(type)&.field_list || self.class.field_list
      pq = Search::ParsedQuery.new(phrase, field_list, options[:current_user], Search::Queries::IssueQuery.enumerable_terms(current_user: options[:current_user]))
      @options[:raw_phrase]  = phrase
      @options[:query]       = pq.query
      @options[:qualifiers]  = pq.qualifiers
      if GitHub::Connect.unified_search_enabled?
        # NOTE: Using T.unsafe because this attribute is conditionally defined based on being in Enterprise mode!
        @options[:environment] = T.unsafe(pq).environment
      end
    end

    sig { params(type: T.untyped).returns(T.nilable(T.class_of(Search::Query))) }
    def resolve_query_type(type)
      if @options[:current_user]&.feature_enabled?(:undisputed_search_type_resolution)
        if type.present? && UNDISPUTED_TYPES.key?(type)
          UNDISPUTED_TYPES[type]
        end
      end
    end

    # Returns the search type as a String
    def search_type
      set = Set.new(%w[Repositories Code Commits Labels Marketplace Users Issues
        Topics Vulnerabilities Wikis])
      set << "RegistryPackages" if PackageRegistryHelper.show_packages?
      set << "Discussions" if GitHub.discussions_available_on_platform?
      set.include?(@type) ? @type : default_search_type
    end

    # If a search type is not specified, try to intuit what the user wants to
    # search for by looking at the filter fields. The Query type with the
    # most matching filter fields will be chosen.
    #
    # Returns our best guess for the search type as a String.
    def default_search_type
      fields = @options[:qualifiers].keys

      repo_count = (fields & Search::Queries::RepoQuery::field_list).length
      issue_count = (fields & Search::Queries::IssueQuery::field_list).length

      if GitHub.discussions_available_on_platform?
        discussion_count = (fields & Search::Queries::DiscussionQuery::field_list).length
      end

      # Consider valid `is:` values to distinguish between a repo search and an
      # issue search.
      if @options[:qualifiers].key?(:is) && @options[:qualifiers][:is].must?
        values = @options[:qualifiers][:is].must
        repo_count += (values & Search::Queries::RepoQuery::IS_VALUES.values.flatten).length
        issue_count += (values & Search::Queries::IssueQuery::IS_VALUES.values.flatten).length

        if GitHub.discussions_available_on_platform?
          discussion_count +=
            (values & Search::Queries::DiscussionQuery::IS_VALUES.values.flatten).length
        end
      end

      choices = [
        ["Repositories", repo_count],
        ["Commits",      (fields & Search::Queries::CommitQuery::field_list).length],
        ["Issues",       issue_count],
        ["Users",        (fields & Search::Queries::UserQuery::field_list).length],
        ["RegistryPackages", (fields & Search::Queries::RegistryPackageQuery::field_list).length],
        ["Topics",       (fields & Search::Queries::TopicQuery::field_list).length],
        ["Wikis",        (fields & Search::Queries::WikiQuery::field_list).length],
      ]

      if GitHub.use_elastomer_code_search?
        choices << ["Code", (fields & Search::Queries::CodeQuery.field_list).length]
      else
        choices << ["Code", (fields & Search::Queries::BlackbirdCodeQuery.field_list).length]
      end

      if GitHub.discussions_available_on_platform?
        choices << ["Discussions", discussion_count]
      end

      choice = choices.max_by { |_name, count| count }
      T.must(choice).first
    end

    # The selected query based on the given or inferred query type.
    #
    # Returns a Query.
    def current
      self[search_type]
    end

    # Lookup a Query given the key String. The allowed keys are:
    # 'Repositories', 'Code', 'Commits', 'Issues', 'Marketplace', 'Users', and 'Wikis'.
    #
    # key - The query type key as a String.
    #
    # Returns a Query or nil if the key is invalid.
    def [](key)
      case key
      when "Code"; code_query
      when "Commits"; commit_query
      when "Discussions"; discussion_query
      when "Issues"; issue_query
      when "Labels"; label_query
      when "Marketplace"; marketplace_listing_query
      when "RegistryPackages"; registry_packages_query
      when "Repositories"; repo_query
      when "Topics"; topic_query
      when "Users"; user_query
      when "Wikis"; wiki_query
      end
    end

    # Returns a CodeQuery
    def code_query
      return @code_query if defined? @code_query

      if GitHub.use_elastomer_code_search?
        opts = @options.dup
        opts[:request_category] = @options.fetch(:request_category, "web")
        opts[:normalizer] = lambda { |results| Search::CodeResultView.build_batch(results) }
        opts[:dotcom_normalizer] = lambda { |results| Search::DotcomCodeResultView.build_batch(results) }

        dup_qualifiers(opts)
        Search::Queries::CodeQuery.new(opts)
      else
        opts = @options.dup
        dup_qualifiers(opts)
        Search::Queries::BlackbirdCodeQuery.new(opts)
      end
    end

    # Returns a CommitQuery
    def commit_query
      opts = @options.dup
      opts[:dotcom_normalizer] = lambda { |results| results.map! { |h| Search::DotcomCommitResultView.new(h) } }
      dup_qualifiers(opts)

      Search::Queries::CommitQuery.new(opts)
    end

    # Returns a DiscussionQuery
    def discussion_query
      return @discussion_query if defined? @discussion_query

      opts = @options.dup
      opts[:normalizer] = lambda { |results| results.map! { |h| Search::DiscussionResultView.new(h) } }
      dup_qualifiers(opts)

      @discussion_query = Search::Queries::DiscussionQuery.new(opts)
    end

    # Returns an IssueQuery
    def issue_query
      return @issue_query if defined? @issue_query

      opts = @options.dup

      opts[:normalizer] = lambda { |results| results.map! { |h| Search::IssueResultView.new(h, opts[:current_user]) } }
      opts[:dotcom_normalizer] = lambda { |results| results.map! { |h| Search::DotcomIssueResultView.new(h, opts[:current_user]) } }
      opts[:context] = "#{self.class.name&.demodulize.underscore}-#{__method__}"
      dup_qualifiers(opts)

      @issue_query = Search::Queries::IssueQuery.new(opts)
    end

    # Returns an LabelQuery
    def label_query
      return @label_query if defined? @label_query

      opts = @options.dup
      opts[:normalizer] = lambda { |results| results.map! { |h| Search::LabelResultView.new(h) } }
      dup_qualifiers(opts)

      @label_query = Search::Queries::LabelQuery.new(opts)
    end

    # Returns a MarketplaceQuery
    def marketplace_listing_query
      return @marketplace_listing_query if defined? @marketplace_listing_query

      opts = @options.dup
      opts[:type] = "marketplace-tools"
      opts[:normalizer] = lambda do |results|
        results.map! do |h|
          case h["_source"]["search_type"]
          when "marketplace_listing"
            Search::MarketplaceListingResultView.new(h)
          when "repository_action"
            Search::RepositoryActionResultView.new(h)
          when "azure_model"
            Search::AzureModelResultView.new(h)
          end
        end
      end
      dup_qualifiers(opts)

      @marketplace_listing_query = Search::Queries::MarketplaceQuery.new(opts)
    end

    # Returns a RegistryPackageQuery
    def registry_packages_query
      return @registry_packages_query if defined? @registry_packages_query
      current_user = @options[:current_user]

      opts = @options.dup
      opts[:normalizer] = lambda { |results| results.map! { |h| Search::RegistryPackageResultView.new(h, current_user: current_user) } }
      dup_qualifiers(opts)

      @registry_packages_query = Search::Queries::RegistryPackageQuery.new(opts)
    end

    # Returns a RepoQuery
    def repo_query
      return @repo_query if defined? @repo_query

      opts = @options.dup
      opts[:normalizer] = lambda { |results| results.map! { |h| Search::RepoResultView.new(h) } }
      opts[:dotcom_normalizer] = lambda { |results| results.map! { |h| Search::DotcomRepoResultView.new(h) } }
      dup_qualifiers(opts)

      @repo_query = Search::Queries::RepoQuery.new(opts)
    end

    # Returns a CommandPalette::RepoQuery
    def command_palette_repo_query
      return @command_palette_repo_query if defined? @command_palette_repo_query

      opts = @options.dup
      opts[:normalizer] = lambda { |results| results.map! { |h| Search::RepoResultView.new(h) } }
      opts[:dotcom_normalizer] = lambda { |results| results.map! { |h| Search::DotcomRepoResultView.new(h) } }
      dup_qualifiers(opts)

      @command_palette_repo_query = Search::Queries::CommandPalette::RepoQuery.new(opts)
    end

    # Returns a UserQuery
    def user_query
      return @user_query if defined? @user_query

      opts = @options.dup
      opts[:normalizer] = lambda { |results| results.map! { |h| Search::UserResultView.new(h) } }
      opts[:dotcom_normalizer] = lambda { |results| results.map! { |h| Search::DotcomUserResultView.new(h) } }
      dup_qualifiers(opts)

      @user_query = Search::Queries::UserQuery.new(opts)
    end

    # Returns a TopicQuery
    def topic_query
      return @topic_query if defined? @topic_query

      opts = @options.dup
      opts[:normalizer] = lambda { |results| results.map! { |h| Search::TopicResultView.new(h) } }
      opts[:dotcom_normalizer] = lambda { |results| results.map! { |h| Search::DotcomTopicResultView.new(h) } }
      dup_qualifiers(opts)

      @topic_query = Search::Queries::TopicQuery.new(opts)
    end

    # Returns a WikiQuery
    def wiki_query
      return @wiki_query if defined? @wiki_query

      opts = @options.dup
      opts[:normalizer] = lambda { |results| results.map! { |h| Search::WikiResultView.new(h) } }
      dup_qualifiers(opts)

      @wiki_query = Search::Queries::WikiQuery.new(opts)
    end

    # Returns a VulnerabilityQuery
    def vulnerability_query
      return @vulnerability_query if defined? @vulnerability_query

      opts = @options.dup
      dup_qualifiers(opts)

      @vulnerability_query = Search::Queries::VulnerabilityQuery.new(opts)
    end

    # Replace the :qualifiers with a duplicate so we don't cross-contaminate queries
    def dup_qualifiers(options)
      return unless options.key? :qualifiers

      qualifiers = options[:qualifiers].dup
      qualifiers.each { |k, v| qualifiers[k] = v.dup }
      options[:qualifiers] = qualifiers
    end
  end
end  # Search
