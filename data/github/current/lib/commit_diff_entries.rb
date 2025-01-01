# typed: true
# frozen_string_literal: true

class DiffEntryChange
  include GitHub::Memoizer

  class UnprocessableError < StandardError; end

  class InvalidAuthorEmail < StandardError; end

  # Adapter class that is useful if your diff data is not in a Diff object
  class DiffEntry
    attr_reader :lines

    def initialize(old_path:, new_path:, lines:, status:)
      @old_path = old_path
      @new_path = new_path
      @lines = lines
      @status = status
    end

    def basic_enumerator
      lines.map do |line|
        DiffLine.new(text: line[:text], current: line[:current], type: line[:type])
      end
    end

    def added?
      @status == "A"
    end

    def deleted?
      @status == "D"
    end

    def modified?
      @status == "M"
    end

    def path
      if added?
        @new_path
      else
        @old_path
      end
    end
  end

  class DiffLine
    attr_reader :text, :current

    def initialize(text:, current:, type:)
      @text = text
      @current = current.to_i
      @type = type
    end

    def addition?
      @type == "ADDITION"
    end

    def deletion?
      @type == "DELETION"
    end
  end

  NEWLINE_REGEXP = Regexp.union(["\r\n", "\r", "\n"])

  attr_reader :pull_request, :tree_name, :repository, :diff_entries

  def initialize(pull_request:, diff_entries:)
    @pull_request = pull_request
    @tree_name = pull_request&.head_ref
    @repository = pull_request&.head_repository
    @diff_entries = diff_entries
    @file_contents = {}

    if @pull_request.blank? || @repository.blank?
      raise ArgumentError, "pull_request and repository must be present"
    end

    # fall back to the base ref and then the default branch if the pr branch has been deleted.
    if !@repository.heads.exist?(@tree_name)
      @tree_name = pull_request.base_ref
      if !@repository.heads.exist?(@tree_name)
        @tree_name = @repository.default_branch
      end
    end
  end

  def build_new_files
    diff_entries.each_with_object({}) do |diff_entry, out|
      path = diff_entry.path

      if diff_entry.deleted?
        out[path] = nil
        next
      end

      if diff_entry.modified?
        blob = blob_at_path(path)
        source = blob.data.split(NEWLINE_REGEXP, -1)
      else
        source = ""
      end

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

  def commit_change_for_user(
    author:,
    author_email: nil,
    branch:,
    files:,
    current_oid:,
    reflog_data:,
    message:,
    description: nil,
    is_quick_pull: false
  )
    unless pull_request.open? || branch != pull_request.head_ref
      raise UnprocessableError.new("Changes can only be made to an open pull request.")
    end

    if author_email.blank?
      author_email = author.default_author_email(repository)
    end

    if author_email
      author_email = validate_author_email!(author, author_email)
    end

    if ref.target_oid != current_oid
      raise UnprocessableError.new("Sorry, the diff is outdated.")
    end

    commit_message = begin
      default_title = String.new
      if files.length == 1
        default_title << "Update #{files.keys.first}".dup.force_encoding("UTF-8").scrub!
      else
        default_title << "Updating #{files.length} files"
      end

      title = (message.presence || default_title).strip

      parts = [title, description]
      parts.reject(&:blank?).join("\n\n")
    end

    result = repository.commit_change_for_user(
      author:,
      author_email:,
      before_oid: current_oid,
      branch:,
      files:,
      message: commit_message,
      pull_request: is_quick_pull ? pull_request : nil,
      reflog_data:
    )

    commit_oid, _branch, _hook_error = result
    raise UnprocessableError.new("Could not apply changes.") unless commit_oid
    result
  end

  # Validate that the email belongs to the user.
  # Raises an error if
  #   - the author_email does not belong to the user
  #   - the author_email is nil or empty string
  # Returns the email if it belongs to the user.
  #
  # @param author [User]
  # @param author_email [String]
  # @return [String]
  def validate_author_email!(author, author_email)
    if author_email.blank?
      raise StandardError.new("No author email provided.")
    end

    user_emails = author.emails.verified.visible.map(&:email)
    if user_emails.include?(author_email)
      return author_email
    end

    # if an EMU user, their email can have a shortcode in
    # their email, hence try again with the shortcode added
    if author.is_enterprise_managed?
      author_email = author.add_emu_shortcode_to_emails(author_email)
      if user_emails.include?(author_email)
        return author_email
      end
    end

    raise InvalidAuthorEmail.new("Invalid author email.")
  end

  memoize def branch
    GitHub::RefShaPathExtractor.new(repository).call(tree_name).first
  end

  memoize def ref
    repository.heads.find(tree_name)
  end

  private

  memoize def current_commit
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
      { truncate: false, limit: 1.megabyte },
    )

    @file_contents[path] = blob
  end

  def line_endings(blob)
    blob&.has_windows_line_endings? ? "\r\n" : "\n"
  end
end
