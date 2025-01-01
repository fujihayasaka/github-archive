# typed: true
# frozen_string_literal: true

class PullRequests::SurveyController < AbstractRepositoryController
  before_action :login_required
  before_action :check_feature_flag
  before_action :find_survey, except: :dismiss

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:fragment]

  def fragment # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    render PullRequests::SurveyComponent.new(survey: @survey, return_to: referrer, user: current_user, repository: current_repository),
      layout: false
  end

  def answer # rubocop:todo GitHub/UseRestfulActions
    answers = answer_params[:answers].to_h
    saved = @survey.save_answers(current_user, answers)

    flash[:notice] = "Thank you for sharing your feedback!"
    safe_redirect_to answer_params[:return_to]
  end

  def dismiss # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?

    PullRequest::Survey.hide_for(current_user)

    head :ok
  end

  private

  def target_for_conditional_access
    # using user instead of repo, because repo name and owner only get used for creating the path
    # this controller is asking users for feedback on improving PRs
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    current_user
  end

  def find_survey
    @survey = Survey.find_by(slug: PullRequest::Survey::SLUG)
  end

  def answer_params
    # Because the answer format is {question_id => {"choice" => choice_id}} we need to create
    # a Hash with keys that match our question IDs. This allows us to filter input params.
    acceptable_input = @survey.questions.pluck(:id).map { |id| [id.to_s, {}] }.to_h

    params.permit(:authenticity_token, :user_id, :repository, :return_to, answers: acceptable_input)
  end

  def check_feature_flag
    return render_404 unless user_feature_enabled?(:pr_satisfaction_survey)
  end
end
