# typed: true
# frozen_string_literal: true

module Configurable
  module CodespaceDotfilesRepository
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    KEY = "codespace_dotfiles_repository"

    def codespace_dotfiles_repository
      repo_id = config.get(KEY)
      if repo_id.present?
        Repositories::Public.find_active!(repo_id)
      else
        repo = T.unsafe(self).find_repo_by_name("dotfiles")
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def update_codespace_dotfiles_repository(repo_id, force = false, actor:)
      raise ActiveRecord::RecordNotFound unless repo_id.nil? || Repositories::Public.find_active!(repo_id).owner == self

      changed = if repo_id.nil?
        config.delete(KEY, actor)
      else
        config.set!(KEY, repo_id, actor, force)
      end
      return unless changed

      GitHub.dogstats.increment("codespace_dotfiles_repository.updated")
    end
  end
end
