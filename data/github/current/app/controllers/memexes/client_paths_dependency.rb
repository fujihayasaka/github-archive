# typed: strict
# frozen_string_literal: true

module Memexes
  # This module ensures that any controller which includes this module must define data
  # about client paths.
  module ClientPathsDependency
    extend T::Helpers
    interface!

    # Returns a Hash of paths/URLs for the client.
    sig { abstract.returns(T::Hash[Symbol, { url: String }]) }
    def client_paths; end

    sig { abstract.returns(String) }
    def client_search_repositories_path; end

    sig { abstract.returns(String) }
    def client_search_issues_and_pulls_path; end

    sig { abstract.returns(String) }
    def client_count_issues_and_pulls_path; end

    sig { abstract.returns(String) }
    def client_suggested_repositories_path; end
  end
end
