# typed: true
# frozen_string_literal: true

# Template and cloning-specific functionality for repositories
module Repository::TemplateDependency
  include GitHub::Memoizer
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))

    scope :templates, -> { active.where(template: true) }

    scope :templates_relevant_to, ->(user, force_index: true) do
      relevant_owner_ids = [user.id]
      relevant_owner_ids.concat(
        user.feature_enabled?(:indirect_orgs_for_repo_templates) ? user.direct_and_indirect_org_ids : user.organization_ids
      ) if user.user?

      recent_template_ids = user.recently_used_template_repository_ids

      if recent_template_ids.any?
        user_templates = templates.where("repositories.owner_id IN (?) OR repositories.id IN (?)", relevant_owner_ids, recent_template_ids)
      else
        user_templates = templates.where(owner_id: relevant_owner_ids)
      end

      if force_index
        user_templates = user_templates.from("repositories FORCE INDEX(index_repositories_on_template_and_active_and_owner_id)")
      end
      user_templates
    end

    validate :lfs_cannot_template, on: :update
  end

  def lfs_cannot_template
    return unless template? && template_changed?

    errors.add(:template, "LFS content is not supported on template repositories") if has_lfs_files?
  end

  # Public: The repository from which this repository was cloned, if any.
  #
  # Returns a Repository or nil.
  def template_repository
    @template_repository ||= async_template_repository.sync
  end

  def async_template_repository
    async_template_repository_clone.then do |tmpl_repo_clone|
      if tmpl_repo_clone
        tmpl_repo_clone.async_template_repository.then do |tmpl_repo|
          tmpl_repo if tmpl_repo&.disabled_at.nil?
        end
      end
    end
  end

  # Public: Whether this repository is not yet finished being cloned from a template repository.
  #
  # Returns a Boolean.
  def cloning_from_template?
    template_repository_clone&.cloning? || clone_errored?
  end

  # Public: Whether this repository could not finish being cloned from a template repository because
  # an error occurred.
  #
  # Returns a Boolean.
  def clone_errored?
    template_repository_clone&.error?
  end

  # Public: The reason this repository could not be cloned from a template, if it was generated from
  # a template and failed in the process.
  #
  # Returns a RepositoryClone.error_reason_codes (or nil).
  def clone_error_reason_code
    template_repository_clone&.error_reason_code
  end

  memoize def clone_error_rule_suite
    return nil unless clone_error_reason_code == "rule_violations"
    return nil unless (suite_id = repo_clone_rule_suite_id)

    RuleEngine::RuleSuite.find_by(id: suite_id)
  end

  # Public: The owner of the template repository this repository was cloned from
  #
  # Returns a User, Organization, or nil.
  def clone_owner
    template_repository_clone&.template_owner
  end

  # Public: Whether this repo was cloned from a template repository and is finished being cloned.
  #
  # Returns a Boolean.
  def finished_cloning_from_template?
    template_repository_clone&.finished?
  end

  def clone_template_to(owner, actor:, name:, copy_branches:, description:, visibility:, reflog_data:, current_integration_context:, allow_integrations: false)
    is_mine = owner.id == actor.id
    bot_creating_for_user = allow_integrations && actor.bot? && actor.ability_delegate&.target == owner
    can_write_to_org = owner.organization? &&
      owner.can_create_repository?(actor, visibility: visibility)

    if !is_mine && !can_write_to_org && !bot_creating_for_user
      return [nil, :forbidden, "#{actor.display_login} cannot create a repository for #{owner.display_login}."]
    end

    if !GitHub.public_repositories_available? && visibility == ::Repository::PUBLIC_VISIBILITY
      return [nil, :forbidden, "Public repositories are not permitted on #{GitHub.flavor_brand_name}"]
    end

    if owner.renaming?
      return [nil, :forbidden, "#{owner.display_login} is currently renaming and cannot create new repositories."]
    end

    orchestration = RepositoryOrchestration.clone_template(
      template_repository: T.cast(self, Repository), # rubocop:todo GitHub/AvoidCast
      owner:,
      actor:,
      name:,
      copy_branches:,
      description:,
      visibility:,
      reflog_data:,
      current_integration_context:
    )

    unless orchestration.valid?
      return [nil, :unprocessable_entity, "Could not clone: #{orchestration.errors.full_messages.join(", ")}"]
    end

    orchestration.execute

    return [nil, :unprocessable_entity, "Could not clone: #{orchestration.error_message}"] if orchestration.failed?

    [orchestration.repository, nil, nil]
  end
end
