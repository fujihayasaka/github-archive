# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class HasReacted < Platform::Loader
      def self.load(user_id, reaction_group)
        self.for(user_id).load(reaction_group)
      end

      def initialize(user_id)
        @user_id = user_id
      end

      def fetch(reaction_groups)
        # reactions which have not been split to their own tables
        subjects = reaction_groups.map(&:subject).uniq
        subjects = subjects.filter { |s| ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.exclude?(s.class.name) }

        # legacy reactions which haven't been split to their own tables (yet)
        found = Reaction.where(subject: subjects, user_id: @user_id).pluck(:subject_type, :subject_id, :content).to_set

        # reactions which have been split to their own tables
        subjects_by_type =
          reaction_groups.
            map(&:subject).uniq.group_by { |s| s.class.name }.
            slice(*::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS)

        subjects_by_type.each do |subject_type, subjects|
          model_class = "#{subject_type}Reaction".constantize
          found.merge(
            model_class.
              where(model_class.subject_association => subjects.map(&:id)).
              where(user_id: @user_id).
              pluck(model_class.subject_association_column_name.to_sym, :content).
              map { |subject_id, content| [subject_type, subject_id, content] }
          )
        end

        reaction_groups.index_with do |reaction_group|
          subject = reaction_group.subject
          found.include?([subject.class.name, subject.id, reaction_group.content])
        end
      end
    end
  end
end
