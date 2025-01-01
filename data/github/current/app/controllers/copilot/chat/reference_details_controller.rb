# typed: true
# frozen_string_literal: true

class Copilot::Chat::ReferenceDetailsController < Copilot::Chat::AbstractChatController
  FILE_TOO_LARGE_ERROR_MESSAGE = "File too large for preview\n\nThis file is %{file_size} which exceeds the %{limit_size} limit for Copilot chat references."
  ERROR_MESSAGE_DISPLAY_LINES = 5

  before_action :require_reference_readable_by_current_user, only: [:create]
  allow_verified_fetch only: [:create]

  def create
    reference = reference_params

    case reference_params[:type]
    when "snippet"
      hydrate_snippet(reference)
    when "file"
      hydrate_file(reference)
    when "file-diff"
      hydrate_file_diff(reference)
    when "symbol"
      hydrate_symbol(reference)
    when "docset"
      hydrate_docset(reference)
    when "repository"
      hydrate_repository(reference)
    end

    render json: reference
  end

  private

  def require_reference_readable_by_current_user
    case reference_params[:type]
    when "snippet", "file", "file-diff", "symbol", "repository"
      render_404 unless repo&.readable_by?(current_user)
    when "docset"
      # TODO: implement authorization for docsets
      render_404
    else
      render json: { error: "Unsupported reference type" }, status: :bad_request
    end
  end

  memoize def repo
    repo_params = reference_params

    if reference_params[:type] == "file-diff"
      repo_params = reference_params[:head] || reference_params[:base]
    end

    Repository.with_name_with_owner(repo_params[:repoOwner], repo_params[:repoName])
  end

  def hydrate_snippet(snippet_reference)
    hydrate_code(snippet_reference, snippet_reference[:range][:start].to_i, snippet_reference[:range][:end].to_i)
  end

  def hydrate_file(file_reference)
    if user_feature_enabled?(:copilot_chat_immersive_full_file_retrieval)
      entry = load_file_entry(file_reference)
      return if user_feature_enabled?(:copilot_chat_immersive_file_size_limit_check) && handle_oversized_file(file_reference, entry)

      file_contents = entry.data
      lines = TreeEntry.split_lines(file_contents)

      range = {
        start: 1,
        end: lines.length
      }

      populate_reference_with_content(file_reference, entry, file_contents, range, range)
    else
      hydrate_code(file_reference, 1, 25)
    end
  end

  def hydrate_file_diff(file_diff_reference)
    file_diff_reference[:repoIsOrgOwned] = repo.owner.organization?
  end

  def hydrate_code(reference, start_line, end_line)
    entry = load_file_entry(reference)

    return if user_feature_enabled?(:copilot_chat_immersive_file_size_limit_check) && handle_oversized_file(reference, entry)

    lines = TreeEntry.split_lines(entry.data)
    lines_in_snippet = end_line - start_line
    lines_in_buffer = [0, (max_code_lines - lines_in_snippet)].max / 2
    range = {
      start: start_line,
      end: [end_line, lines.length].min
    }

    expanded_range = {
      start: [1, start_line - lines_in_buffer].max,
      end: [end_line + lines_in_buffer, lines.length].min
    }

    display_contents = lines[expanded_range[:start] - 1...expanded_range[:end]].join("\n")

    populate_reference_with_content(reference, entry, display_contents, range, expanded_range)
  end

  def load_file_entry(reference)
    # Since commitOIDs are dynamic, we aren't able to populate or stub commitOID in the reference received from copilot-api
    commit_oid = reference[:commitOID]

    if commit_oid.blank? && Rails.env.development?
      commit_oid = repo.default_oid
    end

    repo.tree_entry(commit_oid, reference[:path])
  end

  def handle_oversized_file(reference, entry)
    return false unless entry.size > max_file_size_for_chat

    reference[:repoIsOrgOwned] = repo.owner.organization?
    reference[:contents] = FILE_TOO_LARGE_ERROR_MESSAGE % {
      file_size: number_to_human_size(entry.size),
      limit_size: number_to_human_size(max_file_size_for_chat)
    }
    reference[:range] = { start: 1, end: ERROR_MESSAGE_DISPLAY_LINES }
    reference[:expandedRange] = { start: 1, end: ERROR_MESSAGE_DISPLAY_LINES }
    reference[:headerInfo] = build_header_info(entry, reference)
    true
  end

  def populate_reference_with_content(reference, entry, display_contents, range, expanded_range)
    highlighted_contents = GitHub::Treelights.highlight(entry.language&.tm_scope, display_contents)

    reference[:repoIsOrgOwned] = repo.owner.organization?
    reference[:contents] = display_contents
    reference[:highlightedContents] = highlighted_contents
    reference[:range] = range
    reference[:expandedRange] = expanded_range
    reference[:headerInfo] = build_header_info(entry, reference)
  end

  def build_header_info(entry, reference)
    {
      blobSize: number_to_human_size(entry.size),
      displayName: entry.display_name,
      isLfs: entry.git_lfs?,
      lineInfo: {
        truncatedLoc: entry.viewable? ? entry.truncated_loc : nil,
        truncatedSloc: entry.viewable? ? entry.truncated_sloc : nil,
      },
      rawBlobUrl: TreeEntryRenderHelper.raw_blob_url(current_user, repo, reference[:ref], reference[:path]),
      viewable: entry.viewable? && entry.render_file_type_for_display(:preview),
    }
  end

  def hydrate_symbol(symbol_reference)
    symbol_reference.fetch(:codeNavDefinitions, []).each &method(:hydrate_symbol_definition_or_reference)
    symbol_reference.fetch(:codeNavReferences, []).each &method(:hydrate_symbol_definition_or_reference)
    symbol_reference.fetch(:suggestionDefinitions, []).each &method(:hydrate_symbol_definition_or_reference)
  end

  def hydrate_symbol_definition_or_reference(ref)
    entry = repo.tree_entry(ref[:commitOID], ref[:path])

    line_range = get_line_range(ref, repo, entry)
    highlighted_contents = entry.colorized_lines

    ref[:repoIsOrgOwned] = repo.owner.organization?
    if line_range[:start] && line_range[:end]
      ref[:range] = line_range
      ref[:highlightedContents] = highlighted_contents[line_range[:start] - 1..line_range[:end] - 1]
    end
  end

  def get_line_range(ref, repo, entry)
    start_line = nil
    end_line = nil

    if ref[:extent]
      start_line = ref[:extent][:start][:line] + 1
      end_line = ref[:extent][:end][:line] + 1
    elsif ref[:ident]
      start_line = ref[:ident][:start][:line] + 1
      end_line = ref[:ident][:end][:line] + 1
    elsif ref[:extentOffset]
      start_line = get_line_number_from_byte_offset(entry.data, ref[:extentOffset][:start])
      end_line = get_line_number_from_byte_offset(entry.data, ref[:extentOffset][:end])
    elsif ref[:identOffset]
      start_line = get_line_number_from_byte_offset(entry.data, ref[:identOffset][:start])
      end_line = get_line_number_from_byte_offset(entry.data, ref[:identOffset][:end])
    else
      start_line = nil
      end_line = nil
    end

    {
      start: start_line,
      end: end_line
    }
  end

  def get_line_number_from_byte_offset(file_contents, offset)
    head = file_contents[0...offset]
    lines_in_head = TreeEntry.split_lines(head)
    lines_in_head.length + 1
  end

  def hydrate_docset(docset_reference)
    docset_reference[:hydrated] = true # TODO
  end

  def hydrate_repository(repo_reference)
    repo_reference[:hydrated] = true # TODO
  end

  def max_code_lines
    500
  end

  def max_file_size_for_chat
    2.megabytes
  end

  memoize def reference_params
    try_parse_json_params
    params.require(:reference).permit!
  end

  # CAP is not bypassed here as repo is required by :require_reference_readable_by_current_user
  def resource_for_conditional_access
    return repo if repo
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return repo.owner if repo
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
