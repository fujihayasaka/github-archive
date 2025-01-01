# typed: true
# frozen_string_literal: true

module CodeNav
  # The CodeNav::BlobSymbolsComponent lists symbol definitions (e.g., methods,
  # functions) found in a blob to enable quick code navigation.
  class BlobSymbolsComponent < ApplicationComponent
    # Known states for this component based on availability of the code nav
    # services, indexing status, configured feature flags, and if the blob is in
    # one of the supported code nav langauges.
    STATES = {
      ok: {
        color: "green",
        msg: "Code navigation index up-to-date",
      },
      error_index_not_found: {
        color: "light-gray",
        msg: "Code navigation not available for this commit",
      },
      error_index_unreachable: {
        color: "red",
        msg: "Unable to reach the code navigation service",
      },
      error_internal: {
        color: "red",
        msg: "Internal error in the code navigation service",
      },
      index_requested: {
        color: "yellow",
        msg: "Code navigation indexing in progress…",
      },
    }.freeze

    def initialize(code_nav:, language:)
      @code_nav = code_nav
      @language = language
    end

    attr_reader :code_nav, :language

    delegate :backend, :state, :current_repository, :current_user, :tree_name, :code_symbols, :has_code_symbols?, :code_nav_context, to: :code_nav

    # Hydro click tracking attrs for individual blob symbol links (select menu items).
    memoize def navigate_to_definition_hydro_attrs
      helpers.code_navigation_hydro_click_tracking("navigate_to_blob_definition",
          repo: current_repository, ref: tree_name, language: language, backend: backend, code_nav_context: code_nav_context, retry_backend: "")
    end

    def symbol_path(symbol)
      "#{helpers.blob_path(symbol.path, tree_name, current_repository)}#L#{symbol.row}"
    end
  end
end
