# typed: true
# frozen_string_literal: true

class EditRepositories::TagProtectionController < AbstractRepositoryController
  include TextHelper
  include ReactHelper

  before_action :ensure_user_can_edit_repo_protections
  before_action :ensure_protected_tags_available, except: [:index]
  before_action :ensure_plan_supports_rules, only: [:import]
  before_action :sudo_filter, only: [:delete, :import]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new, :index],
    optional: true

  def index
    render "edit_repositories/pages/tag_protection/index",
      locals: { existing_imports: current_repository.existing_imported_ruleset_names }
  end

  def new
    render "edit_repositories/pages/tag_protection/new"
  end

  def check_pattern # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        rule = RepositoryTagProtectionState.new({ repository_id: current_repository.id, pattern: params[:value], enabled: true })
        return head :ok unless !rule.valid? && rule.errors[:pattern].any?

        safe_pattern = sanitize_html(rule.pattern)

        if rule.errors.details[:pattern].any? { |err| err[:error] == :taken }
          error_message = "#{safe_pattern} is already in use"
        else
          error_message = "#{safe_pattern} is not a valid pattern"
        end

        render body: error_message, status: 422
      end
    end
  end

  def create
    unless params[:pattern].present?
      flash[:error] = "You must provide a pattern to create a tag protection rule."
      return redirect_to action: :new
    end

    state = current_repository.create_tag_protection_state(pattern: params[:pattern])
    unless state.valid?
      flash[:error] = "There was an error creating your tag protection rule."
      return redirect_to action: :new
    end

    flash[:notice] = "Tag protection rule created."
    redirect_to action: :index
  end

  def delete # rubocop:todo GitHub/UseRestfulActions
    unless params[:tag_protection_id].present?
      flash[:error] = "You must provide a tag protection rule id to delete."
      return redirect_to action: :index
    end

    state = RepositoryTagProtectionState.find_by(repository_id: current_repository.id, id: params[:tag_protection_id])
    if state
      state.destroy
      flash[:notice] = "Tag protection rule deleted."
    else
      flash[:error] = "Tag protection rule not found."
    end

    redirect_to action: :index
  end

  def import # rubocop:todo GitHub/UseRestfulActions
    single_ruleset = case params[:create_rulesets]
    when "single"
      true
    when "multiple"
      false
    end

    if single_ruleset.nil?
      # This would really only happen if the user is modifying the XHR payload somehow
      flash[:error] = "Invalid payload (create_rulesets)"
      return redirect_to action: :index
    end

    begin
      result = current_repository.import_tag_protections_to_rulesets(current_user, single_ruleset:)
    rescue ActiveRecord::RecordInvalid, RepositoryRuleset::ParametersValidationError, RepositoryRuleset::RuleValidationError => e
      log_import_error(e, single_ruleset)

      flash[:error] = e.message
      return redirect_to action: :index
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      log_import_error(e, single_ruleset)
      raise
    end

    if result.present?
      flash[:notice] = if single_ruleset
        "One ruleset matching current tag protects has been created. You may now delete your protected tags."
      else
        "Two rulesets matching current tag protects has been created. You may now delete your protected tags."
      end
    end

    redirect_to repository_rulesets_path
  end

  private

  def log_import_error(e, single_ruleset)
    GitHub.logger.error(
      "Failed importing tag protections",
      {
        "gh.repo.tag_protection.single_ruleset" => single_ruleset,
        "gh.repo.id" => current_repository.try(:id),
        "gh.repo.owner.id" => current_repository.try(:owner).try(:id),
        "gh.business.id" => current_repository.try(:owner).try(:business).try(:id),
        "gh.actor.id" => current_user.try(:id),
        "gh.actor.type" => current_user.try(:class).try(:name),
      },
      e)
  end

  def existing_imports
    if (current_repository.tag_protections_availability == :enabled) && current_repository.plan_supports?(:protected_branches)

      current_repository.rulesets.where(name: [
        Repository::TagProtectionStatesDependency::SINGLE_RULESET_NAME,
        Repository::TagProtectionStatesDependency::CREATE_RULESET_NAME,
        Repository::TagProtectionStatesDependency::DELETE_RULESET_NAME,
      ]).pluck(:name).to_a
    end
  end

  # Same permission is used for editing both tag protection and branch protection
  def ensure_user_can_edit_repo_protections
    render_access_denied unless current_repository.async_can_edit_repo_protections?(current_user).sync
  end

  def ensure_protected_tags_available
    case current_repository.tag_protections_availability
    when :disabled
      render_404
    when :not_in_plan
      render plain: "Upgrade to #{current_repository.next_plan} or make this repository public to enable this feature.", status: 403
    end
  end

  def ensure_plan_supports_rules
    unless current_repository.plan_supports?(:protected_branches)
      render plain: "Upgrade to #{current_repository.next_plan} or make this repository public to enable this feature.", status: 403
    end
  end
end
