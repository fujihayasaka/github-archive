# typed: true
# frozen_string_literal: true

class CreateNewCopilotCodeReviewOrchestration < CopilotCodeReviewOrchestration
  include PullRequests::Orchestrations::DataAttributes

  # def only_save_on_orchestration_end? = true

  data :actor, User

  def head_repository
    @head_repository ||= pull_request!.head_repository
  end

  def base_repository
    @base_repository ||= pull_request!.base_repository
  end

  step :validate_user_has_proper_license do
    copilot_user = Copilot::User.new(actor)
    authorizer = Copilot::Authorizer.new(copilot_user, GitHub.context)

    return :failed, "User is not licensed to use Copilot Code Reviews" unless authorizer.access_allowed?
  end

  step :validate_copilot_code_review_orchestration_can_proceed do
    validate_pull_request_base_repository
    validate_pull_request_head_repository

    return :skipped, errors.first.full_message if errors.present?
  end

  step :get_diff_hunks do
  end

  step :get_linked_issue do
  end

  step :build_code_review_prompt do
  end

  step :generate_code_review_from_copilot_api do
  end

  step :comment_on_pull_request_with_code_review do
  end

  private

  def validate_pull_request_head_repository
    return if errors.present?

    if head_repository.nil?
      errors.add(:head, "No head repository for pull request with id: #{pull_request!.id}")
    end
  end

  def validate_pull_request_base_repository
    return if errors.present?

    if base_repository.nil?
      errors.add(:base, "No base repository for pull request with id: #{pull_request!.id}")
    end
  end
end
