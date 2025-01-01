# typed: true
# frozen_string_literal: true

class Signup::CustomizeView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :survey, :tags, :example_topics, :skip_path

  # Public: Returns array of SurveyQuestion objects
  # sorted by display order.
  def questions
    survey.questions.where(hidden: false).order(:display_order).includes(:choices)
  end
end
