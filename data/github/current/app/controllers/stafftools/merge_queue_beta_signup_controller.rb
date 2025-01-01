# typed: true
# frozen_string_literal: true

class Stafftools::MergeQueueBetaSignupController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  RESULTS_PER_PAGE = 25

  def index
    survey_answers = SurveyAnswer.
      where(survey: MergeQueueBeta::Survey.find_survey).
      preload(:user).
      order(created_at: :asc)

    total_requests = survey_answers.count

    if params[:query].present?
      other_text = SurveyAnswer.arel_table[:other_text]
      survey_answers = survey_answers.where(other_text.matches("%#{params[:query].strip}%"))
    end

    # .paginate here to limit the number of extra queries we need to make
    # below, but we'll still pass this collection onto the view so that we can
    # show pagination controls
    survey_answers = survey_answers.paginate(page: current_page, per_page: RESULTS_PER_PAGE)

    requests = survey_answers.map do |survey_answer|
      repository_nwo = survey_answer.other_text

      # This results in additional queries for each survey answer, but we made
      # a small mistake in building the survey by not capturing a
      # repository_id.
      #
      # We think that this is a reasonable workaround given 1) it's
      # stafftools, and 2) our other option is to rebuild the form and write a
      # transition for the existing data.
      repository = Repository.nwo(repository_nwo)
      next unless repository.present? # In case the repository has been renamed

      organization = repository.owner
      requesting_user = survey_answer.user

      # Only one EarlyAccessMembership can exist per user per organization
      early_access_membership = EarlyAccessMembership.merge_queue_waitlist.find_by(member: organization, actor: requesting_user)

      {
        organization: organization,
        repository: repository,
        requested_at: survey_answer.created_at.to_date,
        requesting_user: requesting_user,
        early_access_membership: early_access_membership
      }
    end.compact

    render "stafftools/merge_queue_beta_signup/index", locals: {
      requests: requests,
      survey_answers: survey_answers, # Only provided for pagination details
      total_requests: total_requests
    }
  end

  # Onboarding for the Merge Queue private beta is per-repository, and we intend
  # to give users the option to enable Merge Queue on a repository that's
  # different from the one that they submitted with their waitlist access
  # request. Rather than build a whole UI for
  # modifying/updating/feature-enabling here, we're going to offload that work
  # to https://devportal.githubapp.com/feature-flags/merge_queue/overview and use the
  # `feature_enabled` attribute of the EarlyAccessMembership model as an
  # additional place to track fulfilled requests.
  def mark_onboarded # rubocop:todo GitHub/UseRestfulActions
    early_access_membership = EarlyAccessMembership.find(params[:early_access_membership])
    early_access_membership.update!(feature_enabled: true, invitation_sent_at: Time.current)

    redirect_to stafftools_merge_queue_beta_signup_path,
                notice: "Successfully marked #{early_access_membership.member.name} as onboarded"
  end
end
