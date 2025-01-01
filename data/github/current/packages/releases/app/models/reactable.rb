# typed: true
# frozen_string_literal: true

module Reactable
  extend ActiveSupport::Concern
  include GitHub::BatchMethod
  extend T::Helpers

  SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS = Set.new(%w[
    CommitComment
    Issue
    IssueComment
    PullRequestReview
    PullRequestReviewComment
  ]).freeze

  class_methods do
    # List of allowed emotions, it can be overridden if subject wants to filter out
    def emotions
      Emotion.all
    end

    def reactions_by_reactable_ids(ids)
      T.bind(self, T::Class[Reactable])
      # On a PullRequest, a reaction is created on the corresponding issue so subject_id and subject_type correspond to the issue
      subject_type = self.name == "PullRequest" ? "Issue" : "#{self.name}"

      if ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(subject_type)
        field = "#{subject_type.underscore}_id"
        "#{subject_type}Reaction".constantize.
          where("#{field}": ids).
          select(field, :content, :user_id).
          group_by { |record| record[field] }
      else
        Reaction.
          where(subject_id: ids).
          where(subject_type: subject_type).
          select(:subject_id, :content, :user_id).
          group_by(&:subject_id)
      end
    end

    def reactions_by_reactable_ids_for_emotion(ids, emotion)
      T.bind(self, T::Class[Reactable])
      # On a PullRequest, a reaction is created on the corresponding issue so subject_id and subject_type correspond to the issue
      subject_type = self.name == "PullRequest" ? "Issue" : "#{self.name}"

      if ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(subject_type)
        field = "#{subject_type.underscore}_id"
        "#{subject_type}Reaction".constantize.
          where("#{field}": ids).
          select(field).
          where(content: emotion).
          group(field.to_sym).
          count
      else
        Reaction.
          where(subject_id: ids).
          where(subject_type: subject_type).
          where(content: emotion).
          group(:subject_id).
          count
      end
    end
  end

  included do
    extend GitHub::ResilienceMixin
    # since sorbet cannot find reactions_by_reactable_ids, use T.bind to ignore the sorbet type check
    T.bind(self, T.untyped)

    #returns a hash grouped by reaction content, ex.. {"heart"=>["user-8f30b9ada11bde2cc321021d"]}
    batch_method(:prelude_user_logins_by_reaction) do |reactables|
      reactions_by_reactable_id = reactions_by_reactable_ids(reactables.map(&:reactable_id))
      user_ids = reactions_by_reactable_id.values.flatten.map(&:user_id).uniq
      user_logins_by_user_id = User.where(id: user_ids).to_h { |user| [user.id, user.display_login] }

      reactables.index_with do |reactable|
        reactions_by_content = reactions_by_reactable_id[reactable.reactable_id]&.group_by(&:content) || {}
        reactions_by_content.transform_values do |reactions|
          reactions.map { |reaction| user_logins_by_user_id[reaction.user_id] }
        end
      end
    end

    batch_method(:prelude_viewer_can_react) do |reactables, viewer|
      promises = reactables.map { |reactable| reactable.async_viewer_can_react?(viewer) }
      results = with_database_error_fallback(fallback: [false] * reactables.count) do
        Promise.all(promises).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      reactables.zip(results).to_h
    end

    batch_method(:prelude_reaction_count_for_reaction) do |reactables, emotion|
      ids = reactables.map(&:reactable_id)
      reactions = reactions_by_reactable_ids_for_emotion(ids, emotion)
      result = {}
      reactables.each do |reactable|
        result[reactable] = reactions[reactable.reactable_id] || 0
      end

      result
    end

  end

  def viewer_can_react?(viewer)
    return @viewer_can_react if defined? @viewer_can_react
    async_viewer_can_react?(viewer).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def async_viewer_can_react?(viewer)
    ::Reaction.async_viewer_can_react?(viewer, self)
  end

  def reaction_groups
    return @reaction_groups if defined?(@reaction_groups)
    async_reaction_groups.sync
  end

  def async_reaction_groups
    Platform::Loaders::ReactionGroups.load(self)
  end

  def reactable_id
    # since sorbet cannot find id, use T.bind to ignore the sorbet type check
    T.bind(self, T.untyped)
    id
  end
end
