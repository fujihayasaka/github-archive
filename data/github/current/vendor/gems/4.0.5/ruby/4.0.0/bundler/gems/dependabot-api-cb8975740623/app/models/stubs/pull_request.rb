# frozen_string_literal: true
# typed: strong

require "sorbet-runtime"

module Stubs
  class PullRequest < T::Struct
    extend T::Sig

    prop :repo, Repo
    prop :github_number, Integer

    delegate :account, to: :repo

    sig { returns(String) }
    def github_url
      "#{repo.github_url}/pull/#{github_number}"
    end
  end
end
