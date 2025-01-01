# typed: true
# frozen_string_literal: true

class CodeNavController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    only: [:react_definition, :react_references]

  javascript_bundle :"code-nav"

  include Search::Blackbird::Features

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

    response = ::BlackbirdSearch::Client.text_document_definition(
        user: T.must(current_user),
        actor: T.must(code_nav_actor),
        symbol_name: params[:q],
        repo: current_repository,
        commit_oid:,
        path: blob_path,
        row:,
        col:,
        ref:,
        language:,
        symbol_kind:,
    )

    return head 204 if response.nil?

    locations = if is_timeout?(response) || is_retry_and_not_found?(response)
      []
    elsif response.error || response.data.nil?
      return head 204
    else
      response.data.body&.locations&.to_a || []
    end

    repo_visibility = current_repository.public ? "public" : "private"
    GitHub.dogstats.increment("symbol_search", tags: ["visibility:#{repo_visibility}", "language:#{BlackbirdSearch::CodeNav.clean_language_name(language)}"])
    GitHub.dogstats.count("symbol_search.#{repo_visibility}.#{language}.tag_count", locations.length)

    locations_by_path = locations.group_by(&:path)
    file_paths = locations_by_path.keys

    # Ensure that code-nav results are sorted thusly:
    # - results from this file
    # - results from the same repo (sorted by path)
    locations_by_path = locations_by_path.to_a
    this_file, this_repo = locations_by_path.partition { |path, _loc| path == blob_path }
    this_repo.sort_by! { |path, _loc| path }
    locations_by_path = this_file + this_repo

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
        Repos::ReactPayload.code_nav_payload(loc, text, repo)
      end
    end

    def_payload = {
      payload: payload,
      filePaths: file_paths,
      backend: :BLACKBIRD,
    }

    GlobalInstrumenter.instrument "search.execute", {
      variant: "aleph-BLACKBIRD",
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

    response = ::BlackbirdSearch::Client.text_document_references(
        user: T.must(current_user),
        actor: T.must(code_nav_actor),
        symbol_name: params[:q],
        repo: current_repository,
        commit_oid:,
        path: blob_path,
        row:,
        col:,
        ref:,
        language:,
        symbol_kind:,
    )

    return head 204 if response.nil?

    locations = if is_timeout?(response) || is_retry_and_not_found?(response)
      []
    elsif response.error || response.data.nil?
      return head 204
    else
      response.data.body&.locations&.to_a || []
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
      backend: :BLACKBIRD,
    }

    GlobalInstrumenter.instrument "search.execute", {
      variant: "aleph-BLACKBIRD",
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

  sig { params(response: Twirp::ClientResp[T.untyped]).returns(T::Boolean) }
  def is_timeout?(response)
    response.error&.code == :deadline_exceeded
  end

  sig { params(response: Twirp::ClientResp[T.untyped]).returns(T::Boolean) }
  def is_retry_and_not_found?(response)
    # For historical reasons, whether a request is a retry is indicated by the presence of a :backend
    # parameter in the request parameters (which otherwise goes unused).
    T.cast(params[:backend].present?, T::Boolean) && response.error&.code == :not_found
  end

  sig do
    returns(T.nilable(::Blackbird::Query::V1::Actor))
  end
  def code_nav_actor
    ::BlackbirdSearch::Client.actor(T.must(current_user), user_session, request.remote_ip) if blackbird_enabled?
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
