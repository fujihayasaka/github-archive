# typed: false
# frozen_string_literal: true

class Blob::PreviewView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

  attr_reader :funding_links, :repo, :tree_name, :old_oid, :path, :blobname, :code, :render_url_base, :creates_branch, :responsive, :action, :avoid_diff
  DELETED   = :preview_deleted
  RENAMED   = :preview_renamed
  UNCHANGED = :preview_unchanged
  ERROR     = :preview_error
  BLANK     = :preview_blank

  # semantic accessors

  def displays_funding?
    return false if action == "delete"
    funding_file?
  end

  def displays_html?
    !!display[:html]
  end

  def as_html
    display[:html]
  end

  def displays_diff?
    !!display[:diff]
  end

  def as_diff
    display[:diff]
  end

  def displays_message?
    !!display[:preview_message]
  end

  def as_message
    display[:preview_message]
  end

  def as_message_supplemental_html
    display[:preview_rendered_html]
  end

  def displays_blob?
    !!display[:opaque]
  end

  def displays_viewable_blob?
    !!display[:opaque].try(:[], :viewable?)
  end

  def as_blob
    display[:opaque][:blob]
  end

  def displays_empty?
    display.empty?
  end

  def deleted?
    displays_message? && as_message == DELETED
  end

  def renamed?
    displays_message? && as_message == RENAMED
  end

  def unchanged?
    displays_message? && as_message == UNCHANGED
  end

  def error?
    displays_message? && as_message == ERROR
  end

  def blank?
    displays_message? && as_message == BLANK
  end

  def is_for_a_new_file?
    path.blank? || repo.includes_directory?(path, tree_name)
  end

  def is_for_a_rich_file?
    named? && blob && blob.viewable? && GitHub::Markup.can_render?(blobname, blob.data)
  end

  def display_with_code_rendering_service?
    code_rendering_service&.supports_view?
  end

  def code_rendering_service
    return nil unless blob
    @code_rendering_service ||= CodeRenderingService.for(blob, :preview, current_user)
  end

  private

  # the master method, memoized

  def display
    @display ||= if unstarted?
      render_as_unstarted
    elsif is_for_a_rich_file? && avoid_diff
      render_for_simple_preview
    elsif is_for_a_rich_file?
      render_for_rich_file
    elsif is_a_viewable_file?
      render_for_viewable_file
    elsif is_for_a_new_file?
      render_for_new_code
    else
      render_for_existing_code
    end
  end

  DEFAULT_NAME = "nothing.txt"

  # 'blob' will only be a blob if the current path
  # is to a file
  def blob
    return false if path.blank?
    repo.tree_entry(committish, path)
  rescue GitRPC::NoSuchPath, GitRPC::InvalidFullOid
    nil
  end

  def committish
    old_oid || repo.default_oid
  end

  # high-level methods that delegate to more direct renders

  def render_for_simple_preview
    return render_html(before_html) if after_html == UNCHANGED
    render_html after_html
  end

  def render_for_rich_file

    if after_html == DELETED || after_html.blank?
      if before_html.blank?
        render_as_unstarted
      else
        render_html renderer.diff(before_html, GitHub::HTMLSafeString::EMPTY)
      end
    elsif after_html == RENAMED
      render_message RENAMED, after_html_just_renamed
    elsif after_html == UNCHANGED
      message = helpers.content_tag(:div, id: "readme", class: "readme prose-diff") do # rubocop:disable Rails/ViewModelHTML
        helpers.content_tag(:div, class: "markdown-body#{ responsive ? " p-3 p-md-5 p-xl-6 container-lg" : " px-6 pb-6 pt-4"}") do # rubocop:disable Rails/ViewModelHTML
          renderer.diff(before_html, before_html)
        end
      end

      render_message UNCHANGED, message
    elsif after_html == ERROR
      render_message ERROR
    elsif after_html && before_html.blank?
      render_html after_html
    elsif after_html
      render_html renderer.diff(before_html, after_html)
    else
      render_message ERROR
    end
  end

  def funding_file?
    if path.blank? # new file
      blobname&.downcase == FundingLinks::FILENAME.downcase
    else
      funding_links_path = repo&.funding_links_path || FundingLinks::PATH
      path.downcase == funding_links_path.downcase
    end
  end

  def render_for_viewable_file
    render_as_blob
  end

  def render_for_new_code
    if unstarted?
      render_as_unstarted
    elsif empty?
      render_message BLANK
    else
      begin
        synthetic_oid = synthetic_commit.oid
        te = repo.tree_entry(synthetic_oid, synthetic_path)
        render_as_blob te
      rescue GitRPC::NoSuchPath
        render_message ERROR
      end
    end
  end

  def render_for_existing_code
    return render_message ERROR unless diff

    diff_entry = diff.entries.first

    if diff_entry.nil? && old_name == new_name
      render_message UNCHANGED
    elsif diff_entry.nil?
      render_message RENAMED
    elsif diff_entry.renamed? && diff_entry.similarity == 100
      render_message RENAMED
    else
      { diff: diff }
    end
  end

  # Private Predicates

  def unstarted?
    is_for_a_new_file? && unnamed? && empty?
  end

  def is_a_viewable_file?
    return false unless blob

    renderer.viewable?(blob)
  end

  def unnamed?
    blobname.blank?
  end

  def named?
    !unnamed?
  end

  def empty?
    code.blank?
  end

  # direct render methods

  def render_as_unstarted
    {}
  end

  def render_html(html)
    return render_message ERROR if html.blank?

    { html: html }
  end

  def render_message(message, inner_html = "")
    {
      preview_message: message,
      preview_rendered_html: inner_html,
    }
  end

  def render_as_blob(blob_to_render = blob)
    return render_message ERROR unless blob_to_render

    { opaque: {
        blob: blob_to_render,
        viewable?: is_a_viewable_file?,
      },
    }
  end

  def render_as_diff
    return render_message ERROR unless diff

    { diff: diff }
  end

  # Creates a diff for the 'Preview' function of the
  # code editor. Validates that tree_name is a current branch
  #
  # Returns: An instance of Diff, or:
  #          false if tree_name is invalid, or:
  #          false if path is invalid.
  def diff(new_blob_name = name_for_diff)
    synthetic_commit(new_blob_name) && synthetic_commit(new_blob_name).diff
  end

  def synthetic_commit(new_blob_name = name_for_diff)
    (@synthetic_commit ||= {})[new_blob_name || ""] ||= begin
      repo.heads.find(tree_name)
      # Avoid rare race condition where `last_commit` has been garbage collected,
      # resulting in a new (very broken) commit with an unreachable parent.
      # See https://github.com/github/github/issues/27410#issuecomment-56235332.
      return false unless old_oid

      if is_for_a_new_file?
        commit_path = synthetic_path(new_blob_name)
        files = { commit_path => (code || "") }
      else
        # Avoid same race condition as above.
        return false unless blob
        current_path = blob.path
        new_blob_name = blob.name if new_blob_name.blank?

        directory = File.dirname(current_path)
        commit_path = directory == "." ? new_blob_name : File.join(directory.b, new_blob_name.b)

        files = if blob.name.b == new_blob_name.b
          { current_path => code.presence }
        else
          { commit_path => { from: current_path, contents: code } }
        end
      end

      repo.create_commit(old_oid,
        message: "Temporary Commit for Preview",
        author: current_user,
        files: files,
        skip_rule_evaluation: true,
      )
    end
  end

  # Helpers for generating rich previews

  def before_blob
    @current_blob_value ||= is_for_a_new_file? ? nil : blob
  end

  def before_html
    return GitHub::HTMLSafeString::EMPTY unless before_blob

    before_path = before_blob.path || ""

    if GitHub::Markup.can_render?(before_path, before_blob.data)
      renderer.rich_blob(before_blob)
    else
      renderer.rich_blob(
        decorate_tree_entry(before_blob, "path" => new_path),
      )
    end
  end

  def after_html_just_renamed
    if before_blob
      renderer.rich_blob(decorate_tree_entry(before_blob, path: new_path))
    else
      GitHub::HTMLSafeString::EMPTY
    end
  end

  def after_html
    @after_html = if after_blob_for_rich_preview.kind_of?(Symbol)
      after_blob_for_rich_preview
    else
      @after_html ||= renderer.rich_blob(after_blob_for_rich_preview)
    end
  end

  def after_blob_for_rich_preview
    @after_blob_for_rich_preview ||= if code.blank? && is_for_a_new_file?
      UNCHANGED
    elsif code.blank?
      DELETED
    else
      if diff(blobname)
        entries = diff(blobname).entries
        if entries.empty?
          UNCHANGED
        else
          diff_entry = entries.find { |e| e.renamed? || e.b_blob }
          if diff_entry.nil?
            ERROR
          elsif diff_entry.renamed? && diff_entry.similarity == 100
            RENAMED
          else
            diff_head_blob(diff_entry, repo)
          end
        end
      else
        ERROR
      end
    end
  end

  # Creates a synthetic copy of a tree_entry,
  # and merges in some overriding properties
  def decorate_tree_entry(blob, overrides)
    repository, info = blob.repository, blob.info
    TreeEntry.new(repository, info.merge(overrides))
  end

  # Helpers for generating diffs

  def old_name
    blob.try(:name) || ""
  end

  def new_name
    blobname || ""
  end

  # If view.blob.name != view.blobname, git will do a similarity
  # analysis and decide that there has been a delete and create rather than
  # a rename if the dissimilarity exceeds a threshold (50% by default).
  #
  # The result is a preview broken into two distinct chunks with their own headers.
  # This is ugly and/or confusing for users who believe they are making one change
  # to one file.
  #
  # But when previewing a web blob edit, we know that the user intends this
  # to be a rename of one file, so we want the resulting preview to only
  # display edits to one chunk as often as possible.
  #
  # We could sidestep the entire process by ignoring any renaming when creting
  # a preview, however we do syntax-highlight diffs, and in the case where a file
  # has been renamed in such a way that its extension changes, its syntax
  # highlighting may also change. This will show up if the changes involve
  # adding any new lines of code.
  def name_for_diff
    if is_for_a_new_file?
      # When it's a new file, we use the new name if available.
      blobname.presence || DEFAULT_NAME
    elsif File.extname(old_name) == File.extname(new_name)
      # when the extension has not been changed (including the degerate case
      # of no name change taking place at all), we are not concerned with
      # syntax hilighting any added lines (if any) in a new way, because
      # the new way would be the same as the current way.
      old_name
    elsif empty?
      # when all of the text has been deleted, we are not concerned with
      # syntax-highlighting any added lines in a new way. Because there
      # are no added lines. So we prefer the old name.
      old_name
    else
      # For all other cases (the extension has been changed, and there
      # is some new text), we want to maintain information about the current
      # and changed name so that syntax hilighting correctly displays
      # added lines (if any). So we prefer the new name.
      new_name
    end
  end

  def old_path
    blob.info["path"]
  end

  def new_path
    if File.dirname(old_path) == "."
      new_name
    else
      File.join(File.dirname(old_path.b), new_name.b)
    end
  end

  def synthetic_path(new_blob_name = name_for_diff)
    new_blob_name = "test.txt" if new_blob_name.blank?
    directory = path
    (directory == "." || directory.blank?) ? new_blob_name : File.join(directory.b, new_blob_name.b)
  end

  def diff_head_blob(diff, repository = nil)
    TreeEntry.new(repository || head_repository, {
      "oid" => diff.b_blob,
      "path" => diff.b_path,
      "mode" => diff.b_mode,
      "type" => "blob",
    })
  end

  # isolate our dependence on controller helpers to render rich blobs

  def renderer
    @renderer ||= Renderer.new(
      path: path,
      tree_name: tree_name,
      current_repository: repo,
      render_url_base: render_url_base,
      current_user: current_user,
    )
  end

  class Renderer

    include UrlHelper
    include TextHelper
    include BlobMarkupHelper
    include FailbotHelper
    include BlobHelper
    include ColorHelper

    attr_reader :path, :tree_name, :current_repository, :render_url_base, :current_user

    def initialize(path:, tree_name:, current_repository:, render_url_base:, current_user:)
      @path, @tree_name, @current_repository, @render_url_base, @current_user = path, tree_name, current_repository, render_url_base, current_user
    end

    def rich_blob(blob)
      markup_blob_content_if_successful(blob, context)
    end

    def diff(before_html, after_html)
      GitHub::HTML::Diff.new(before_html, after_html, render_url_base: render_url_base).html
    end

    def viewable?(blob)
      blob.viewable? && blob.render_file_type_for_display(:preview)
    end

    def logged_in?
      !!current_user
    end

    private

    def context
      { path: path, committish: tree_name, view: :blob, sanitize_orphan_hrefs: true, use_sourcepos: true }
    end

    sig { override.returns(T.nilable(ActionDispatch::Request)) }
    def request
      nil
    end

  end

end
