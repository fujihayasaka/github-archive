# typed: strict
# frozen_string_literal: true

module Workbench
  sig do
    params(
      user_id: Integer,
      runtime_app_id: T.nilable(Integer),
      name: String,
      attributes: T::Hash[Symbol, T.untyped],
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.create_workbench(user_id, runtime_app_id, name, attributes = {})
    uuid = SecureRandom.uuid

    workbench_params = attributes.merge({
      id: uuid,
      name: name,
      runtime_app_id: runtime_app_id,
    })
    workbench = ::Workbench.save_workbench(user_id, uuid, JSON.dump(workbench_params))
    self.serialize_workbench(workbench, nil)
  end

  sig do
    params(
      user_id: Integer,
    ).returns(T::Array[T::Hash[Symbol, T.untyped]])
  end
  def self.load_workbenches(user_id)
    workbenches = Spark::Workbench.where(user_id: user_id).to_a
    repository_ids = workbenches.map(&:repository_id).compact
    # Bulk load the repositories to avoid the N+1
    repositories_by_id = Repositories.domain.by_ids(repository_ids).index_by(&:id)

    workbenches.map do |workbench|
      repository = repositories_by_id[workbench.repository_id]
      serialize_workbench(workbench, repository)
    end
  end

  sig do
    params(
      workbench: Spark::Workbench,
      repository: T.nilable(Repositories::IRepository),
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.serialize_workbench(workbench, repository)
    {
      id: workbench.uuid_string,
      name: workbench.name,
      description: workbench.description,
      createdAt: workbench.created_at.iso8601,
      updatedAt: workbench.updated_at.iso8601,
      cloudspace_id: workbench.cloud_environment_id,
      shouldGenerateInitialPrompt: !workbench.initialized,
      currentRefinementId: workbench.current_iteration_id,
      previousRefinements: workbench.iterations.map(&:as_json),
      repositoryUrl: repository&.permalink,
      repository_id: workbench.repository_id,
      billableOwner: {
        id: workbench.billable_owner.id,
        login: workbench.billable_owner.display_login,
        type: workbench.billable_owner.type,
      },
      runtime: {
        app: {
          permanentName: workbench.runtime_app&.permanent_name,
          deploymentVisibility: {
            setting: workbench.runtime_app&.visibility,
            organizationId: workbench.runtime_app&.visibility_organization_id,
          },
          friendlyName: workbench.runtime_app&.friendly_name,
          readOnlyKv: workbench.runtime_app&.read_only_kv,
        },
        owner: {
          permanentName: workbench.runtime_app&.runtime_app_owner&.permanent_name,
          deployLogin: workbench.runtime_app&.runtime_app_owner&.deploy_login,
          deploymentDomainBase: workbench.runtime_app&.runtime_app_owner&.deployment_domain_base,
        }
      },
    }
  end

  sig do
    params(
      user_id: Integer,
      workbench_id_or_friendly_name: String,
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def self.load_workbench(user_id, workbench_id_or_friendly_name)
    workbench = Spark::Workbench.by_friendly_name_or_uuid(user_id, workbench_id_or_friendly_name)

    if workbench.nil?
      return nil
    end

    if workbench.runtime_app.nil?
      user = T.must(::User.find_by(id: user_id))
      runtime_app = ::SparkRuntimeApp.create_runtime_app(user, workbench.name)
      workbench[:runtime] = runtime_app[:app_id]
      ::Workbench::save_workbench(user.id, workbench.id, JSON.dump(workbench))
    end

    repository = Repositories.domain.by_id(workbench.repository_id) if workbench.repository_id

    serialize_workbench(workbench, repository)
  end

  sig do
    params(
      user_id: Integer,
      workbench_id: String,
      workbench_raw: String,
    ).returns(Spark::Workbench)
  end
  def self.save_workbench(user_id, workbench_id, workbench_raw)
    # Find the existing workbench (might not exist yet)
    workbench = Spark::Workbench.for_uuid_string(user_id, workbench_id)

    # Parse the JSON input and extract only the relevant (and safe to modify) fields
    values = JSON.parse(workbench_raw).with_indifferent_access
    updated_workbench = values.slice("name", "repository_id", "cloud_environment_id", "description", "runtime_app_id", "current_refinement_id")
    updated_workbench[:current_iteration_id] = values["currentRefinementId"] if values.key?("currentRefinementId")
    updated_workbench[:initialized] = !values["shouldGenerateInitialPrompt"] if values.key?("shouldGenerateInitialPrompt")
    friendly_name = values.dig("runtime", "app", "friendlyName")

    # Now that we've determined which fields are safe to update, make the original input values inaccessible
    # so that we don't accidentally use them later
    workbench_raw = nil
    values = nil

    ActiveRecord::Base.connected_to(role: :writing) do
      if workbench
        workbench.update!(updated_workbench)
        wb = workbench
      else
        wb = Spark::Workbench.create!(
          user_id: user_id,
          uuid_string: workbench_id,
          name: updated_workbench[:name],
          initialized: false,
          repository_id: updated_workbench[:repository_id],
          cloud_environment_id: updated_workbench[:cloud_environment_id],
          description: updated_workbench[:description],
          runtime_app_id: updated_workbench[:runtime_app_id],
        )
      end

      # If we've got a friendly name, it belongs on the runtime app
      wb.runtime_app&.update!(friendly_name: friendly_name) if friendly_name

      wb
    end
  end

  sig do
    params(
      user_id: Integer,
      workbench_id: String,
    ).void
  end
  def self.delete_workbench(user_id, workbench_id)
    workbench = Spark::Workbench.for_uuid_string(user_id, workbench_id)
    return unless workbench
    ActiveRecord::Base.connected_to(role: :writing) do
      workbench.destroy
    end
  end

  sig { params(user: ::User, workbench: Spark::Workbench).void }
  def self.save_favorite(user, workbench)
    Spark::FavoriteWorkbench.create_favorite(user: user, workbench_id: workbench.id)
  end

  sig { params(user: ::User, workbench: Spark::Workbench).void }
  def self.delete_favorite(user, workbench)
    Spark::FavoriteWorkbench.remove_favorite(user: user, workbench_id: workbench.id)
  end

  sig { params(user_id: Integer).returns(T::Array[String]) }
  def self.load_favorites(user_id)
    Spark::FavoriteWorkbench.joins(:workbench).where(user_id: user_id).map do |favorite|
      workbench = T.must(favorite.workbench)
      workbench.uuid_string
    end
  end
end
