# typed: true
# frozen_string_literal: true

require "github/config/kv_dual_write"

module PullRequest::DiffViewDependency
  extend T::Helpers
  extend T::Sig

  requires_ancestor { PullRequest }

  IgnoreWhitespaceKeyTransformer = PullRequests::KV::KeyTransformer.new(
    old_key_pattern: %r(
      \Auser_(?<user_id>\d+)
      \.repo_(?<repository_id>\d+)
      \.pull_request_(?<pr_number>\d+)
      \.ignore_whitespace
      \z
    )x,
    new_key_template: "pull_requests/ignore_whitespace/user%{user_id}.pr%{pr_number}",
  )

  def ignore_whitespace?(current_user)
    return false if !current_user

    ignore_whitespace_kv.exists(ignore_whitespace_key(current_user)).value { false }
  end

  def set_ignore_whitespace_preference(current_user)
    ignore_whitespace_kv.set(ignore_whitespace_key(current_user), "true", expires: 3.months.from_now)
  end

  def clear_ignore_whitespace_preference(current_user)
    ignore_whitespace_kv.del(ignore_whitespace_key(current_user))
  end

  def ignore_whitespace_key(current_user)
    "pull_requests/ignore_whitespace/user#{current_user.id}.pr#{number}"
  end

  private

  sig { returns(GitHub::KV) }
  def ignore_whitespace_kv
    PullRequests::KV.for_repository(T.must(repository))
  end
end
