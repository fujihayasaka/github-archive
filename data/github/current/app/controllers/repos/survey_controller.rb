# typed: false
# frozen_string_literal: true

class Repos::SurveyController < AbstractRepositoryController
  before_action :login_required, :find_survey

  include Repos::CodeViewHelper

  def index
    return render_404 unless request.xhr?

    if code_view_enabled?
      questions = []
      @survey.questions.map do |question|
        questions << {
          id: question.id,
          choices: question.choices.map { |choice| { id: choice.id, text: choice.text, display_order: choice.display_order, question_id: choice.question_id } },
          text: question.text,
          hidden: question.hidden,
          shortText: question.short_text,
          displayOrder: question.display_order,
          isRequired: required?(question)
        }
      end
      survey_payload = {
        questions: questions
      }
      render json: survey_payload.to_json
    else
      render Repositories::SurveyComponent.new(survey: @survey, return_to: referrer, user: current_user, repository: current_repository),
    layout: false
    end
  end

  def answer # rubocop:todo GitHub/UseRestfulActions
    answers = answer_params[:answers].to_h
    Repository::Survey::answered_survey(current_user)
    saved = @survey.save_answers(current_user, answers)

    flash[:notice] = "Thank you for sharing your feedback!"
    safe_redirect_to answer_params[:return_to]
  end

  def dismiss # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?

    Repository::Survey::dismiss_survey(current_user)

    head :ok
  end

  def answer_params # rubocop:todo GitHub/UseRestfulActions
    # Because the answer format is {question_id => {"choice" => choice_id}} we need to create
    # a Hash with keys that match our question IDs. This allows us to filter input params.
    acceptable_input = @survey.questions.pluck(:id).map { |id| [id.to_s, {}] }.to_h

    params.permit(:authenticity_token, :user_id, :repository, :return_to, answers: acceptable_input)
  end

  def find_survey # rubocop:todo GitHub/UseRestfulActions
    @survey = Survey.find_by_slug(Repository::Survey::SURVEY_SLUG)
  end

  def required?(question) # rubocop:todo GitHub/UseRestfulActions
    # Copied from app/components/repositories/survey_component.rb
    %w[file_browsing file_editing branch_creation general_satisfaction].include?(question.short_text)
  end
end
