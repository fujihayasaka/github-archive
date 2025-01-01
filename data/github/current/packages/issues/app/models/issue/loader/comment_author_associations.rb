# typed: true
# frozen_string_literal: true

class Issue::Loader::CommentAuthorAssociations < Issue::Loader::Base
  def initialize(context, associables: [])
    @context = context
    @associables = associables
  end

  def self.load_for(context, associables: [])
    super new(context, associables: associables)
  end

  def load
    # Shortcut the loading of the associations if this is a private repository
    filtered = @associables.select do |associable|
      repo = @context.repositories_by_id[associable.repository_id]
      repo.nil? || !repo.private?
    end

    Promise.all(
      filtered.map do |associable|
        CommentAuthorAssociation.new(comment: associable, viewer: @context.viewer).async_to_sym.then do |sym|
          [associable, sym]
        end
      end
    ).sync.each do |associable, sym| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      associable.preload_attr(:author_association_symbol, sym)
    end
  end
end
