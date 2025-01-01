# typed: strict
# frozen_string_literal: true

module Stratocaster
  class Domain < GH::Domain::Base
    extend T::Sig

    # Public: Generates the Stratocaster event key for Repositories.
    sig { params(repo: Repositories::IRepository, options: T::Hash[Symbol, Symbol]).returns(String) }
    def repo_event_key(repo, options = {})
      case options[:type]
      when :issues then "repo:#{repo.id}:issues"
      when :network then "network:#{repo.network_id}:public"
      when nil then "repo:#{repo.id}"
      else
        raise ArgumentError, "Invalid :type"
      end
    end

    # Public: Drop events for a repository
    sig { params(repo: Repositories::IRepository, options: T::Hash[Symbol, Symbol]).void }
    def drop_repo_events(repo, options = {})
      return if repo.new_record?

      GitHub.stratocaster.delete_timelines(repo_event_key(repo, options))
    end
  end
end
