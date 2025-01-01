# typed: true
# frozen_string_literal: true
class CodeNavController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    only: [:definition, :react_definition]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    only: [:references, :react_references]

  CONDITIONAL_ACCESS_BYPASS_PUBLIC_REPO_ACTIONS = %w(definition references).freeze

  javascript_bundle :"code-nav"

  include BlackbirdControllerMethods

  extend T::Sig

  def definition # rubocop:todo GitHub/UseRestfulActions
    return head 204 unless logged_in?

    language = params[:language] || params[:lang]
    return head 400 unless language

    blob_path = params[:blob_path] || params[:context]
    return head 400 unless blob_path

    ref = params[:ref]
    return head 400 unless ref

    commit_oid = current_repository.ref_to_sha(ref)
    return head 400 unless commit_oid

    row = params[:row].to_i
    col = params[:col].to_i
    return head 400 unless row >= 0 && col >= 0

    return head 204 unless aleph_code_navigation_available?
    return head 204 unless aleph_code_navigation_viewable?(language)

    code_nav_context = params[:code_nav_context] || :UNKNOWN_VIEW

    is_timeout = false
    available_backends = []
    repos_by_location = {}

    response = GitHub::Aleph.text_document_definition(
      repo: current_repository,
      commit_oid: commit_oid,
      path: blob_path,
      row: row,
      col: col,
      query: params[:q],
      search_dependencies: aleph_cross_repo_jump_to_definition_enabled?,
      actor: code_nav_actor,
      backends: backends,
      ref: ref,
      language: language,
      symbol_kind: symbol_kind,
    )

    return head 204 if response.nil?

    is_timeout = is_timeout?(response)
    if is_timeout
      locations = []
      backend = if is_retry?
        force_backend
      else
        # Eventually we want to return the backend responsible for the timeout from `aleph-query`,
        # but the Twirp timeout error response is not flexible enough to include that data.  For now,
        # we guess the backend by using the first backend in the list of available backends to the user.
        backends.first
      end
    elsif is_retry? && response.error&.code == :not_found
      locations = []
      backend = force_backend
    elsif response.error
      # When error code isn't found, node is not found. In this case, we return 204 or show the search partial.
      return head 204
    else
      available_backends = response.data.available_backends
      backend = response.data.backend
      locations = response.data.locations
    end

    repo_visibility = current_repository.public ? "public" : "private"
    GitHub.dogstats.increment("symbol_search", tags: ["visibility:#{repo_visibility}", "language:#{GitHub::Aleph.clean_language_name(language)}"])
    GitHub.dogstats.count("symbol_search.#{repo_visibility}.#{language}.tag_count", locations.length)

    if aleph_cross_repo_jump_to_definition_enabled?
      # We need to be able to map a location to its corresponding Repository,
      # and it's desirable to have a single Repository.find call, so we
      # group_by into a temporary hash and then build the associations in another pass.
      repository_ids = locations.map { |loc| loc.pkg&.repository_id || current_repository.id }.uniq
      repository_map = Repository.where(id: repository_ids).group_by(&:id)
      repos_by_location = locations.each_with_object({}) do |loc, hash|
        repository_id = loc.pkg&.repository_id || current_repository.id
        repos = repository_map[repository_id]
        hash[loc] = repos[0] if repos && repos.size == 1
      end
    else
      # If cross-repo code nav is off, ensure we don't display any cross-repo results we might have yielded from aleph.
      locations.reject! { |loc| loc.pkg && loc.pkg.repository_id != current_repository.id }
    end

    locations_by_path = locations.each_with_object({}) do |loc, hash|
      hash[loc.path] ||= []
      hash[loc.path] << loc
    end

    # Ensure that code-nav results are sorted thusly:
    # - results from this file
    # - results from the same repo (sorted by path)
    # - results from other repos (sorted by nwo then path)
    locations_by_path = locations_by_path.to_a
    if aleph_cross_repo_jump_to_definition_enabled?
      same_repo, external = locations_by_path.partition { |_path, loc| loc.first.pkg&.repository_id == current_repository.id }
      this_file, this_repo = same_repo.partition { |path, _loc| path == blob_path }
      this_repo.sort_by! { |path, _loc| path }
      external.sort_by! { |path, loc| [repos_by_location[loc.first].name_with_display_owner, path] }
      locations_by_path = this_file + this_repo + external
      cross_repo_results_included = :CROSS_REPO_ENABLED
      in_repo_result_count = same_repo.size
      cross_repo_result_count = external.size
    else
      this_file, this_repo = locations_by_path.partition { |path, _loc| path == blob_path }
      this_repo.sort_by! { |path, _loc| path }
      locations_by_path = this_file + this_repo
      cross_repo_results_included = :CROSS_REPO_NOT_ENABLED
      in_repo_result_count = locations_by_path.size
      cross_repo_result_count = 0
    end


    respond_to do |format|
      format.html do
        render "code_navigation/show", layout: false, locals: {
          locations: locations,
          locations_by_path: locations_by_path,
          repos_by_location: repos_by_location,
          available_backends: available_backends,
          backend: backend,
          language: language,
          commit_oid: commit_oid,
          ref: params[:ref],
          blob_path: blob_path,
          query: params[:q],
          row: params[:row].to_i,
          col: params[:col].to_i,
          request_timed_out: is_timeout,
          is_retry: is_retry?,
          code_nav_context: code_nav_context,
          cross_repo_results_included: cross_repo_results_included,
          in_repo_result_count: in_repo_result_count,
          cross_repo_result_count: cross_repo_result_count,
        }
      end
    end
  end

  def references # rubocop:todo GitHub/UseRestfulActions
    return head 204 unless logged_in?

    language = params[:language] || params[:lang]
    return head 400 unless language

    blob_path = params[:blob_path] || params[:context]
    return head 400 unless blob_path

    ref = params[:ref]
    return head 400 unless ref

    commit_oid = current_repository.ref_to_sha(ref)
    return head 400 unless commit_oid

    row = params[:row].to_i
    col = params[:col].to_i
    return head 400 unless row >= 0 && col >= 0

    return head 204 unless aleph_code_navigation_available?
    return head 204 unless aleph_code_navigation_viewable?(language)

    code_nav_context = params[:code_nav_context] || :UNKNOWN_VIEW

    is_timeout = false
    available_backends = []
    repos_by_location = {}

    response = GitHub::Aleph.text_document_references(
      repo: current_repository,
      ref: ref,
      commit_oid: commit_oid,
      path: blob_path,
      row: row,
      col: col,
      query: params[:q],
      search_dependencies: false, # ignored on the aleph-side for now
      actor: code_nav_actor,
      backends: backends,
      language: language,
      symbol_kind: symbol_kind,
    )
    return head 204 if response.nil?
    is_timeout = is_timeout?(response)

    if is_timeout
      locations = []
      backend = if is_retry?
        force_backend
      else
        # Eventually we want to return the backend responsible for the timeout from `aleph-query`,
        # but the Twirp timeout error response is not flexible enough to include that data.  For now,
        # we guess the backend by using the first backend in the list of available backends to the user.
        backends.first
      end
    elsif is_retry? && response.error&.code == :not_found
      locations = []
      backend = force_backend
    elsif response.error
      return head 204
    else
      available_backends = response.data.available_backends
      backend = response.data.backend
      locations = response.data.locations
    end

    locations_by_path = locations.each_with_object({}) do |loc, hash|
      hash[loc.path] ||= []
      hash[loc.path] << loc
    end

    respond_to do |format|
      format.html do
        render "code_navigation/references", layout: false, locals: {
          locations: locations,
          locations_by_path: locations_by_path,
          repos_by_location: repos_by_location,
          available_backends: available_backends,
          backend: backend,
          language: language,
          commit_oid: commit_oid,
          ref: params[:ref],
          blob_path: blob_path,
          query: params[:q],
          row: params[:row].to_i,
          col: params[:col].to_i,
          request_timed_out: is_timeout,
          is_retry: is_retry?,
          code_nav_context: code_nav_context,
        }
      end
    end
  end

  # This is the same as above 'definition', copied (for now)
  # Returns JSON instead of HTML for react app
  def react_definition # rubocop:todo GitHub/UseRestfulActions
    return head 204 unless logged_in?

    language = params[:language] || params[:lang]
    return head 400 unless language

    blob_path = params[:blob_path] || params[:context]
    return head 400 unless blob_path

    ref = params[:ref]
    return head 400 unless ref

    commit_oid = current_repository.ref_to_sha(ref)
    return head 400 unless commit_oid

    row = params[:row].to_i
    col = params[:col].to_i
    return head 400 unless row >= 0 && col >= 0

    return head 204 unless aleph_code_navigation_available_for_react?

    code_nav_context = params[:code_nav_context] || :UNKNOWN_VIEW

    is_timeout = false
    available_backends = []
    repos_by_location = {}

    response = GitHub::Aleph.text_document_definition(
      repo: current_repository,
      commit_oid: commit_oid,
      path: blob_path,
      row: row,
      col: col,
      query: params[:q],
      search_dependencies: aleph_cross_repo_jump_to_definition_enabled?,
      actor: code_nav_actor,
      backends: backends,
      ref: ref,
      language: language,
      symbol_kind: symbol_kind,
    )

    return head 204 if response.nil?

    is_timeout = is_timeout?(response)
    if is_timeout
      locations = []
      backend = if is_retry?
        force_backend
      else
        # Eventually we want to return the backend responsible for the timeout from `aleph-query`,
        # but the Twirp timeout error response is not flexible enough to include that data.  For now,
        # we guess the backend by using the first backend in the list of available backends to the user.
        backends.first
      end
    elsif is_retry? && response.error&.code == :not_found
      locations = []
      backend = force_backend
    elsif response.error
      # When error code isn't found, node is not found. In this case, we return 204 or show the search partial.
      return head 204
    else
      available_backends = response.data.available_backends
      backend = response.data.backend
      locations = response.data.locations
    end

    repo_visibility = current_repository.public ? "public" : "private"
    GitHub.dogstats.increment("symbol_search", tags: ["visibility:#{repo_visibility}", "language:#{GitHub::Aleph.clean_language_name(language)}"])
    GitHub.dogstats.count("symbol_search.#{repo_visibility}.#{language}.tag_count", locations.length)

    if aleph_cross_repo_jump_to_definition_enabled?
      # We need to be able to map a location to its corresponding Repository,
      # and it's desirable to have a single Repository.find call, so we
      # group_by into a temporary hash and then build the associations in another pass.
      repository_ids = locations.map { |loc| loc.pkg&.repository_id || current_repository.id }.uniq
      repository_map = Repository.where(id: repository_ids).group_by(&:id)
      repos_by_location = locations.each_with_object({}) do |loc, hash|
        repository_id = loc.pkg&.repository_id || current_repository.id
        repos = repository_map[repository_id]
        hash[loc] = repos[0] if repos && repos.size == 1
      end
    else
      # If cross-repo code nav is off, ensure we don't display any cross-repo results we might have yielded from aleph.
      locations.reject! { |loc| loc.pkg && loc.pkg.repository_id != current_repository.id }
    end

    locations_by_path = locations.group_by(&:path)
    file_paths = locations_by_path.keys

    # Ensure that code-nav results are sorted thusly:
    # - results from this file
    # - results from the same repo (sorted by path)
    # - results from other repos (sorted by nwo then path)
    locations_by_path = locations_by_path.to_a
    if aleph_cross_repo_jump_to_definition_enabled?
      same_repo, external = locations_by_path.partition { |_path, loc| loc.first.pkg&.repository_id == current_repository.id }
      this_file, this_repo = same_repo.partition { |path, _loc| path == blob_path }
      this_repo.sort_by! { |path, _loc| path }
      external.sort_by! { |path, loc| [repos_by_location[loc.first].name_with_display_owner, path] }
      locations_by_path = this_file + this_repo + external
    else
      this_file, this_repo = locations_by_path.partition { |path, _loc| path == blob_path }
      this_repo.sort_by! { |path, _loc| path }
      locations_by_path = this_file + this_repo
    end

    line_text = locations.map do |location|
      location.first_line.split("\n").first
    end.compact.uniq

    colorized_lines = GitHub::Colorize.highlight_many(
      [Linguist::Language[language].try(:tm_scope)] * line_text.size,
      line_text,
      code_snippet: true
    ).map { |colorized_line| safe_join(colorized_line, "\n") }

    colorized_lines = line_text.zip(colorized_lines).to_h

    payload = locations_by_path.map(&:last).map do |locations|
      locations.filter_map do |loc|
        next if loc.first_line.empty?
        text = colorized_lines[loc.first_line.split("\n").first]
        repo = current_repository

        if aleph_cross_repo_jump_to_definition_enabled? && loc.pkg.repository_id != current_repository.id
          repo = Repository.find_by(id: loc.pkg.repository_id)
        end

        Repos::ReactPayload.code_nav_payload(loc, text, repo)
      end
    end

    def_payload = {
      payload: payload,
      filePaths: file_paths,
      backend: backend
    }

    GlobalInstrumenter.instrument "search.execute", {
      variant: "aleph-#{backend}",
      actor: current_user,
      query: "repo:#{current_repository.nwo} path:#{blob_path} symbol:#{params[:q]}", # rubocop:disable GitHub/DoNotAllowNameWithOwner nwo is expected in instrumentation
      search_type: ["codenav_find_definition"],
      search_context: "web.scoped",
      originating_request_id: GitHub.context[:request_id],
      total_results: locations.length,
    }

    respond_to do |format|
      format.json { render json: Repos::ReactPayload.camelize_keys(def_payload) } # rubocop:disable GitHub/AvoidCamelizeKeys
    end
  end

  # This is the same as above 'references', copied (for now)
  # Returns JSON instead of HTML for react app
  def react_references # rubocop:todo GitHub/UseRestfulActions
    return head 204 unless logged_in?

    language = params[:language] || params[:lang]
    return head 400 unless language

    blob_path = params[:blob_path] || params[:context]
    return head 400 unless blob_path

    ref = params[:ref]
    return head 400 unless ref

    commit_oid = current_repository.ref_to_sha(ref)
    return head 400 unless commit_oid

    row = params[:row].to_i
    col = params[:col].to_i
    return head 400 unless row >= 0 && col >= 0

    return head 204 unless aleph_code_navigation_available_for_react?

    code_nav_context = params[:code_nav_context] || :UNKNOWN_VIEW

    is_timeout = false
    available_backends = []
    repos_by_location = {}

    response = GitHub::Aleph.text_document_references(
      repo: current_repository,
      ref: ref,
      commit_oid: commit_oid,
      path: blob_path,
      row: row,
      col: col,
      query: params[:q],
      search_dependencies: false, # ignored on the aleph-side for now
      actor: code_nav_actor,
      backends: backends,
      language: language,
      symbol_kind: symbol_kind,
    )
    return head 204 if response.nil?
    is_timeout = is_timeout?(response)

    if is_timeout
      locations = []
      backend = if is_retry?
        force_backend
      else
        # Eventually we want to return the backend responsible for the timeout from `aleph-query`,
        # but the Twirp timeout error response is not flexible enough to include that data.  For now,
        # we guess the backend by using the first backend in the list of available backends to the user.
        backends.first
      end
    elsif is_retry? && response.error&.code == :not_found
      locations = []
      backend = force_backend
    elsif response.error
      return head 204
    else
      available_backends = response.data.available_backends
      backend = response.data.backend
      locations = response.data.locations
    end

    line_text = locations.map do |location|
      location.first_line.split("\n").first
    end.compact.uniq

    colorized_lines = GitHub::Colorize.highlight_many(
      [Linguist::Language[language].try(:tm_scope)] * line_text.size,
      line_text,
      code_snippet: true
    ).map { |colorized_line| safe_join(colorized_line, "\n") }

    colorized_lines = line_text.zip(colorized_lines).to_h

    locations_by_path = locations.group_by(&:path)
    file_paths = locations_by_path.keys

    payload = locations_by_path.values.map do |locations|
      locations.map do |loc|
        text = colorized_lines[loc.first_line.split("\n").first]

        Repos::ReactPayload.code_nav_payload(loc, text, current_repository)
      end
    end

    ref_payload = {
      payload: payload,
      filePaths: file_paths,
      backend: backend
    }

    GlobalInstrumenter.instrument "search.execute", {
      variant: "aleph-#{backend}",
      actor: current_user,
      query: "repo:#{current_repository.nwo} path:#{blob_path} symbol:#{params[:q]}", # rubocop:disable GitHub/DoNotAllowNameWithOwner nwo is expected in instrumentation
      search_type: ["codenav_find_references"],
      search_context: "web.scoped",
      originating_request_id: GitHub.context[:request_id],
      total_results: locations.length,
    }

    respond_to do |format|
      format.json { render json: Repos::ReactPayload.camelize_keys(ref_payload) } # rubocop:disable GitHub/AvoidCamelizeKeys
    end
  end

  private

  def is_timeout?(response)
    response.respond_to?(:error) && response.error&.code == :deadline_exceeded
  end

  # The backends to be used for the code nav rpc request.  The order of the backends
  # indicates the priority in which the backends should be queried for code nav data.
  def backends # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @backends ||= begin
      b = []
      if params[:backend].present?
        b << force_backend
      else
        b << :RICH_NAV if aleph_unified_code_nav_enabled?
        b << :ALEPH_PRECISE_DEVELOPMENT if aleph_precise_development_code_nav_enabled?
        b << :ALEPH_PRECISE_PREVIEW if aleph_precise_preview_code_nav_enabled?
        b << :ALEPH_PRECISE
        b << :BLACKBIRD if blackbird_enabled?
      end
      b
    end
  end

  def force_backend
    case params[:backend]
    when "Code Index"           then :RICH_NAV
    when "precise-development"  then :ALEPH_PRECISE_DEVELOPMENT
    when "precise-preview"      then :ALEPH_PRECISE_PREVIEW
    when "precise"              then :ALEPH_PRECISE
    when "search-based"         then :BLACKBIRD
    else
      :ALEPH_PRECISE
    end
  end

  def is_retry?
    params[:backend].present?
  end

  def code_nav_actor
    actor = nil
    if blackbird_enabled?
      actor = ::Search::Blackbird::Client.actor(T.must(current_user), user_session)
    end
    actor
  end

  # Convert a string symbol_kind to the related hydro enum varint value.
  def symbol_kind
    kind = if user_feature_enabled?(:blackbird_better_references)
      params[:symbol_kind] || "SYMBOL_KIND_UNKNOWN"
    else
      "SYMBOL_KIND_UNKNOWN"
    end
    ::Hydro::Schemas::Blackbird::V0::Entities::SymbolKind.resolve(kind.to_sym)
  end
end
