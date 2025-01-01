# typed: true
# frozen_string_literal: true

class RestApiStatusFilterExperimentJob < ApplicationJob
  use_replicas ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql1

  retry_on_dirty_exit

  queue_as :rest_api_status_filter_experiment

  include Scientist

  def perform(repository_id:, user_id:, indifferent_params:)
    return if GitHub.enterprise?

    repo = Repositories::Public.get_active_or_deleted(repository_id)

    return unless repo
    return unless user_id

    user = ActiveRecord::Base.connected_to(role: :reading) { User.find_by(id: user_id) }

    science "pull_request.rest_api_status_filter" do |experiment|
      experiment.use { pulls_control(repo, user, indifferent_params) }
      experiment.try { pulls_candidate(repo, user, indifferent_params) }
      experiment.compare_record_sequence
    end
  end

  # This method is copied from the pull_requests_sorted_by_pull_requests_table method in app/api/pulls.rb
  def pulls_control(repo, user, indifferent_params)
    pulls =
      if repo&.feature_enabled?(:only_filter_by_user_if_user_spammy)
        repo.pull_requests.filter_spam_for(user, skip_user_filter_if_not_spammy: true)
      else
        repo.pull_requests.filter_spam_for(user)
      end

    if head_label = indifferent_params[:head]
      head_ref, head_owner = head_label.split(":").reverse
      if head_owner
        head_repo = Repositories.domain.networks.find_fork_in_network_for_user(repo, head_owner)
        pulls = pulls.for_head_repo_and_head_ref(head_repo, head_ref)
      end
    end

    if base_ref = indifferent_params[:base]
      pulls = pulls.for_base_ref(base_ref).where("pull_requests.base_repository_id = pull_requests.repository_id")
    end

    pulls = pulls.filtered_and_ordered(indifferent_params)

    state = indifferent_params[:state]
    should_rewrite_join = if repo.feature_enabled?(:pull_requests_api_count_index_hint_more_often)
      state != "all"
    else
      state.present? && state != "all"
    end

    if should_rewrite_join
      # This works around a performance problem, where the MySQL query optimiser
      # will select the unique `pull_request_id` index over a non-unique index
      # that covers all of the fields in the `WHERE` clause.
      # See: https://github.com/github/killed-query-dashboard-updater/issues/913
      counter_scope = pulls.unscope(:joins).joins(Arel.sql(<<-SQL))
        INNER JOIN `issues` IGNORE INDEX (`index_issues_on_pull_request_id_unique`)
        ON `issues`.`pull_request_id` = `pull_requests`.`id`
      SQL

      pulls = counter_scope
    end

    pulls
  end

  def pulls_candidate(repo, user, indifferent_params)
    pulls = repo.pull_requests.filter_spam_for(user, skip_user_filter_if_not_spammy: true)

    if head_label = indifferent_params[:head]
      head_ref, head_owner = head_label.split(":").reverse
      if head_owner
        head_repo = repo.find_fork_in_network_for_user(head_owner)
        pulls = pulls.for_head_repo_and_head_ref(head_repo, head_ref)
      end
    end

    if base_ref = indifferent_params[:base]
      pulls = pulls.for_base_ref(base_ref).where("pull_requests.base_repository_id = pull_requests.repository_id")
    end

    pulls.filtered_and_ordered_candidate(indifferent_params)
  end
end
