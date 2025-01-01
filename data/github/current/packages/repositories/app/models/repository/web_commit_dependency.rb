# typed: true
# frozen_string_literal: true

module Repository::WebCommitDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # Internal: Commit a change (create, update, or destroy)
  #
  # Used for high-level user operations such as applying suggested changes, or
  # committing from the web (eg. BlobController, TreeController).
  #
  # See related: `WebCommitControllerMethods`.
  #
  # author       - user making change
  # author_email - email of the user making the change
  # branch       - branch name for this commit
  # files        - Hash of filename => data pairs.
  # message      - message to use for the commit
  # before_oid   - (Optional) Commit oid when proposed change was submitted
  # ref          - (Optional) Explicit ref to be updated (otherwise ref is obtained based on `branch` parameter).
  # reflog_data  - (Optional) Data to be included in reflog.
  # sign         - (Optional) Forwarded to Repository#create_commit
  def commit_change_for_user(
    author:,
    author_email:,
    branch:,
    files:,
    message:,
    before_oid: nil,
    pull_request: nil,
    ref: nil,
    reflog_data: nil,
    sign: true
  )
    return unless ready_for_writes?
    return if branch_being_renamed?(branch)

    ref = heads.find_or_build(branch) if ref.nil?

    # Use the branch's target_oid, or fall back on the supplied old_oid.
    # both can be nil for an absolutely new file in a new repo.
    parent_oid = ref.target_oid || before_oid
    before_oid = ref.target_oid

    commit = begin
      ref.append_commit(
        {
          message:,
          author:,
          author_email:,
        },
        author,
        sign:,
        reflog_data:,
        post_receive: !pull_request,
        target_oid: parent_oid,
      ) do |commit_files|
        files.each do |filename, contents|
          if contents.is_a?(Hash)
            commit_files.move(contents[:from].b, filename.b, contents[:contents].b)
          elsif contents
            commit_files.add(filename.b, contents.b)
          else
            commit_files.remove(filename.b)
          end
        end
      end
    # Accounts for invalid emails being used for web commits in Enterprise mode
    rescue ArgumentError
      nil
    end

    return unless commit

    if pull_request
      pull_request.synchronize!(
        user: author,
        repo: self,
        ref: ref.qualified_name,
        before: before_oid,
        after: commit.oid,
      )
      ref.enqueue_push_job(before_oid, commit.oid, author, ref.written_at, excluded_pull_ids: [pull_request.id])
    end
    [commit.oid, ref.name, nil]
  rescue Git::Ref::HookFailed => e
    err_msg = e.message
    [nil, nil, err_msg]
  rescue Git::Ref::ProtectedBranchUpdateError => e
    err_msg = "#{ref.name} branch is protected"
    [nil, nil, err_msg]
  rescue Git::Ref::RepositoryRuleViolationError => e
    err_msg = e.detailed_message
    [nil, nil, err_msg, e]
  rescue GitRPC::RequestTooLarge
    err_msg = "The input is too large to process. " \
        "Consider commiting your change in a local clone and pushing it to GitHub."
    [nil, nil, err_msg]
  rescue Git::Ref::ComparisonMismatch,
         Git::Ref::InvalidName,
         Git::Ref::UpdateFailed,
         GitHub::DGit::InsufficientQuorumError,
         GitHub::DGit::ThreepcFailedToLock,
         GitHub::DGit::UnroutedError,
         GitRPC::BadGitmodules,
         GitRPC::Failure,
         GitRPC::SymlinkDisallowed
    nil
  end
end
