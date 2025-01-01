# rubocop:disable GitHub/DoNotAllowNameWithOwner
# typed: true
# frozen_string_literal: true

class Copilot::Chat::RepositoryReferencesController < Copilot::Chat::AbstractChatController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    only: [:show]

  before_action :ensure_feature_enabled

  VALID_ITEM_TYPES = [:repository, :issue, :pull_request, :discussion, :file].freeze

  def show
    return head :not_found unless item_payload
    render json: item_payload
  end

  private

  memoize def item_payload
    return nil unless repository.present?

    case item_type
    when :repository
      repository_reference(repository)
    when :issue
      issue = repository.issues.find_by(number: item_number) if item_number.present? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      issue_reference(issue) if issue&.readable_by?(current_user)
    when :pull_request
      pull_request = repository.issues.with_pull_requests.find_by(number: item_number)&.pull_request if item_number.present? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      pull_request_reference(pull_request) if pull_request&.readable_by?(current_user)
    when :discussion
      discussion = repository.discussions.find_by(number: item_number) if item_number.present?
      discussion_reference(discussion) if discussion&.readable_by?(current_user)
    when :file
      oid = repository.default_oid
      path = item_id
      # throws GitRPC::NoSuchPath if the item is not found
      entry = repository.tree_entry(oid, path) rescue nil if path.present?
      tree_entry_reference(entry, oid) if entry
    else
      nil
    end
  end

  memoize def repository
    return nil unless nwo.present?
    repo = Repository.with_name_with_owner(nwo)
    return repo if repo&.readable_by?(current_user)
    nil
  end

  def nwo
    return nil unless params[:owner].present? && params[:name].present?
    "#{params[:owner]}/#{params[:name]}"
  end

  def item_type
    return :repository unless params[:type].present?
    type_value = params[:type].to_sym
    return type_value if VALID_ITEM_TYPES.include?(type_value)
    nil
  end

  def item_id
    return nil unless params[:id].present?
    params[:id]
  end

  def item_number
    item_id&.to_i
  end

  def ensure_feature_enabled
    return if current_user&.feature_enabled?(:copilot_chat_autocomplete)
    render_404
  end

  def resource_for_conditional_access
    repository || self
  end

  def target_for_conditional_access
    # repository can be nil, we return a 404 in that case and there is no TFCA
    repository&.target_for_conditional_access || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end

# rubocop:enable GitHub/DoNotAllowNameWithOwner
