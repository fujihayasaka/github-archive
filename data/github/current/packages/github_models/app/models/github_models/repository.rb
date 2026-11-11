# typed: true
# frozen_string_literal: true

class GitHubModels::Repository
  include GitHub::Memoizer

  sig { params(repository: ::Repository).void }
  def initialize(repository:)
    @repository = repository
  end

  # Public: Is models access available for this repository? (the user can turn it on in repo settings)
  sig { returns T::Boolean }
  memoize def models_available_for_repo?
    return false unless GitHub.models_enabled?

    org = self.org
    if org
      # For org-owned repositories, we need to check if the org has models enabled
      GitHubModels::OrganizationAccessPolicy.new(org: org).models_available_for_org?
    else
      # For user-owned repositories, we always want user to see Settings page
      true
    end
  end

  # TODO: This needs to be changed to hide the models tab if the organization has disabled models.
  # Public: Is models access enabled for this repository?
  sig { returns T::Boolean }
  memoize def models_enabled_for_repo?
    return false unless GitHub.models_enabled?

    org = self.org
    if org
      return false unless GitHubModels::OrganizationAccessPolicy.new(org: org).models_enabled_for_org?
    end

    GitHubModels::RepositoryAccessPolicy.new(repo: @repository).models_enabled_for_repo?
  end

  sig do
    params(user: T.any(::User, GitHubModels::User), all_models: T::Boolean)
      .returns(T::Array[DefaultAndCustomModels::IModel])
  end
  def models(user:, all_models: false)
    @models_by_user_id ||= {}
    return @models_by_user_id[user.id] if @models_by_user_id.key?(user.id)

    models_user = user.is_a?(GitHubModels::User) ? user : GitHubModels::User.new(user: user)
    github_user = models_user.user

    org = self.org
    unless org && org.member?(github_user)
      @models_by_user_id[user.id] = models_user.models(sort: :publisher)
      return @models_by_user_id[user.id]
    end

    org_policy = GitHubModels::OrganizationAccessPolicy.new(org: org)
    @models_by_user_id[user.id] = all_models ? org_policy.all_models : org_policy.allowed_models
  end

  sig do
    params(user: T.any(::User, GitHubModels::User), name: String, key: T.nilable(String))
      .returns(T.nilable(ModelsByok::CustomModel))
  end
  def custom_model(user:, name:, key: nil)
    result = model(user: user, registry: ModelsByok::CustomModel::REGISTRY, name: name, key: key)
    result.is_a?(ModelsByok::CustomModel) ? result : nil
  end

  sig { params(user: T.any(::User, GitHubModels::User), registry: String, name: String, key: T.nilable(String)).returns(T.nilable(DefaultAndCustomModels::IModel)) }
  def model(user:, registry:, name:, key: nil)
    models_list = models(user:)

    models_list.find do |model|
      if registry == ModelsByok::CustomModel::REGISTRY
        model.is_a?(ModelsByok::CustomModel) && model.custom_key_name == key && model.slug == name
      else
        model.is_a?(GitHubModels::IModel) && model.registry == registry && model.name == name
      end
    end
  end

  sig { returns T.nilable(Organization) }
  memoize def org
    repo_owner = @repository.owner
    repo_owner.is_a?(Organization) ? repo_owner : nil
  end
end
