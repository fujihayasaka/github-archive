# typed: true
# frozen_string_literal: true

class Reaction::Summary
  include GitHub::Tracing

  # Public: Preloads Reaction counts
  #
  # items - An Array of items that may have a reaction.
  #
  # Returns nothing.
  def self.prefill(items)
    GitHub.tracer.in_span("reaction/summary.prefill", kind: :internal) do
      items_by_class_name = items.group_by { |i| i.class.name }
      items_by_class_name.slice!(*Reaction.valid_subject_types)

      return if items_by_class_name.empty?

      items_by_class_name.each do |class_name, items|
        subject_ids = items.map(&:id).uniq

        all_reaction_counts =
          if ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(class_name)
            field = "#{class_name.underscore}_id"

            scope = "#{class_name}Reaction".constantize.where("#{field}": subject_ids)
            scope = scope.where(user_hidden: [false, 0]) if GitHub.spamminess_check_enabled?
            scope.group(field, :content).count
          else
            scope = Reaction.where(subject_type: class_name, subject_id: subject_ids)
            scope = scope.where(user_hidden: [false, 0]) if GitHub.spamminess_check_enabled?
            scope.group(:subject_id, :content).count
          end

        items.each do |item|
          item.reactions_count = {}
          Emotion.all.each do |emotion|
            count = all_reaction_counts[[item.id, emotion.content]]
            item.reactions_count[emotion.content] = count if count
          end
        end
      end
    end
  end
end
