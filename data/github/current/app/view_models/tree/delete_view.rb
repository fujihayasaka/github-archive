# typed: true
# frozen_string_literal: true

class Tree::DeleteView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :branch
  attr_reader :current_tree
  attr_reader :forked_repo
  attr_reader :forked_reason
  attr_reader :last_commit
  attr_reader :parent_repo
  attr_reader :path
  attr_reader :quick_pull
  attr_reader :target_branch

  include WebCommit::PreviewViewMethods

  def action
    "delete"
  end

  def cancel_url
    urls.tree_path(path, branch, parent_repo)
  end

  # Override WebCommit::PreviewViewMethods#new_file?
  def new_file?
    false
  end

  # Creates a "preview" diff of the proposed changes.
  #
  # Follows the same interface as Blob::PreviewView#diff.
  #
  # Returns an instance of Diff or false if unable to create synthetic commit
  def synthetic_commit_diff
    return false unless synthetic_commit
    synthetic_commit.diff
  end

  private

  # Creates a temporary "preview" commit used to display the proposed diff.
  # We're not pointing any refs to this commit, so it'll be garbage collected
  # after our default expiry time (one hour). For more context on this approach,
  # see https://github.com/github/github/issues/33238#issuecomment-56739052.
  #
  # Derived from Blob::PreviewView#synthetic_commit.
  #
  # Returns an instance of Commit or false if unable to create commit
  def synthetic_commit
    @synthetic_commit ||= begin
      # Avoid rare race condition where `last_commit` has been garbage collected,
      # resulting in a new (very broken) commit with an unreachable parent.
      # See https://github.com/github/github/issues/27410#issuecomment-56235332.
      return false unless last_commit
      return false unless current_tree

      parent_repo.create_commit(last_commit,
        message: "Temporary Commit for Preview",
        author: current_user,
        files: { "#{current_tree.path}" => nil },
        skip_rule_evaluation: true,
      )
    end
  end
end
