# typed: true
# frozen_string_literal: true

# Public: A mixin to use on an ActiveRecord model that both:
#   1. can have Reactions attached to it
#   2. belongs to a Repository
module Reaction::Subject::RepositoryContext
  extend ActiveSupport::Concern
  include Reaction::Subject

  def reaction_admin
    T.unsafe(self).repository.owner
  end

  def async_reaction_admin
    T.unsafe(self).async_repository.then do |repo|
      next false unless repo
      repo.async_owner
    end
  end

  def reaction_path
    return @reaction_path if defined?(@reaction_path)
    @reaction_path = async_reaction_path.sync
  end

  def async_reaction_path
    T.unsafe(self).async_repository.then do |repo|
      UrlHelpers.update_repository_reaction_path(repo.owner_display_login, repo)
    end
  end
end
