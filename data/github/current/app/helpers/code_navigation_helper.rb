# typed: true
# frozen_string_literal: true

module CodeNavigationHelper
  extend T::Helpers
  abstract!

  include HydroHelper

  # Public: Does this blob support code navigation (jump to definition and find all references).
  def blob_supports_code_navigation?(blob)
    return false unless blob
    return false unless aleph_code_navigation_available?

    lang_name = blob&.language&.name
    aleph_code_navigation_viewable?(lang_name)
  end

  # Public: Does this blob support listing symbols (outline of methods and
  # functions defined in the file).
  def blob_supports_listing_symbols?(blob)
    return false unless blob
    return false unless aleph_code_navigation_available?

    aleph_code_navigation_viewable?(blob&.language&.name)
  end

  # Public: Instrument viewing code navigation for a blob
  def instrument_view_code_navigation(viewer:, repo:, blob_supports_listing_symbols:, blob_has_code_symbols:, ref:, language:, backend:, code_nav_context:, retry_backend:)
    event = if blob_has_code_symbols
      "symbols_available"
    elsif blob_supports_listing_symbols
      "symbols_unavailable"
    else
      "language_not_supported"
    end

    repo_visibility = repo.public? ? "public" : "private"
    action = "view_blob_#{event}"

    GitHub.dogstats.increment("blob_view", tags: ["visibility:#{repo_visibility}", "language:#{GitHub::Aleph.clean_language_name(language)}", "action:#{action}"])

    # Only instrument in hydro for views where aleph is available and enabled
    return unless aleph_code_navigation_available?
    GlobalInstrumenter.instrument("code_navigation.#{action}", {
      action: action,
      user_id: viewer&.id, # nil for anonymous users
      repository_id: repo.id,
      ref: ref,
      language: language,
      backend: backend,
      code_nav_context: code_nav_context,
      retry_backend: retry_backend,
    })
  end

  # Public: Helper for hydro click tracking for code navigation links
  def code_navigation_hydro_click_tracking(action, repo:, ref:, language:, backend:, code_nav_context:, retry_backend:,
                                           cross_repo_results_included: :CROSS_REPO_UNKNOWN, in_repo_result_count: 0,
                                           cross_repo_result_count: 0)
    hydro_click_tracking_attributes("code_navigation.#{action}", {
      action: action,
      repository_id: repo.id,
      ref: ref.dup.force_encoding(Encoding::UTF_8),
      language: language,
      backend: backend,
      code_nav_context: code_nav_context,
      retry_backend: retry_backend,
      cross_repo_results_included: cross_repo_results_included,
      in_repo_result_count: in_repo_result_count,
      cross_repo_result_count: cross_repo_result_count,
    })
  end

  # retry_backend returns the next backend to try given the current backend
  # and a list of available backends.
  def retry_backend(current_backend, available_backends)
    backends_order = [:BLACKBIRD, :ALEPH_PRECISE, :ALEPH_PRECISE_PREVIEW, :ALEPH_PRECISE_DEVELOPMENT, :RICH_NAV]
    next_backend = T.let(nil, T.nilable(Symbol))
    if original_index = backends_order.index(current_backend)
      next_index = original_index
      while !next_backend
        next_index += 1

        # If we've reached the end of the possible backends, start from the beginning.
        if next_index >= backends_order.length
          next_index = 0
        end

        # If we've looped around the possible next backends, and we've cycled back
        # to where we originally started,  then return the current backend and stop looping.
        if next_index == original_index
          next_backend = current_backend
        else

          # We're still searching for the next backend. Check the next possible backend
          # until we find a match in the list of available backends, and return the first result.
          next_candidate = backends_order[next_index]
          if candidate_found = available_backends.index(next_candidate)
            next_backend = next_candidate
          end
        end
      end
    else
      # If the current backend is unknown, then default to returning the precise backend.
      next_backend = :ALEPH_PRECISE
    end
    next_backend
  end

  def display_backend_name(backend)
    case backend
    when :ALEPH_PRECISE             then "precise"
    when :ALEPH_PRECISE_PREVIEW     then "precise-preview"
    when :ALEPH_PRECISE_DEVELOPMENT then "precise-development"
    when :RICH_NAV                  then "Code Index"
    when :BLACKBIRD                 then "search-based"
    else "search-based"
    end
  end

  sig { returns(T::Boolean) }
  def aleph_code_navigation_available?; super; end

  sig { params(lang: String).returns(T::Boolean) }
  def aleph_code_navigation_viewable?(lang); super(lang); end
end
