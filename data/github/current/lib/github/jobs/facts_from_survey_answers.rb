# typed: false
# frozen_string_literal: true

# Map survey answers to one or more facts about the respondee.
module GitHub
  module Jobs
    module FactsFromSurveyAnswers
      def facts
        survey_answers.flat_map(&SurveyAnswer.method(:to_facts))
      end

      def survey_answers
        raise NotImplementedError
      end

      class Fact
        attr_reader :dimension, :value, :recorded_at

        # Public: Instantiate a fact.
        #
        #   dimension   - The Symbol or String dimension name.
        #   value       - The Object value.
        #   recorded_at - A Time identifying when the fact was recorded (optional).
        #
        def initialize(dimension:, value:, recorded_at:)
          @dimension   = dimension
          @value       = value
          @recorded_at = recorded_at
        end
      end

      class SurveyAnswer
        def self.to_facts(answer)
          new(answer).to_facts
        end

        def initialize(answer)
          @answer = answer
        end

        # Public: Transform the answer into an array of facts.
        #
        # Returns an Array of Facts.
        def to_facts
          if contains_multiple_selections?
            answer.selections.map do |selection|
              Fact.new(
                dimension: dimension,
                value: selection,
                recorded_at: recorded_at
              )
            end
          else
            Fact.new(
              dimension: dimension,
              value: value,
              recorded_at: recorded_at
            )
          end
        end

        private

        attr_reader :answer

        # Private: Does the answer value take the form of an array of selections?
        # Currently, this only applies to the "interests" question.
        #
        # Returns a Boolean.
        def contains_multiple_selections?
          answer.question.short_text == "interests"
        end

        def dimension
          answer.question.short_text
        end

        def value
          answer.choice.other? ? answer.other_text : answer.choice.short_text
        end

        def recorded_at
          answer.created_at
        end
      end
    end
  end
end
