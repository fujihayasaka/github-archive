# typed: false
# frozen_string_literal: true

module Repository::DeploymentDependency
  # Public: The most deployed to environments for the repository.
  #         Considers the last 1000 deployments to the repository.
  #
  # Returns: An array of arrays. The second element in each array is the environment. The
  #          first element is the number of deployments with that environment.
  #
  # E.g. [[31, 'production'], [17, 'canary']
  def ranked_deployment_environments
    Deployment.connection.select_rows(Arel.sql(<<-SQL, repository_id: self.id))
      SELECT COUNT(*) AS count_all, latest_environment AS deployments_environment
      FROM (
        SELECT id, latest_environment
        FROM deployments
          FORCE INDEX (index_deployments_on_repo_id_created_and_latest_environment)
        WHERE deployments.repository_id = :repository_id
        ORDER BY deployments.created_at DESC LIMIT 501
      ) AS most_recent
      GROUP BY latest_environment
      ORDER BY count_all desc
    SQL
  end

  # Public: The list of ranked deployments on active (not deleted) environments.
  #
  # Returns: An array of arrays. The second element in each array is the environment. The
  #          first element is the number of deployments with that environment. Deployments
  #          on deleted environments are filtered.  The filtering is case insensitive because
  #          we match environments case insensitively, for example, user can sepecify "prod"
  #          in their yaml file, and we will match it with an environment with name "PROD".
  def ranked_active_deployment_environments
    ranked_environments = ranked_deployment_environments
    if self.can_use_environments?
      # case insensitive filtering
      active_envs = Set.new environments.pluck(:name).map(&:downcase)
      ranked_environments.select! { |_count, env_name| active_envs.include?(env_name.downcase) }
    end
    ranked_environments
  end
end
