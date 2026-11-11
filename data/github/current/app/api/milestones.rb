# typed: true
# frozen_string_literal: true

class Api::Milestones < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::Mysql1ReplicaAuth
  include Api::DatabaseResourceUpdateRateLimiting
  include Api::App::DatabaseConnectionHelper

  # Gate this batch of endpoints on phase2 independently of the always-on
  # default; see Api::App::Mysql1ReplicaAuth.
  def mysql1_replica_auth_flag
    :issues_api_mysql1_replica_auth_phase2
  end

  # List Milestones
  get "/repositories/:repository_id/milestones", operation_id: "issues/list-milestones" do
    replica_clusters = T.let(
      [ApplicationRecord::IamAbilities, ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::Collab],
      T::Array[T.class_of(ApplicationRecord::Base)],
    )
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters, current_user: current_user) do
      control_access :list_milestones,
        repo: repo = find_repo!,
        allow_integrations: true,
        allow_user_via_granular_actor: true
      scope = repo.milestones.preload(:created_by)

      sort = params[:sort] || "due_date"
      direction = params[:direction] || "asc"
      scope = scope.sorted_by(sort, direction)
      # filter by state
      scope = case params[:state]
      when "all"   then scope
      when /close/ then scope.closed_milestones
      else              scope.open_milestones
      end

      milestones = paginate_rel(scope)

      deliver :milestone_hash, milestones, repo: repo
    end
  end

  # Create a Milestone
  post "/repositories/:repository_id/milestones", operation_id: "issues/create-milestone" do
    replica_clusters = T.let(
      [ApplicationRecord::Configurations, ApplicationRecord::IamAbilities, ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::Collab],
      T::Array[T.class_of(ApplicationRecord::Base)],
    )
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters, current_user: current_user) do
      control_access :create_milestone,
        repo: repo = find_repo!,
        allow_integrations: true,
        allow_user_via_granular_actor: true
      ensure_repo_writable!(repo)

      data = receive_with_schema("milestone", "create-legacy")

      milestone = repo.milestones.build attr(data,
        :title, :state, :description, :due_on)
      milestone.created_by = current_user

      if milestone.save
        deliver :milestone_hash, milestone, status: 201, repo: repo
      else
        deliver_error 422,
          errors: milestone.errors,
          documentation_url: @documentation_url
      end
    end
  end

  # Get a single Milestone
  get "/repositories/:repository_id/milestones/:milestone_number", operation_id: "issues/get-milestone" do
    replica_clusters = T.let(
      [ApplicationRecord::IamAbilities, ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::Collab],
      T::Array[T.class_of(ApplicationRecord::Base)],
    )
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters, current_user: current_user) do
      control_access :get_milestone,
        repo: repo = find_repo!,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      milestone = find_milestone(repo)

      if milestone
        deliver :milestone_hash, milestone,
          repo: repo,
          last_modified: calc_last_modified_for_object(milestone)
      else
        deliver_error 404
      end
    end
  end

  # Update a Milestone
  verbs :patch, :post, "/repositories/:repository_id/milestones/:milestone_number", operation_id: "issues/update-milestone" do
    replica_clusters = T.let(
      [ApplicationRecord::Configurations, ApplicationRecord::IamAbilities, ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::Collab],
      T::Array[T.class_of(ApplicationRecord::Base)],
    )
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters, current_user: current_user) do
      control_access :update_milestone,
        repo: repo = find_repo!,
        allow_integrations: true,
        allow_user_via_granular_actor: true
      ensure_repo_writable!(repo)

      milestone = find_milestone(repo)
      deliver_error! 404 if milestone.nil?

      check_database_resource_update_rate_limit!(resource: milestone, repo: repo, current_user: current_user)

      data = receive(Hash)

      # don't convert due_on to local time, as what we want is the pure date portion _before_ any conversion
      if milestone.update(attr(data, :title, :state, :description, :due_on, convert_to_local_times: false))
        # Introducing strict validation of the milestone.update
        # JSON schema would cause breaking changes for integrators
        # skip_validation until a rollout strategy can be determined
        # see: https://github.com/github/ecosystem-api/issues/1555
        _ = receive_with_schema("milestone", "update", skip_validation: true)

        deliver :milestone_hash, milestone, repo: repo
      else
        deliver_error 422,
          errors: milestone.errors,
          documentation_url: @documentation_url
      end
    end
  end

  # Delete a Milestone
  delete "/repositories/:repository_id/milestones/:milestone_number", operation_id: "issues/delete-milestone" do
    replica_clusters = T.let(
      [ApplicationRecord::Configurations, ApplicationRecord::IamAbilities, ApplicationRecord::Mysql1, ApplicationRecord::Repositories, ApplicationRecord::Collab],
      T::Array[T.class_of(ApplicationRecord::Base)],
    )
    replica_clusters << ApplicationRecord::Iam if FeatureFlag.vexi.enabled?(:issues_iam_replica, default: false)
    with_replica_clusters(replica_clusters, current_user: current_user) do
      # Introducing strict validation of the milestone.delete
      # JSON schema would cause breaking changes for integrators
      # skip_validation until a rollout strategy can be determined
      # see: https://github.com/github/ecosystem-api/issues/1555
      receive_with_schema("milestone", "delete", skip_validation: true)

      control_access :delete_milestone,
        repo: repo = find_repo!,
        allow_integrations: true,
        allow_user_via_granular_actor: true
      ensure_repo_writable!(repo)

      if milestone = find_milestone(repo)
        milestone.destroy
        deliver_empty(status: 204)
      else
        deliver_error 404
      end
    end
  end

  def find_milestone(repo)
    number = int_id_param!(key: :milestone_number).to_s
    return nil if number.blank?
    repo.milestones.find_by_number(number)
  end
end
