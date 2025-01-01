# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CodeSearchResult < Base
      description "A file that matches a code search query"

      # The underlying Blackbird API will provide authz for the entire code search object graph.
      def self.async_api_can_access?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # The underlying Blackbird API will provide authz for the entire code search object graph.
      def self.async_viewer_can_see?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      mobile_only true

      # The underlying Blackbird API will also verify oauth scopes during its authz checks.
      scopeless_tokens_as_minimum

      field :path, String, description: "Path to the file in the repository", null: false

      # For now we will simply relay the data Blackbird is giving us and not connect it to the richer
      # object graph. A next iteration should consider adding/replacing these repository fields with a rich
      # Objects::Repository field but due to time constraints this will be left out the initial v1.
      field :repo_owner_database_id,
        Scalars::BigInt,
        description: "Repository owner ID",
        null: true,
        method: :repo_owner_id

      field :repo_database_id,
        Scalars::BigInt,
        description: "Repository ID",
        null: true,
        method: :repo_id

      # This connects the Blackbird search result with our deeper object graph via the repository.
      # Authz should have already been checked via Blackbird's authz checks so any non-null repository ID
      # found here should be an accessible repository for the viewer.
      #
      # Design Note: This does open up the possibility of deeper traversal causing performance
      # problems so accessing anything under the Repository object should be done with caution to ensure
      # performance is within normal limits. Another option would be to not connect the repository at all
      # and instead provide only the fields we need on a field-by-field basis. Since this is a mobile_only
      # API we can revisit this decision later.
      field :repository,
        Objects::Repository,
        description: "The repository associated with the code result",
        null: true

      field :repo_name_with_owner,
        String,
        description: "Owner and name of repository",
        null: false,
        method: :repo_nwo

      field :snippets,
        [Objects::CodeSearchSnippet],
        description: "Previews of the file contents that match the search query",
        null: false

      field :commit_sha, String, description: "The resulting file's object ID within the git repository", null: false

      field :ref_name, String, description: "The resulting file's branch within the git repository", null: false

      field :blob_sha, String, description: "The blob object this resuling file's path resolves to", null: false

      field :language, Objects::CodeSearchLanguage, description: "Language of the resulting file", null: true

      field :match_count, Integer, description: "Number of query matches within the resulting file", null: false
    end
  end
end
