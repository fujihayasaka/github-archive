# typed: true
# frozen_string_literal: true

module User::RepositoryTemplateDependency
  extend T::Helpers

  requires_ancestor { User }

  # Public: Get a list of repo IDs for templates this user has recently cloned.
  #
  # limit - optional integer count of how many repo IDs at most to return
  #
  # Returns an Array. Will only contain repository IDs for a User, not an Organization or Bot.
  def recently_used_template_repository_ids(limit: 100)
    return [] unless user?
    RepositoryClone.for_user(self).order("repository_clones.id DESC").limit(limit).
      pluck(:template_repository_id)
  end

  # Public: Get a list of possible templates connected to this User or Organization that the
  # current user can access to generate a new repository.
  #
  # viewer - the currently authenticated User
  # scope - optional Repository ActiveRecord relation for filtering
  # cap_filter - optional ConditionalAccess::Web::Filter that will perform the filtering
  #
  # Returns an Array of Repositories.
  def repository_templates_for(viewer, scope: nil, cap_filter: nil)
    templates = generate_template_query(viewer, scope: scope, cap_filter: cap_filter)

    # Do sorting in Ruby to avoid a `CrossDomainQueryError` when sorting by user+repo in SQL
    templates.includes(:owner).sort_by do |template|
      is_mine = template.owner == viewer ? 0 : 1
      # Put viewer's own templates first, then group remaining templates by their owner
      "#{is_mine}#{template.name_with_owner.downcase}"
    end
  end

  # Gets whether a user has repository templates available.
  # It may return false positives as the found templates may not be accessible by the user.
  # Thus this is a faster though less accurate version of `generate_template_query().exists?`
  def quick_has_repository_templates?(viewer)
    relevant_owner_ids = [self.id]

    relevant_owner_ids.concat(
      viewer.feature_enabled?(:indirect_orgs_for_repo_templates) ? self.direct_and_indirect_org_ids : self.organization_ids
    ) if self.user?

    recent_template_ids = self.recently_used_template_repository_ids
    if recent_template_ids.any?
      owner_templates = Repository.templates
        .where(owner_id: relevant_owner_ids)
        .filter_spam_and_disabled_for(viewer)
        .select(:id)
        .limit(1)
      recent_templates = Repository.templates
        .where(id: recent_template_ids)
        .filter_spam_and_disabled_for(viewer)
        .select(:id)
        .limit(1)
      inner_query = [owner_templates, recent_templates].map(&:to_sql)
        .map { |q| "(#{q})" }
        .join(" UNION ")
      Repository.from("(#{inner_query}) AS repositories").exists?
    else
      Repository.templates
        .where(owner_id: relevant_owner_ids)
        .filter_spam_and_disabled_for(viewer)
        .exists?
    end
  end

  private

  def generate_template_query(viewer, scope: nil, cap_filter: nil)
    T.bind(self, T.any(User, Organization))

    GitHub.dogstats.time("RepositoryTemplateDependency.generate_template_query") do
      template_scope = Repository.templates_relevant_to(self, force_index: false).filter_spam_and_disabled_for(viewer)
      template_scope = template_scope.merge(scope) if scope

      # include internal templates if appropriate
      visibility_scope = if viewer == self || (organization? && viewer && T.cast(self, Organization).member?(viewer))
        template_scope.public_or_internal_scope(viewer)
      else
        template_scope.public_scope
      end

      # include all templates directly associated with the viewer
      template_ids = if viewer
        GitHub.dogstats.time("RepositoryTemplateDependency.associated_repository_ids") do
          viewer.associated_repository_ids(repository_ids: template_scope.pluck(:id))
        end
      else
        []
      end

      templates = if template_ids.any?
        Repository.from("(#{template_scope.where(id: template_ids).to_sql} UNION DISTINCT #{visibility_scope.to_sql}) AS repositories")
      else
        visibility_scope
      end

      if viewer && cap_filter
        unauthorized_org_ids = cap_filter.unauthorized_resource_ids(viewer.organizations)

        # public repos should always be returned regardless of CAP filter status
        templates = templates.where(public: true).or(templates.where.not(owner_id: unauthorized_org_ids)) if unauthorized_org_ids.any?
      end

      templates
    end
  end
end
