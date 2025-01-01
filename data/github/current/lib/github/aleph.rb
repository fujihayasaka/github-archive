# typed: true
# frozen_string_literal: true

require "aleph"

module GitHub
  class Aleph
    class ReportableError < StandardError; end

    SERVICE_NAME        = "aleph"
    SERVICE_URL         = "#{GitHub.aleph_url}/twirp"
    FAILBOT_APP         = "github-aleph-client"
    IS_PUBLIC_HEADER    = "X-GitHub-Is-Public"
    FEATURE_FLAG_HEADER = "X-GitHub-Feature-Flags"
    DEFAULT_TIMEOUT = 2.0

    SLOW_SERVICE_NAME   = "aleph_slow"
    SLOW_SERVICE_URL    = "#{GitHub.aleph_slow_url}/twirp"
    SLOW_TIMEOUT        = 10.0

    # VALID_OPERATIONS define the set of accepted operation values for toggle_repo_network.
    VALID_OPERATIONS = %w[enable disable].freeze

    # Some characters are not valid for GitHub.flipper names.
    # This regex is used to remove invalid characters from Linguist language names
    # when converting a Linguist language name to the derived format used with GitHub.flipper.
    INVALID_CHARS = /[-+\s\.]/

    # For these errors, callers of aleph should gracefully degrade to render content without aleph data.
    ERRORS_TO_IGNORE = [
      # Conversion errors can result from paths with non-UTF8 characters, and should not be reported as failures.
      ::Encoding::UndefinedConversionError,
      # For these errors, stats will be recorded (see GitHub::FaradayMiddleware::Datadog)
      Faraday::SSLError,
      Faraday::Error,
      Faraday::ConnectionFailed,
    ]

    TIMEOUT_ERRORS = [
      Faraday::TimeoutError,
      Timeout::Error,
    ]

    # Public: Determine if the repo was indexed at the commit oid for a given backend.
    def self.exist(repo:, commit_oid:, actor: nil, backends: [])
      with_error_reporting do
        client.exist(
          repo_id: repo.id,
          network_id: repo.network_id,
          root_id: repo.network.root_id,
          repo_owner: repo.owner_display_login,
          repo_name: repo.name,
          commit_oid: commit_oid,
          backends: backends,
          actor_id: actor&.actor_id,
          request_ip: actor&.request_ip,
          access_token: actor&.access_token,
          access_token_expires: actor&.access_token_expires,
          access_token_kind: actor&.access_token_kind,
          session_id: actor&.session_id,
          opt_headers: { IS_PUBLIC_HEADER => repo.public?.to_s },
        )
      end
    end

    # Request index reason helper methods are defined to give callers easy access to valid `reason` keyword arg values
    # when making a `GitHub::Aleph.request_index` RPC.
    #
    # Public: vea_repo_with_alert is provided for requesting indexes during alert creation for eligible repositories
    # depending on vulnerable packages.
    def self.vea_repo_with_alert_reason
      :VEA_REPO_WITH_ALERT
    end

    # Public: vea_repo_user_viewing_alerts is provided for requesting indexes when users view a Dependabot security alert.
    def self.vea_repo_user_viewing_alerts_reason
      :VEA_REPO_USER_VIEWING_ALERTS
    end

    # Public: vea_repo_with_vulnerability is provided for requesting indexes by curators to identify packages with security
    # vulnerabilities that can impact dependent repositories.
    def self.vea_repo_with_vulnerability_reason
      :VEA_REPO_WITH_VULNERABILITY
    end

    # Public: code_nav_user_viewing_code is provided for requesting indexes by user-driven behavior when viewing the
    # blob view.
    def self.code_nav_user_viewing_code_reason
      :CODE_NAV_USER_VIEWING_CODE
    end

    # Public: code_nav_user_viewing_code_diff is provided for requesting indexes by user-driven behavior when viewing
    # the files tab of a PR.
    def self.code_nav_user_viewing_code_diff_reason
      :CODE_NAV_USER_VIEWING_CODE_DIFF
    end

    def self.search_keys_references_to_consider_only_direct
      :OnlyDirectReferences
    end

    def self.search_keys_references_to_consider_direct_and_aliased
      :DirectAndAliasedReferences
    end

    INDEX_REASONS = ::Aleph::Proto::RequestIndexReason.constants
    class InvalidRequestIndexReasonError < StandardError
      def initialize(reason)
        super("Invalid reason #{reason}, must be one of #{INDEX_REASONS}")
      end
    end

    class InvalidToggleRepoNetworkOperationError < StandardError
      def initialize(operation)
        super("Invalid operation #{operation}, must be one of :enable or :disable")
      end
    end

    # Public: Requsts an index for a repository at a commit oid (i.e. commit sha). Requires a valid reason argument, or will raise an error.
    #
    # repo            - Repository to index.
    # commit_oid      - String commit oid (i.e. commit sha) to index.
    # reason          - Symbol reason for requesting the index. Please see the various reason helper methods (e.g. vea_repo_with_alert_reason). Reason must be an approved reason.
    #
    # Returns an Aleph::Proto::RequestIndexResponse.
    def self.request_index(repo:, commit_oid:, reason:, should_index_future_pushes: false, ref: "")
      if !INDEX_REASONS.include?(reason)
        raise InvalidRequestIndexReasonError.new(reason)
      else
        with_error_reporting do
          client.request_index(
            network_id: repo.network_id,
            repo_id: repo.id,
            commit_oid: commit_oid,
            reason: reason,
            should_index_future_pushes: should_index_future_pushes,
            ref: ref,
            opt_headers: { IS_PUBLIC_HEADER => repo.public?.to_s },
          )
        end
      end
    end

    # Public: Requsts an index for the provided search-key. Requires a valid reason argument, or will raise an error.
    # Please see Request Index reasons above for the appropriate reason based on the use case.
    #
    # search_key      - String base64 encoded search-key provided by the Aleph service.
    # reason          - Symbol reason for requesting the index. Please see the various reason helper methods (e.g. vea_repo_with_alert_reason). Reason must be an approved reason.
    #
    # Returns an Aleph::Proto::RequestIndexResponse.
    def self.request_index_for_search_key(search_key:, reason:)
      if !INDEX_REASONS.include?(reason)
        raise InvalidRequestIndexReasonError.new(reason)
      else
        with_error_reporting do
          slow_client.request_index_for_search_key(
            search_key: search_key,
            reason: reason,
          )
        end
      end
    end

    # Public: Get the indexing status for the provided repo and commit oid.
    #
    # repo            - Repository to check indexing status for.
    # commit_oid      - String commit oid (i.e. commit sha).
    #
    # Returns the Aleph::Proto::GetIndexingStatusResponse for a given repository at a commit oid (i.e. commit sha).
    def self.get_indexing_status(repo:, commit_oid:)
      with_error_reporting do
        client.get_indexing_status(
          network_id: repo.network_id,
          repo_id: repo.id,
          commit_oid: commit_oid,
          opt_headers: { IS_PUBLIC_HEADER => repo.public?.to_s },
        )
      end
    end

    # Public: Get the indexing status for the provided search key.
    #
    # search_key: A string base64 encoded search-key retrieved by the Aleph service.
    #
    # Returns the Aleph::Proto::GetIndexingStatusResponse for the provided search-key.
    def self.get_indexing_status_for_search_key(search_key:)
      with_error_reporting do
        slow_client.get_indexing_status_for_search_key(
          search_key: search_key,
        )
      end
    end

    # Public: Find the location of the definition for a given symbol. `textDocument/definition`
    def self.text_document_definition(repo:, commit_oid:, path:, row:, col:, query:, language:, search_dependencies: false, actor: nil, backends: [], ref:, symbol_kind:)
      with_error_reporting do
        client.text_document_definition(
          repo_id: repo.id,
          network_id: repo.network_id,
          root_id: repo.network.root_id,
          repo_owner: repo.owner_display_login,
          repo_name: repo.name,
          commit_oid: commit_oid,
          path: path,
          row: row,
          col: col,
          query: query,
          search_dependencies: search_dependencies,
          backends: backends,
          ref: ref,
          actor_id: actor&.actor_id,
          request_ip: actor&.request_ip,
          access_token: actor&.access_token,
          access_token_expires: actor&.access_token_expires,
          access_token_kind: actor&.access_token_kind,
          session_id: actor&.session_id,
          language: language,
          symbol_kind: symbol_kind,
          opt_headers: { IS_PUBLIC_HEADER => repo.public?.to_s },
        )
      end
    end

    # Public: Find the locations of references of a given symbol. `textDocument/references`
    def self.text_document_references(repo:, commit_oid:, path:, row:, col:, query:, language:, search_dependencies: false, actor: nil, backends: [], ref:, symbol_kind:)
      with_error_reporting do
        client.text_document_references(
          repo_id: repo.id,
          network_id: repo.network_id,
          root_id: repo.network.root_id,
          repo_owner: repo.owner_display_login,
          repo_name: repo.name,
          commit_oid: commit_oid,
          path: path,
          row: row,
          col: col,
          query: query,
          backends: backends,
          ref: ref,
          actor_id: actor&.actor_id,
          request_ip: actor&.request_ip,
          access_token: actor&.access_token,
          access_token_expires: actor&.access_token_expires,
          access_token_kind: actor&.access_token_kind,
          session_id: actor&.session_id,
          language: language,
          symbol_kind: symbol_kind,
          opt_headers: { IS_PUBLIC_HEADER => repo.public?.to_s },
        )
      end
    end

    # Public: Find references for a specific repo, commoit_oid, and list of fully qualified names.
    # Warning! This uses a slow client and is not intended to be used for user-facing production requests! Please only use in background jobs.
    #
    # repo            - Repository to search.
    # commit_oid      - The commit oid in which to search.
    # qualified_names - The array of fully qualified names to search for.
    # language        - String language name.
    # ref             - (optional) String git ref (branch) to search. If no ref is provided, the default branch ref will be used.
    #
    # Returns locations of references for the array of qualified names.
    def self.find_references_to_qualified_names(repo:, commit_oid:, qualified_names:, language: "", ref: "", features: [])
      with_error_reporting do
        #  For the VEA (vulnerability exposure analysis) usecase,  a default ref keyword arg of "" is provided.  When
        #  no specific ref is provided,  we attempt to lookup the repository's default ref.  In the future,  when VEA
        #  analysis is expanded to include non-default refs,  this approach will need to be revisited.
        if ref == ""
          ref = T::let(repo.default_branch_ref&.qualified_name, T.nilable(String)) || ""
        end
        slow_client.find_references_to_qualified_names(
          repo_id: repo.id,
          network_id: repo.network_id,
          commit_oid: commit_oid,
          qualified_names: qualified_names,
          language: language,
          ref: ref,
          opt_headers: {
            IS_PUBLIC_HEADER => repo.public?.to_s,
            FEATURE_FLAG_HEADER => features,
          },
        )
      end
    end

    # Public: Find the locations of references that match any one of the given search keys.
    # Warning! This uses a slow client and is not intended to be used for user-facing production requests! Please only use in background jobs.
    #
    # repo        - Repository to search.
    # commit_oid  - String commit sha
    # search_keys - List of search keys
    # ref         - (optional) String ref to search. If no ref is provided, the default branch ref will be used.
    #
    # Returns locations of references matched by the search keys provided for the repo / commit oid.
    def self.find_references_for_search_keys(repo:, commit_oid:, search_keys:, references_to_consider: self.search_keys_references_to_consider_only_direct, ref: "", features: [])
      with_error_reporting do
        if ref == ""
          ref = T::let(repo.default_branch_ref&.qualified_name, T.nilable(String)) || ""
        end
        slow_client.find_references_for_search_keys(
          repo_id: repo.id,
          network_id: repo.network_id,
          commit_oid: commit_oid,
          search_keys: search_keys,
          references_to_consider: references_to_consider,
          ref: ref,
          opt_headers: {
            IS_PUBLIC_HEADER => repo.public?.to_s,
            FEATURE_FLAG_HEADER => features,
          },
        )
      end
    end

    # Public: Find the locations of definitions that match any one of the given qualified names.
    # Warning! This uses a slow client and is not intended to be used for user-facing production requests! Please only use in background jobs.
    #
    # repo            - Repository to search.
    # commit_oid      - String commit sha
    # qualified_names - List of qualified names
    # language        - String language name.
    # ref             - (optional) String ref to search. If no ref is provided, the default branch ref will be used.
    #
    # Returns locations of references matched by the search keys provided for the repo / commit oid.
    def self.find_definitions_of_qualified_names(repo:, commit_oid:, qualified_names:, language:, ref: "", features: [])
      with_error_reporting do
        if ref == ""
          ref = T::let(repo.default_branch_ref&.qualified_name, T.nilable(String)) || ""
        end
        slow_client.find_definitions_of_qualified_names(
          repo_id: repo.id,
          network_id: repo.network_id,
          commit_oid: commit_oid,
          qualified_names: qualified_names,
          language: language,
          ref: ref,
          opt_headers: {
            IS_PUBLIC_HEADER => repo.public?.to_s,
            FEATURE_FLAG_HEADER => features,
          },
        )
      end
    end

    # Public: Find the locations of definitions that intersect with the provided line and character (column) ranges for the repo commit.
    # Warning! This uses a slow client and is not intended to be used for user-facing production requests! Please only use in background jobs.
    #
    # repo            - Repository to search.
    # commit_oid      - String commit sha
    # path            - String path to file
    # start_line      - Integer start line
    # start_character - Integer start character
    # end_line        - Integer end line
    # end_character   - Integer end character
    # language        - String language name.
    # backends        - List of backends to search in priority order.
    # ref             - (optional) String ref to search. If no ref is provided, the default branch ref will be used.
    #
    # Returns locations of definitions whose extent or definien's range intersects with the provided start line / end line and start character / end character rnage for the repo / commit oid.
    def self.find_name_by_definiens_location(repo:, commit_oid:, path:, start_line:, start_character:, end_line:, end_character:, language:, backends:, ref: "", features: [])
      with_error_reporting do
        if ref == ""
          ref = T::let(repo.default_branch_ref&.qualified_name, T.nilable(String)) || ""
        end
        slow_client.find_name_by_definiens_location(
          repo_id: repo.id,
          network_id: repo.network_id,
          commit_oid: commit_oid,
          path: path,
          start_line: start_line,
          start_character: start_character,
          end_line: end_line,
          end_character: end_character,
          language: language,
          backends: backends,
          ref: ref,
          opt_headers: {
            IS_PUBLIC_HEADER => repo.public?.to_s,
            FEATURE_FLAG_HEADER => features,
          },
        )
      end
    end

    # Public: Find the symbols matching the given symbol at a specific repo and SHA.
    #
    # repo     - Repository to look in.
    # sha      - The sha to look for tags.
    # symbol   - The symbol to match.
    # language - The language of the repo.
    #
    # Returns a FindSymbolsResponse containing an Array of Definitions (see the Aleph proto file).
    def self.find_symbols(repo:, sha:, query:, language:, features: [])
      with_error_reporting do
        client.find_symbols(
          repo_id: repo.id,
          network_id: repo.network_id,
          root_id: repo.network.root_id,
          repo_owner: repo.owner_display_login,
          repo_name: repo.name,
          sha: sha,
          query: query,
          language: language,
          opt_headers: {
            IS_PUBLIC_HEADER => repo.public?.to_s,
            FEATURE_FLAG_HEADER => features,
           },
         )
      end
    end

    # Public: Find references matching the given symbol at a specific repo and SHA.
    #
    # repo     - Repository to look in.
    # sha      - The sha to look for tags.
    # symbol   - The symbol to match.
    # language - The language of the repo.
    #
    # Returns a FindSymbolsResponse containing an Array of References (see the Aleph proto file) or nil on error.
    def self.find_symbol_references(repo:, sha:, query:, language:, features: [])
      with_error_reporting do
        client.find_symbol_references(
          repo_id: repo.id,
          network_id: repo.network_id,
          root_id: repo.network.root_id,
          repo_owner: repo.owner_display_login,
          repo_name: repo.name,
          sha: sha,
          query: query,
          language: language,
          opt_headers: {
            IS_PUBLIC_HEADER => repo.public?.to_s,
            FEATURE_FLAG_HEADER => features,
           },
         )
      end
    end

    # Public: Find the symbols for a specific repo, SHA, and path.
    #
    # repo     - Repository to look in.
    # sha      - The sha to look for tags.
    # path     - The filepath to look for tags.
    # ref      - String named ref (optional, defaul: nil)
    #
    # Returns a FindSymbolsResponse containing an Array of Definitions (see the Aleph proto file).
    def self.find_symbols_for_path(repo:, sha:, path:, ref: nil, features: [])
      with_error_reporting do
        client.find_symbols_for_path(
          repo_id: repo.id,
          network_id: repo.network_id,
          root_id: repo.network.root_id,
          repo_owner: repo.owner_display_login,
          repo_name: repo.name,
          sha: sha,
          path: path,
          ref: ref,
          opt_headers: {
            IS_PUBLIC_HEADER => repo.public?.to_s,
            FEATURE_FLAG_HEADER => features,
          },
        )
      end
    end

    # Public: Get symbol information about a qualified name.
    #
    # repo                  - Repository to search.
    # commit_oid            - String commit sha
    # language              - String language name
    # ref                   - (optional) String ref to search. If no ref is provided, the default branch ref will be used.
    # fully_qualified_name  - String fully qualified namee
    #
    # Returns a Twirp::ClientResp where #data is a FindSymbolInformationForFullyQualifiedNameResponse (see github/aleph/proto/lsp.proto#FindSymbolInformationForFullyQualifiedNameResponse for more info).
    def self.find_symbol_information_for_fully_qualified_name(repo:, commit_oid:, language:, ref: "", fully_qualified_name:, features: [])
      if ref == ""
        ref = repo.default_branch_ref&.qualified_name || ""
      end
      with_error_reporting do
        slow_client.find_symbol_information_for_fully_qualified_name(
          repo_id: repo.id,
          network_id: repo.network_id,
          commit_oid: commit_oid,
          language: language,
          ref: ref,
          fully_qualified_name: fully_qualified_name,
          opt_headers: {
            IS_PUBLIC_HEADER => repo.public?.to_s,
            FEATURE_FLAG_HEADER => features,
          },
        )
      end
    end

    # Public: Toggle a repo's network to temporarily disable or re-enable it for indexing.
    #
    # repo      - Repository to toggle.
    # operation - String operation to perform. Must be one of "enable" or "disable".
    #
    # Warning! This RPC is used for special situations only, and not suitable for general use without a good understanding of the consequences.
    def self.toggle_repo_network(repo:, operation:)
      if !VALID_OPERATIONS.include?(operation)
        raise InvalidToggleRepoNetworkOperationError.new(operation)
      end
      with_error_reporting do
        client.toggle_repo_network(
          repo_id: repo.id,
          network_id: repo.network_id,
          operation: operation,
          opt_headers: {
            IS_PUBLIC_HEADER => repo.public?.to_s,
          },
        )
      end
    end

    def self.with_error_reporting
      response = yield
      if response.nil?
        Failbot.report(ReportableError.new("Nil response from aleph"), { app: FAILBOT_APP })
      elsif response.error &&
          response.error.code != :canceled &&
          response.error.code != :deadline_exceeded &&
          response.error.code != :not_found &&
          response.error.code != :resource_exhausted
        Failbot.report(ReportableError.new(response.error.msg), { app: FAILBOT_APP }.merge(response.error.to_h))
      end
      response
    rescue *TIMEOUT_ERRORS => e
      # We want to report timeout errors back to the UI.
      Twirp::ClientResp.new(data: nil, error: Twirp::Error.deadline_exceeded("Request timed out"))
    rescue *ERRORS_TO_IGNORE
      nil
    rescue => e # rubocop:todo Lint/GenericRescue
      # These should be fixed, report to failbot
      Failbot.report(e, { app: FAILBOT_APP })
      nil
    end

    def self.client
      @client ||= build_client
    end

    def self.slow_client
      @slow_client ||= build_client(service_name: SLOW_SERVICE_NAME, service_url: SLOW_SERVICE_URL, timeout: SLOW_TIMEOUT)
    end

    def self.build_client(service_name: SERVICE_NAME, service_url: SERVICE_URL, timeout: DEFAULT_TIMEOUT)
      connection = Faraday.new(url: service_url) do |conn|
        conn.use GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: service_name
        conn.use GitHub::FaradayMiddleware::Resilient, name: service_name, options: {
          instrumenter: GitHub,
          sleep_window_seconds: 10,
          error_threshold_percentage: 5,
          window_size_in_seconds: 30,
          bucket_size_in_seconds: 5,
        }
        conn.options[:open_timeout] = 0.1 # connection open timeout in seconds.
        conn.options[:timeout] = timeout  # read timeout in seconds.
        conn.adapter :persistent_excon
      end
      ::Aleph::Client.new(connection, hmac_key: GitHub.aleph_api_hmac_key)
    end

    # Public: Converts a language name to the format used by Aleph's code nav feature flipper format.
    #
    # language_name - language name to convert.
    #
    # Returns a symbol representing a feature flag (e.g. GitHub.flipper[:aleph_language_ruby]).
    def self.convert_language_name(language_name)
      "aleph_language_#{clean_language_name(language_name)}".to_sym
    end

    # Public: Converts a language name to the format used by Aleph's darkship code nav feature flipper format.
    #
    # language_name - language name to convert.
    #
    # Returns a symbol representing a feature flag (e.g. GitHub.flipper[:aleph_darkship_language_ruby]).
    def self.convert_darkship_language_name(language_name)
      "aleph_darkship_language_#{clean_language_name(language_name)}".to_sym
    end

    # Public: Converts a language name to the format used by Aleph's reindex feature flipper format.
    #
    # language_name - language name to convert.
    #
    # Returns a symbol representing a feature flag (e.g. GitHub.flipper[:aleph_reindex_language_ruby]).
    def self.convert_reindex_language_name(language_name)
      "aleph_reindex_language_#{clean_language_name(language_name)}".to_sym
    end

    # Public: Scrubs a Linguist language name to remove special symbols.
    #
    # language_name - language name to sanitize.
    #
    # Returns a sanitized string (e.g. Given "HTML+ERB" this method returns "html_erb").
    def self.clean_language_name(language_name)
      return "csharp" if language_name == "C#"

      language_name&.gsub(INVALID_CHARS, "_")&.downcase
    end

    # Tests are stubbed so that calls to aleph hit this FakeServer instead.
    class FakeServer
      def self.call(env)
        # For now, just return an empty response. Eventually this could be fleshed
        # out to return sensible dummy data.
        [200, { "Content-Type" => "application/protobuf" }, [""]] # Empty response from aleph
      end
    end
  end
end
