# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCommitsTest < GitHub::TestCase

  fixtures do
    @user   = create(:user, login: "commit-controller-test")

    @repo   = create(:repository, name: "commit-api", owner: @user, from_example: :mojombo_grit)

    @commit = @repo.default_oid
    @path   = "lib/grit.rb"
  end

  test "a wrong oid returns false" do
    commit = @repo.create_commit("b1e00f072e7f34c19323aa58fbc7d9668e14ec44",
      message: "Changes made to a bad parent_oid",
      author: @user,
      files: { @path => "begin; end\n" },
    )
    refute commit
  end

  test "sets committer when present" do
    committer = create :user
    commit = @repo.create_commit(@commit,
      message: "Changes made to a bad parent_oid",
      author: @user,
      files: { @path => "begin; end\n" },
      committer: committer,
    )

    assert_equal commit.committer, committer
  end

  test "unchanged data produces a diff with no entries" do
    unchanged_data = old_data = @repo.blob(@commit, @path).data

    commit = @repo.create_commit(@commit,
      message: "No changes made",
      author: @user,
      files: { @path => unchanged_data },
    )
    diff = commit.diff

    refute_nil diff
    assert_empty diff.entries
  end

  test "nil data produces a diff with a delete" do
    commit = @repo.create_commit(@commit,
      message: "Delete",
      author: @user,
      files: { @path => nil },
    )
    diff = commit.diff

    refute_nil diff
    refute_empty diff.entries

    entry = diff.entries.first

    assert_nil entry.b_blob
  end

  test "text data produces a diff that isn't a delete" do
    commit = @repo.create_commit(@commit,
      message: "Replace text",
      author: @user,
      files: { @path => "begin; end\n" },
    )
    diff = commit.diff

    refute_nil diff
    refute_empty diff.entries

    entry = diff.entries.first

    refute_nil entry.b_blob
    assert_equal "100644", entry.b_mode
    assert_equal "@@ -1,27 +1 @@\n-$:.unshift File.dirname(__FILE__) # For use/testing when no gem is installed\n-\n-# core\n-\n-# stdlib\n-\n-# internal requires\n-require 'grit/lazy'\n-require 'grit/errors'\n-require 'grit/git'\n-require 'grit/head'\n-require 'grit/commit'\n-require 'grit/tree'\n-require 'grit/blob'\n-require 'grit/actor'\n-require 'grit/diff'\n-require 'grit/repo'\n-\n-module Grit\n-  class << self\n-    attr_accessor :debug\n-  end\n-  \n-  self.debug = false\n-  \n-  VERSION = '0.1.0'\n-end\n\\ No newline at end of file\n+begin; end", entry.text
  end

  if GitHub.choose_commit_email_enabled?
    test "can provide custom author_email" do
      author_email = create(:user_email, user: @user, state: "verified").email
      commit = @repo.create_commit(
        @commit,
        message: "Replace text",
        author: @user,
        files: { @path => "begin; end\n" },
        author_email: author_email,
      )

      assert commit.valid?
      assert_equal author_email, commit.author_email
      assert_equal @user.login, commit.author_name
      assert_equal @user, commit.author
    end
  else
    test "cannot provide custom author email" do
      author_email = create(:user_email, user: @user, state: "verified").email
      commit = @repo.create_commit(
        @commit,
        message: "Replace text",
        author: @user,
        files: { @path => "begin; end\n" },
        author_email: author_email,
      )
      refute commit
    end
  end

end
