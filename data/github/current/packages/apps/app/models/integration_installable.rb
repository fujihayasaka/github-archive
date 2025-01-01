# typed: true
# frozen_string_literal: true

module IntegrationInstallable
  extend ActiveSupport::Concern
  include BotHydratable

  InstallationTypes = T.type_alias { T.any(IntegrationInstallation, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation) }
  InstallationClasses = T.type_alias do
    T.any(
      T.class_of(IntegrationInstallation),
      T.class_of(ScopedIntegrationInstallation),
      T.class_of(SiteScopedIntegrationInstallation)
    )
  end

  def ability_delegate_owner
    T.bind(self, T.any(InstallationTypes, GlobalIntegrationInstallation))
    integration
  end

  def clear_abilities_per_destroyed_record?
    false
  end

  # Internal: Is the installation governed by oauth application policies?
  #
  # Returns false.
  def governed_by_oauth_application_policy?
    false
  end

  def launch_github_app?
    T.bind(self, InstallationTypes)
    GitHub.launch_github_app&.id == integration_id
  end

  def launch_lab_github_app?
    T.bind(self, InstallationTypes)
    GitHub.launch_lab_github_app&.id == integration_id
  end

  # Public: Is this actor a user?
  #
  # Returns false.
  def user?
    false
  end

  # Internal: Indicates the installation actor will never be using basic auth.
  #
  # Returns false.
  def using_basic_auth?
    false
  end

  # Internal: Indicates the installation actor will never be using personal access token.
  #
  # Returns false.
  def using_personal_access_token?
    false
  end

  def abilities(subject_types: [], subject_ids: [])
    T.bind(self, InstallationTypes)
    params = {
      actor_id: ability_id,
      actor_type: ability_type,
      priority: Ability.priorities[:direct],
    }
    params[:subject_type] = subject_types if subject_types.any?
    params[:subject_id] = subject_ids if subject_ids.any?
    Permission.where(params)
  end

  def target_for_conditional_access
    T.bind(self, InstallationTypes)
    target
  end

  # Public: The tenant id for the installation.
  #
  # Returns an Integer.
  def tenant_id
    T.bind(self, InstallationTypes)
    return unless GitHub.multi_tenant_enterprise?
    # Since  the target type for a scoped integration installation
    # goes through the parent, if the parent doesn't exist, we
    # blow up. Return early if this seems to be the case.
    valid = is_a?(ScopedIntegrationInstallation) ? parent : target
    return unless valid
    target_type == "Business" ? target_id : target&.business_id
  end

  # Public: Resolves the tenant for the installation.
  #
  # Returns a Business.
  def resolve_tenant
    GitHub::CurrentTenant.unscope { Business.find_by(id: tenant_id) }
  end
end
