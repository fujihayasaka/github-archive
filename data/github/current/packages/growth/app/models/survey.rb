# typed: false
# frozen_string_literal: true

class Survey < ApplicationRecord::Domain::Surveys
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations

  has_many :questions, class_name: "SurveyQuestion", dependent: :destroy
  has_many :answers, class_name: "SurveyAnswer"
  has_many :groups, class_name: "SurveyGroup"

  validates :slug, unicode3: true
  validates :slug, uniqueness: { case_sensitive: false }, if: -> { errors[:slug].blank? }
  validates :title, unicode3: true

  scope :sponsors_organization_waitlist, -> { where(slug: Sponsors::OrganizationWaitlistSurvey::SLUG) }

  # Public: Whether or not to show a survey to a user.
  #
  # Define survey-specific classes in app/models/survey/<slug>.rb. E.g:
  #
  # class Survey::BurningQuestions
  #   def self.show_survey?(user)
  #     # Your logic here...
  #   end
  # end
  def self.show_survey?(slug:, user:)
    survey = "Survey::#{slug.camelize}".constantize
    survey && survey.show_survey?(user) && one_percent?(user, slug)
  rescue NameError
    # No survey-specific logic defined: always show the survey
    true
  end

  # Internal: Does this user's ID fall inside 1% of users who could take this survey?
  def self.one_percent?(user, survey_slug)
    # Use the survey_slug as the salt
    hashed_id = Zlib.crc32(user.id.to_s + survey_slug)
    hashed_id % 100 < 1 # Show the survey to 1% of users
  end

  def to_param
    "#{id}-#{slug}"
  end

  # Public: Whether or not the user has submitted any answers.
  # Returns a Boolean.
  def taken_by?(user)
    answers.where(user_id: user.id).exists?
  end

  # Which questions have been answered by a certain user
  #
  # Returns array of SurveyQuestion objects
  def questions_answered_by(user)
    answers.includes(:question).where(user_id: user.id).collect(&:question)
  end

  # Which questions are yet to be answered by a certain user
  #
  # Returns array of SurveyQuestion objects
  def questions_to_answer(user)
    questions - questions_answered_by(user)
  end

  # Next question to be answered by user
  #
  # Returns an SurveyQuestion object, or nil
  def next_question_for(user)
    questions_to_answer(user).first
  end

  # Get the answers for questions a user has submitted
  #
  # Returns array of SurveyAnswer objects
  def answers_for(user)
    answers.where(user_id: user.id)
  end

  # Order position of question in survey
  #
  # Returns an int, or nil
  def question_num(question = nil)
    return nil if !question
    questions.index(question) + 1
  end

  # Public: Save a collection of SurveyAnswers on the survey.
  #
  # user         - a User
  # answers_hash - a Hash keyed by SurveyQuestion ID
  #                with value of SurveyChoice answer(s)
  # {
  #   "42" => {
  #     "choice" => "96"
  #   },
  #   "43" => {
  #     "choice" => "101",
  #     "other" => { "101" => "ruby, rubygems, machine-learning"}
  #   },
  #   "44" => {
  #     "choices" => ["101", "102", "103"]
  #     "other" => { "102" => "other text for choice 102"}
  #   }
  # }
  #
  # Returns an array of SurveyAnswers if successful, false otherwise.
  def save_answers(user, answers)
    self.answers << answers.flat_map do |question_id, answer|
      question = questions.find_by_id(question_id)
      next unless question

      choices = find_choices(question, answer["choice"] || answer["choices"])

      choices.map do |choice|
        build_answer(
          user: user,
          question: question,
          choice: choice,
          other_text: answer.dig("other", choice.id.to_s),
          selections: answer["selections"],
        )
      end
    end.compact
  end

  def respondents_count(current_user)
    if GitHub.flipper[:devtools_survey_respondents_count].enabled?(current_user)
      begin
        answers.count("DISTINCT user_id")
      rescue ActiveRecord::QueryCanceled => qcex
        GitHub.dogstats.increment("devtools.surveys.respondents_count_timeout", tags: ["survey_slug:#{slug}"])
        -1
      end
    else
      answers.count("DISTINCT user_id")
    end
  end

  def csv_dump
    if groups.exists?
      export_groups
    else
      export_answers
    end
  end

  def batch_csv_dump(offset, limit)
    if groups.exists?
      batch_export_groups(offset, limit)
    else
      batch_export_answers(offset, limit)
    end
  end

  def active_questions
    questions.where(hidden: false).order(:display_order).includes(:choices)
  end

  private

  def batch_export_groups(offset, limit)
    responses = groups.order("user_id").offset(offset).limit(limit).includes(:user, :answers)
    generate_group_csv(responses)
  end

  def export_groups
    responses = groups.includes(:user, :answers)
    generate_group_csv(responses)
  end

  # Private: Generates CSV payload for SurveyGroups
  #
  # groups  - SurveyGroups including SurveyAnswer
  #
  # Returns a formated CSV payload of SurveyGroups
  def generate_group_csv(groups)
    CSV.generate do |csv|
      headers = %w(user_id user_country answered_on)
      question_headers = questions.map do |q|
        q.hidden? ? [q.short_text] : [q.text, "Other: " + q.text]
      end.flatten
      csv << headers + question_headers

      groups.each do |groups|
        user = groups.user
        location = GitHub::Location.look_up(user.last_ip)
        row = []
        row << user.id
        row << location[:country_name]
        row << groups.created_at

        answers_by_question = groups.answers.group_by(&:question_id)
        questions.each do |question|
          answers = answers_by_question[question.id] || []
          if question.hidden?
            row << answers.map { |answer| answer.other_text }.compact.join(";")
          else
            row << answers.map { |answer| answer.choice&.text }.compact.join(";")
            row << answers.map { |answer| answer.other_text }.compact.join(";")
          end
        end

        csv << row
      end
    end
  end

  def batch_export_answers(offset, limit)
    answers_by_user = answers.order("user_id").offset(offset).limit(limit).includes(:user, :question, :choice).group_by(&:user)
    generate_answers_csv(answers_by_user)
  end

  def export_answers
    answers_by_user = answers.includes(:user, :question, :choice).group_by(&:user)
    generate_answers_csv(answers_by_user)
  end

  # Private: Generates CSV payload for answers
  #
  # answers_by_user  - Hash of SurveyAnswer grouped by Users
  #
  # Returns a formated CSV payload of SurveyAnswers
  def generate_answers_csv(answers_by_user)
    data = CSV.generate do |csv|
      headers = %w(user_id user_country answered_on user_login)
      question_headers = questions.map do |q|
        q.hidden? ? [q.short_text] : [q.text, "Other: " + q.text]
      end.flatten
      csv << headers + question_headers

      answers_by_user.each do |user, answers|
        location = GitHub::Location.look_up(user.last_ip)

        data = []
        data << user.id
        data << location[:country_name]
        data << answers.first.created_at
        data << user.login

        answers_by_question_id = answers.group_by(&:question_id)
        questions.each do |question|
          answers = answers_by_question_id[question.id] || []
          if question.hidden?
            data << answers.map { |answer| answer.other_text }.compact.join(";")
          else
            data << answers.map { |answer| answer.choice&.text }.compact.uniq.join(";")
            data << answers.map { |answer| answer.other_text }.compact.join(";")
          end
        end

        csv << data
      end
    end
  end

  # Private: Builds a new SurveyAnswer object.
  #
  # user       - a User
  # question   - a SurveyQuestion
  # choice     - a SurveyChoice
  # other_text - a String
  # selections - an Array
  #
  # Returns a SurveyAnswer object.
  def build_answer(user:, question:, choice:, other_text: nil, selections: nil)
    answers.build do |a|
      a.user       = user
      a.question   = question
      a.choice     = choice

      if selections
        a.selections = selections
      else
        a.other_text = other_text
      end
    end
  end

  # Private: Finds specified choices for a question.
  #
  # question   - a SurveyQuestion
  # choice_ids - an Array of Integers
  #
  # Returns an Array of SurveyChoice objects.
  def find_choices(question, choice_ids)
    question.choices.where(id: choice_ids)
  end
end
