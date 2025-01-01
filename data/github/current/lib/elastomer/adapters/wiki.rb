# typed: false
# frozen_string_literal: true

module Elastomer::Adapters

  # The Wiki adapter is used to read pages from a repository wiki
  # and index them into the wikis index. What is needed for
  # this adapter to work is a Repository instance and the wiki revision oid
  # to index from. If two revision oids are given, then only those files that have
  # changed between the two revisions will be indexed.
  #
  class Wiki < ::Elastomer::Adapter
    # Raised when a page fails to render properly
    PageRenderingError = Class.new(Elastomer::Error)

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "Wikis"
    end

    def self.mysql_cluster
      ::Repository.cluster_name
    end

    # Boolean flag used to force the full indexing of a repository that would
    # otherwise be ignored. Only use this option during testing.
    attr_accessor :force_indexing
    alias :force_indexing? :force_indexing

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    #
    def model
      return @model if defined?(@model) && !@model.nil?
      @model = ::Repositories.domain.by_id(document_id)
    end
    alias :repository :model

    # Document routing information used to co-locate all wiki pages on a single
    # shard in the search index for a given repository.
    def document_routing
      document_id
    end

    def wiki
      repository.unsullied_wiki if repository
    end

    # Public: clear the `base_revision_oid` instance variable so we can iterate
    # over the wiki pages again.
    #
    # Returns this adapter.
    def reset!
      super
      remove_instance_variable :@base_revision_oid if defined? @base_revision_oid
      self
    end

    # Public: Iterate over each wiki page and yield
    # an indexing action (:index or :delete) along with a document Hash
    # corresponding to that action.
    #
    # Returns this adapter instance.
    #
    def each(&block)
      if repository.nil?
        raise Elastomer::ModelMissing, "The repository has not been set, or the repository ID does not exist in the database."
      end

      # skip wikis that should not be available in the search index
      unless force_indexing?
        return self unless repository.wiki_is_searchable?
      end

      perform_indexing(&block)
    end

    # Public: Create a query hash that can be used to delete all indexed
    # wiki pages associated with the repository.
    #
    # Returns an Array containing the delete query Hash and the documents
    # types that should be deleted.
    #
    # Raises a RuntimeError if the document_id is not set.
    def delete_query
      if document_id.nil?
        raise RuntimeError, "The Repository ID has not been set."
      end

      query = { query: { term: { repo_id: document_id } } }
      opts  = { type: %w[page wiki], routing: document_routing }

      [query, opts]
    end

    # Raises RuntimeError because you shouldn't use this method.
    #
    def to_hash
      raise RuntimeError, "Wiki indexing does not support single hash indexing - use the `each` method."
    end

    # Returns the current revision oid for the wiki from the search index
    # or `nil` if the wiki is not present in the search index.
    def base_revision_oid
      return @base_revision_oid if defined? @base_revision_oid

      @base_revision_oid = index.indexed_head(repository.id)
    end

    # Convert a wiki page into a document Hash that can be indexed in
    # ElasticSearch.
    #
    # page - The GitHub::Unsullied::Page to convert to a document Hash.
    #
    # Returns a document Hash or nil if the page is not indexable.
    #
    def page_to_document(page)
      return unless page

      if page.deleted?
        document = {
          _id: es_document_id(repository, page),
          _type: "page",
          _routing: document_routing,
        }
        return [:delete, document]
      end

      document = {
        _id: es_document_id(repository, page),
        _type: "page",
        _routing: document_routing,
        title: page.title,
        path: page.path,
        filename: page.filename,
        format: page.format,
        body: rendered_page(page),
        repo_id: repository.id,
        public: repository.public?,
        business_id: repository.internal_visibility_business_id,
        updated_at: page.updated_at,
        revision: page.revision_oid,
      }

      [:index, document]

    rescue PageRenderingError => e
      Failbot.report(e, "gh.wiki.format": page.format, "gh.wiki.latest_oid": page.latest_revision.oid, app: "github-user")
      GitHub.dogstats.increment "search.wiki.indexing.rendering_error.count", tags: datadog_tags(index)
      nil
    rescue Elastomer::Error, ElastomerClient::Error => e
      Failbot.report(e,
        "gh.repo.id": repository.id,
        "gh.wiki.page": page.path,
        "gh.wiki.format": page.format,
        "gh.wiki.latest_oid": page.latest_revision.oid)
      GitHub.dogstats.increment "search.wiki.indexing.page_error.count", tags: datadog_tags(index)
      nil
    end

    def es_document_id(repository, page)
      Digest::SHA1.hexdigest("#{repository.id}::#{page.path}") # rubocop:disable GitHub/InsecureHashAlgorithm
    end

    def rendered_page(page)
      rendered = page.data_html
      if !rendered.errored?
        Nokogiri::HTML::DocumentFragment.parse(rendered.html).text.squish
      else
        raise PageRenderingError, rendered.error
      end
    end

    def wiki_document
      {
        _id: repository.id,
        _type: "wiki",
        _routing: document_routing,
        repo_id: repository.id,
        revision: wiki.default_oid,
        public: repository.public?,
        updated_at: Time.zone.now.iso8601,
      }
    end

    def wiki_state_document
      {
        _id: repository.id,
        _type: "page",
        _routing: document_routing,
        repo_id: repository.id,
        revision: wiki.default_oid,
        public: repository.public?,
        updated_at: Time.zone.now.iso8601,
        is_wiki_state_doc: true
      }
    end

    def perform_indexing
      begin
          start_timer

          pages =
            if base_revision_oid && !force_indexing?
              wiki.pages.changed_pages(base_revision_oid, wiki.default_oid)
            else
              wiki.pages
            end

          pages.each do |page|
            action, document = page_to_document(page)
            next unless action && document
            yield action, document
            check_timer!
          end

        rescue IndexingTimeout => err
          Failbot.report err,
              "gh.repo.id": repository.id,
              "gh.repo.base_oid": base_revision_oid,
              "gh.repo.head_oid": wiki.default_oid
          GitHub.dogstats.increment "search.wiki.indexing.timeout.count", tags: datadog_tags(index)

          ensure
            if wiki.default_oid
              state_doc = index.get_metadata["has_wiki_state_docs"] ? wiki_state_document : wiki_document
              yield :index, state_doc
            end
        end
      self
    end

    module IndexingTimer
      # Maximum time an indexing process can take
      TIMEOUT_IN_SECONDS = 60.minutes
      IndexingTimeout = Class.new(::Elastomer::Error)

      def start_timer
        @start_time = Time.now
        @max_time = @start_time + TIMEOUT_IN_SECONDS
      end

      def elapsed_time
        Time.now - @start_time
      end

      def check_timer!
        if @max_time <= Time.now
          raise IndexingTimeout,
            "Timeout indexing wiki for repo #{repository.id} (#{@max_time - @start_time} seconds)"
        end
      end
    end
    include IndexingTimer
  end
end
