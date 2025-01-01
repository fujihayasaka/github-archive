# typed: true
# frozen_string_literal: true

class DiffEntrySuggestedChange
  class UnprocessableError < StandardError; end
  class NotFoundError < StandardError; end
  class ForbiddenError < StandardError; end

  NEWLINE_REGEXP = Regexp.union(["\r\n", "\r", "\n"])

  attr_reader :pull_request
  attr_reader :tree_name
  attr_reader :repository
  attr_reader :diff_entries
  attr_reader :file_contents

  def initialize(repository:, diff_entries:, pull_request: nil, ref: nil)
    if pull_request.nil? && ref.nil?
      raise ArgumentError, "provide pull_request or ref"
    end

    @pull_request = pull_request
    @tree_name = pull_request ? pull_request.head_ref : ref.qualified_name
    @repository = repository
    @diff_entries = diff_entries
    @file_contents = {}
  end

  def build_new_files
    diff_entries.each_with_object({}) do |diff_entry, out|
      path = diff_entry.path
      blob = blob_at_path(path)

      source = blob.data.split(NEWLINE_REGEXP, -1)
      result = []

      ai = bj = 0

      diff_entry.basic_enumerator.each do |line|
        if line.deletion?
          while ai < line.current - 1
            result << source[ai]
            ai += 1
            bj += 1
          end
          ai += 1
        elsif line.addition?
          while bj < line.current - 1
            result << source[ai]
            ai += 1
            bj += 1
          end
          bj += 1

          result << line.text[1..-1]
        end
      end

      while ai < source.size
        result << source[ai]
        ai += 1
        bj += 1
      end

      out[path] = result.join(line_endings(blob))
    end
  end

  def commit_change_for_user(author:, files: build_new_files, current_oid:, message: nil, co_author_note: nil, reflog_data: nil, sign: false)
    unless repository.pushable_by?(author)
      raise ForbiddenError.new("You don't have permission to apply suggestions on this pull request.")
    end

    if pull_request && !pull_request.open?
      raise UnprocessableError.new("Suggestion can only be applied to open pull requests.")
    end

    author_email = author.default_author_email(repository)
    if author_email && !author.author_emails.include?(author_email)
      raise UnprocessableError.new("Invalid email for web commit.")
    end

    if ref.target_oid != current_oid
      raise UnprocessableError.new("Sorry, the diff is outdated.")
    end

    dco_signoff_enabled = pull_request ? pull_request.dco_signoff_enabled? : repository.dco_signoff_enabled?

    commit_body = begin
      arr = []
      arr << co_author_note
      arr << DcoSignoffHelper.dco_signoff_text(author) if dco_signoff_enabled
      arr.join("\n")
    end

    commit_message = begin
      default_title = String.new
      if files.length == 1
        default_title << "Update #{files.keys.first}".dup.force_encoding("UTF-8").scrub!
      else
        default_title << "Updating #{files.length} files"
      end

      title = (message.presence || default_title).strip

      parts = [title, commit_body]
      parts.reject(&:blank?).join("\n\n")
    end

    result = repository.commit_change_for_user(
      author:,
      author_email:,
      branch:,
      files:,
      message: commit_message,
      pull_request:,
      reflog_data:,
      sign:,
    )

    commit_oid, _branch, hook_error = result
    raise UnprocessableError.new(hook_error) unless commit_oid

    result
  end

  def branch
    return @branch if defined?(@branch)

    @branch = GitHub::RefShaPathExtractor.new(repository).call(tree_name).first
  end

  def ref
    @ref ||= repository.heads.find(tree_name)
  end

  private

  def current_commit
    return @current_commit if defined?(@current_commit)

    commit_sha = repository.ref_to_sha(tree_name)
    @current_commit = commit_sha.presence && repository.commits.find(commit_sha)
  rescue GitRPC::InvalidObject, GitRPC::BadObjectState
    @current_commit = nil
  rescue GitRPC::ObjectMissing
    @current_commit = nil

    # ref points to a missing object, aka repository corruption.
    #
    # it's conceivable that this could be raised mistakenly if we had a bad deploy or
    # an operational problem that caused GitRPC::ObjectMissing to be raised when the
    # objects did in fact exist.
    if ref = repository.refs.find(tree_name)
      raise UnprocessableError.new("ref #{ref.qualified_name} points at missing commit #{ref.target_oid}")
    end

    @current_commit
  end

  def blob_at_path(path)
    return @file_contents[path] if @file_contents.key?(path)
    blob = current_commit && repository.blob(
      current_commit.tree_oid,
      path,
      { truncate: false, limit: 1.megabytes },
    )

    if blob.blank?
      raise NotFoundError.new("This diff has recently been updated.")
    end

    @file_contents[path] = blob
  end

  def line_endings(blob)
    blob.has_windows_line_endings? ? "\r\n" : "\n"
  end
end
