# typed: strict
# frozen_string_literal: true

# methods to mix into the MemexProjectModel
module MemexProject::IssuesGraphDependency
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { MemexProject }

  # Public: the representation of a project key that the issues graph knows about
  #
  # Returns a Hash
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_hierarchy_model_key
    {
      ownerId: owner_id,
      itemId: id
    }
  end

  # Public: the representation of a project that the issues graph knows about
  #
  # Returns a Hash
  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def to_hierarchy_model
    url_value = url

    unless url_value.present?
      GitHub.logger.info(
        "MemexProject#to_hierarchy_model returned nil due to missing owner",
        "code.namespace": "MemexProject::IssuesGraphDependency",
        "code.function": "to_hierarchy_model",
        "gh.memex.project.id": self.id,
      )
      return nil
    end

    {
      key: to_hierarchy_model_key,
      creatorId: creator_id,
      # Force encoding to UTF-8 as we aren't confident that all memex titles and
      # descriptions are utf-8 (and may instead be ASCII-8BIT)
      title: title&.force_encoding(Encoding::UTF_8),
      description: description&.force_encoding(Encoding::UTF_8),
      public: self.public,
      number: number,
      userHidden: user_hidden,
      url: url_value.to_s
    }
  end
end
