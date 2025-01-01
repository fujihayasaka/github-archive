# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class ActionsHostedRunnersController < Stafftools::Businesses::BusinessBaseController
      include ::Actions::RunnersHelper

      before_action :ensure_actions_enabled

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Configurations,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        only: [:show]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:show], optional: true

      def show
        # copied over largely from app/controllers/businesses/actions/runners_controller.rb, use as reference
        all_runner_groups = Actions::RunnerGroup.for_entity(this_business, include_runners: true, include_hosted_runner_groups: true, include_runner_scale_sets: true)
        hosted_runner_group = all_runner_groups.find { |group| group.hosted? }

        if hosted_runner_group.nil?
          return render_404
        end

        runners = get_runners_with_assinged_request(entity: this_business, pool_id: hosted_runner_group.id)
        jobs = get_runner_jobs(runners: runners)
        paginated_jobs = get_paginated_jobs(jobs: jobs)

        render "stafftools/businesses/actions/hosted_runners", locals: {
          jobs: jobs,
          paginated_jobs: paginated_jobs,
          hosted_runner_group: hosted_runner_group,
          concurrency_limit: runners.count
        }
      end

      def ensure_actions_enabled # rubocop:todo GitHub/UseRestfulActions
        render_404 unless GitHub.actions_enabled?
      end
    end
  end
end
