# typed: true
# frozen_string_literal: true

class UserIdentificationSurveyResponseController < ApplicationController
  include ControllerMethods::AnswerParams
  include SignupHelper
  include DashboardHelper

  # The following actions do not require conditional access checks:
  # - new, create & autocomplete: these actions *don't* access protected organization resources
  #   so they don't require conditional access checks.
  skip_before_action :perform_conditional_access_checks, only: %w(new create autocomplete) # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required
  before_action :find_survey
  before_action :ensure_survey_accessible

  javascript_bundle :organizations
  stylesheet_bundle :signup

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:autocomplete]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new],
    optional: true

  def new
    respond_to do |format|
      format.html do
        view = create_view_model(
          Signup::CustomizeView,
          survey: @survey,
          example_topics: example_topics,
          skip_path: skip_survey_path
        )
        render "signup/customize", locals: { view: view }
      end
    end
  end

  def autocomplete # rubocop:todo GitHub/UseRestfulActions
    tags = Topic.curated
    tags = tags.where("`name` LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%") if params[:q]
    tags = tags.limit(1000).pluck(:name)

    respond_to do |format|
      format.html_fragment do
        render partial: "signup/autocomplete", formats: :html, locals: { tags: tags }
      end
    end
  end

  def create
    if @survey.save_answers(current_user, answer_params)
      topics = Repositories.domain.topics.by_names(names: topic_selections)
      Stars.domain.star_topics(user: current_user, topics: topics.to_a, context: "user identification survey response")
      Onboarding.for(current_user).answered_user_identification_questions!
      GitHub.dogstats.increment("user_identification_survey", tags: ["action:create", "valid:true"])
    else
      GitHub.dogstats.increment("user_identification_survey", tags: ["action:create", "valid:false"])
    end

    respond_to do |format|
      format.html do
        redirect_to_return_to(fallback: skip_survey_path)
      end
    end
  end

  private

  def skip_survey_path
    "/" # this will show the email verification message to users in this group
  end

  def ensure_survey_accessible
    redirect_to dashboard_path unless survey_accessible?
  end

  def survey_accessible?
    !already_taken?
  end

  def already_taken?
    @survey.taken_by?(current_user)
  end

  def github_employee?
    current_user.employee?
  end

  def find_survey
    @survey = Survey.find_by!(slug: "user_identification")
  end

  def topic_selections
    _, answer_with_selections = answer_params.find(
      method(:value_to_return_when_find_returns_nil),
    ) do |_question_id, choices_and_selections|
      choices_and_selections["selections"].present?
    end

    answer_with_selections["selections"] || []
  end

  def value_to_return_when_find_returns_nil
    [nil, {}]
  end

  def example_topics
    Topic.curated.order(Arel.sql("RAND()")).limit(3).pluck(:name)
  end
end
