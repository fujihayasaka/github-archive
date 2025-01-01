# typed: true
# frozen_string_literal: true

class PullRequestReviewComment

  # Public: A Plain Old Ruby Object (PORO) used for applying a suggested change proposed in the comment body
  class ApplySuggestedChange
    class UnprocessableError < StandardError; end
    class NotFoundError < StandardError; end
    class ForbiddenError < StandardError; end

    # inputs - Hash containing attributes to apply a suggestion
    # inputs[:message] (optional) - The suggested change commit message
    # inputs[:remote_ip] - The remote ip using the current session
    # inputs[:pull_request] - The PullRequest to apply suggestions to.
    # inputs[:changes] - The list of suggested changes to apply, each change a Hash of:
    #                    comment: The PullRequestReviewComment with the suggested change.
    #                    path: The file path to be changed.
    #                    suggestion: (optional) The contents of the suggested change. If not provided
    #                                we assume the line is to be deleted.
    # inputs[:user_agent] - The user agent using the current session
    # inputs[:sign]       - Whether to try signing the resulting commit.
    def self.call(inputs)
      new(inputs).call
    end

    def initialize(inputs)
      @message          = inputs.fetch(:message, nil)
      @changes          = inputs.fetch(:changes)
      @current_oid      = inputs.fetch(:current_oid)
      @viewer           = inputs.fetch(:viewer)
      @remote_ip        = inputs.fetch(:remote_ip)
      @user_agent       = inputs.fetch(:user_agent)
      @suggesters       = changes.map { |c| c[:comment]&.user }.compact.uniq { |c| c.id }
      @pull_request     = inputs.fetch(:pull_request)
      @tree_name        = pull_request&.head_ref
      @repository       = pull_request&.head_repository
      @sign             = inputs.fetch(:sign, false)
    end

    NEWLINE_REGEXP = Regexp.union(["\r\n", "\r", "\n"])

    def call
      if changes.blank?
        raise UnprocessableError.new("Sorry, you must apply one or more suggested changes.")
      end

      if pull_request.blank? || repository.blank?
        raise UnprocessableError.new("Sorry, the changes couldn't be applied.")
      end

      author_email = viewer.default_author_email(repository)
      if author_email && !viewer.author_emails.include?(author_email)
        raise UnprocessableError.new("Invalid email for web commit.")
      end

      if ref.target_oid != current_oid
        if first_change = changes.first
          instrument_suggestion_applied(first_change[:comment], first_change[:path], "DIFF_OUTDATED")
        end
        raise UnprocessableError.new("Sorry, the diff is outdated.")
      end

      changes.each do |change|
        validate_applicable_suggested_changes!(
          comment: change[:comment],
          path: change[:path],
          suggestion: change[:suggestion]
        )
      end

      changes_by_path = changes.group_by { |c| c[:path] }

      # Validate no overlapping suggestions made it through the UI
      changes_by_path.each do |_path, changes|
        line_numbers = changes.flat_map { |c| c[:comment].current_line_range.to_a }

        if line_numbers.length != line_numbers.uniq.length
          bad_line_number = (line_numbers | line_numbers.uniq).first
          bad_change = changes.find do |c|
            c[:comment].current_line_range.include?(bad_line_number)
          end
          instrument_suggestion_applied(bad_change[:comment], bad_change[:path], "OVERLAPPING_SUGGESTIONS")
          raise UnprocessableError.new("Applying multiple suggestions to the same line is not supported.")
        end
      end

      changed_contents_by_path = changes_by_path.reduce({}) do |contents, (path, changes)|
        path_blob = blob_at_path(path, changes.first[:comment])
        content_lines = path_blob.data.split(NEWLINE_REGEXP, -1)

        # Apply each suggestion last-line-first to avoid suggestions overwriting one another
        changes.sort_by! { |c| -c[:comment].current_line }

        changes.each do |change|
          replace_line(content_lines, at: change[:comment].current_line, start_position_offset: change[:comment].start_position_offset,  with_value: change[:suggestion])
        end

        contents[path] = content_lines.join(line_endings(path_blob))
        contents
      end

      commit_oid, _branch, _hook_error = repository.commit_change_for_user(
        author: viewer,
        author_email: viewer.default_author_email(repository),
        branch: branch,
        files: changed_contents_by_path,
        message: commit_message,
        pull_request: pull_request,
        reflog_data: request_reflog_data("suggested change"),
        sign: @sign,
      )

      raise UnprocessableError.new("Could not apply suggestion.") unless commit_oid

      changes.each do |change|
        resolve_thread(change[:comment])
        instrument_suggestion_applied(change[:comment], change[:path], nil, commit_oid)
      end

      nil
    end

    private

    attr_reader :changes,
                :message,
                :pull_request,
                :repository,
                :tree_name,
                :current_oid,
                :viewer,
                :user_agent,
                :remote_ip,
                :suggesters

    def validate_applicable_suggested_changes!(comment:, path:, suggestion:)
      if comment.pull_request_id != pull_request.id
        instrument_suggestion_applied(comment, path, "PULL_REQUEST_MISMATCH")
        raise UnprocessableError.new("Applying suggestions on multiple pull requests is not supported.")
      end

      thread = comment.async_pull_request_review_thread.sync
      outdated_thread = if repository.feature_flag_enabled?(:prx_comment_outside_the_diff, default: false) || repository&.owner.feature_flag_enabled?(:prx_comment_outside_the_diff, default: false)
        case thread.latest_positioning
        when nil # no new positioning format to utilize
          comment.outdated?
        when PullRequests::CommentPosition::Positions::Indeterminate, PullRequests::CommentPosition::Positions::Errored
          true
        else
          false
        end
      else
        comment.outdated?
      end

      if outdated_thread
        instrument_suggestion_applied(comment, path, "COMMENT_OUTDATED")
        raise NotFoundError.new("Comment is outdated.")
      end

      if comment.on_file?
        instrument_suggestion_applied(comment, path, "FILE_LEVEL_COMMENT")
        raise UnprocessableError.new("Applying suggestions on file-level comments is not supported.")
      end

      if comment.selection_contains_deletions?
        instrument_suggestion_applied(comment, path, "DELETED_LINE")
        raise UnprocessableError.new("Applying suggestions on deleted lines is currently not supported.")
      end

      if comment.pending?
        instrument_suggestion_applied(comment, path, "PENDING_COMMENT")
        raise UnprocessableError.new("Suggestions cannot be applied on pending reviews.")
      end

      if branch.blank? || ref.blank?
        instrument_suggestion_applied(comment, path, "BRANCH_DELETED")
        raise NotFoundError.new("This branch has recently been deleted.")
      end

      if !repository.includes_file?(path, ref.name)
        instrument_suggestion_applied(comment, path, "FILE_NOT_FOUND")
        raise NotFoundError.new("File not found in repository.")
      end

      if !pull_request.open?
        instrument_suggestion_applied(comment, path, "PULL_REQUEST_CLOSED_OR_MERGED")
        raise UnprocessableError.new("Suggested changes can only be applied to open pull requests.")
      end

      if !pull_request.suggested_change_applicable_by?(viewer)
        instrument_suggestion_applied(comment, path, "VIEWER_UNAUTHORIZED")
        raise ForbiddenError.new("You don't have permission to apply suggestions on this pull request.")
      end

      if comment.original_selection.map { |line| line.sub(/\A[+ -]/, "") } == suggestion
        raise UnprocessableError.new("Suggestion cannot be identical to original text.")
      end
    end

    def resolve_thread(comment)
      thread = comment.async_pull_request_review_thread.sync
      thread.resolve(resolver: viewer)
    rescue ActiveRecord::RecordInvalid => e
      Failbot.report(e)
    end

    def commit_message
      default_title = String.new
      if changes.length == 1
        default_title << "Update #{changes.first[:path]}".dup.force_encoding("UTF-8").scrub!
      else
        default_title << "Updating #{changes.length} files"
      end

      title = (message.presence || default_title).strip

      parts = [title, commit_body]
      parts.reject(&:blank?).join("\n\n")
    end

    def commit_body
      coauthors = suggesters.reject { |s| s.id == viewer.id }
      arr = coauthors.map { |author| byline(author) }
      arr << DcoSignoffHelper::dco_signoff_text(@viewer) if @pull_request.dco_signoff_enabled?
      arr.join("\n")
    end

    def byline(author)
      author_name, author_email = User.git_author_info(author)
      author_email = author.default_author_email(repository) || author_email
      "Co-authored-by: #{[author_name, "<#{author_email}>"].reject(&:blank?).join(" ")}"
    end

    def branch
      @branch ||= GitHub::RefShaPathExtractor.
        new(repository).
        call(tree_name).
        first
    end

    def ref
      @ref ||= repository.heads.find(tree_name)
    end

    def current_commit
      return @current_commit if defined?(@current_commit)

      commit_sha = repository.ref_to_sha(tree_name)
      @current_commit = commit_sha.presence && repository.commits.find(commit_sha)
    rescue GitRPC::InvalidObject, GitRPC::BadObjectState
      current_commit = nil
    rescue GitRPC::ObjectMissing
      current_commit = nil
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

    def blob_at_path(path, comment)
      @blobs_at_paths ||= {}
      @blobs_at_paths[path] ||= begin
        blob = current_commit && repository.blob(
          current_commit.tree_oid,
          path,
          { truncate: false, limit: 1.megabyte },
        )

        if blob.blank?
          instrument_suggestion_applied(comment, path, "BLOB_OUTDATED")
          raise NotFoundError.new("This diff has recently been updated.")
        end

        blob
      end
    end

    def line_endings(blob)
      blob.has_windows_line_endings? ? "\r\n" : "\n"
    end

    def replace_line(lines, at:, start_position_offset:, with_value:)
      unless (0..lines.length - 1).cover?(at)
        raise UnprocessableError.new("Suggested changes can only be applied to valid lines.")
      end

      line_count = start_position_offset || 0

      first_line = at - line_count
      if with_value.blank?
        lines.slice!(first_line..at)
      else
        lines[first_line..at] = with_value
      end

      lines
    end

    def request_reflog_data(via)
      {
        real_ip: remote_ip,
        repo_name: repository.name_with_owner,
        repo_public: repository.public?,
        user_login: viewer.login,
        user_agent: user_agent,
        from: GitHub.context[:from],
        via: via,
      }
    end

    def instrument_suggestion_applied(comment, path, error = nil, commit_sha = nil)
      GlobalInstrumenter.instrument("suggested_change.applied",
        repository: repository,
        repository_owner: repository.owner,
        pull_request: pull_request,
        comment: comment,
        actor: viewer,
        issue: pull_request.issue, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        file_extension: path.split(".").last,
        error: error,
        commit_sha: commit_sha,
      )
    end
  end
end
