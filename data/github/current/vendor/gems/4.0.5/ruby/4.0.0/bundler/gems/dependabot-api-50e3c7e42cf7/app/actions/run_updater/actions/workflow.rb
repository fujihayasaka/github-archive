# frozen_string_literal: true

module RunUpdater
  class Actions
    # rubocop:disable Metrics/ClassLength
    class Workflow
      ACTION_NWO = "github/dependabot-action"
      BASE_BRANCH_KEY = "actions:branch"
      CURRENT_VERSION_TAG = "ghes-3.20"
      LATEST_VERSION_TAG = "main"
      DEFAULT_RUNNER_LABELS = %w(dependabot).freeze

      attr_reader :update_job, :repo, :runner_settings

      def self.set_branch_for(repo:, branch_name:)
        redis.set(branch_key_for(repo), branch_name)
      end

      # We don't allow branch selection in GHES as it's a canary deployment measure, so let's not hit redis
      def self.get_branch_for(repo:)
        return CURRENT_VERSION_TAG if Dependabot.enterprise?

        redis.get(branch_key_for(repo)) || LATEST_VERSION_TAG
      end

      def self.clear_branch_for(repo:)
        redis.del(branch_key_for(repo))
      end

      private_class_method def self.redis
        @redis ||= Dependabot.redis
      end

      private_class_method def self.branch_key_for(repo)
        "#{BASE_BRANCH_KEY}:#{repo.id}"
      end

      def initialize(update_job:, runner_settings: nil)
        @update_job = update_job
        @repo = update_job.update_config.repo
        @runner_settings = runner_settings
      end

      # This is the name of this specific run of the workflow which appears
      # in Actions list views.
      #
      # It should be deterministic for any run with the same input parameters
      def run_name
        if update_job.graph?
          graph_run_name
        else
          update_run_name
        end
      end

      # This is specific to version update runs
      def update_run_name
        dependencies = update_job.dependencies&.join(", ")
        package_manager = update_job.package_manager
        directories = if update_job.directories.present?
                        update_job.directories.join(", ")
                      else
                        update_job.update_config.manifest_directories.to_a.join(", ")
                      end

        name = "#{package_manager} in #{directories}"
        name = "#{name} for #{dependencies}" if dependencies.present?
        "#{name} - Update ##{update_job.id}"
      end

      # This is specific to graph update runs
      def graph_run_name
        job_type = update_job.update_config.user_defined? ? "Configured Graph Update" : "Graph Update"

        package_manager = update_job.package_manager
        directories = if update_job.directories.present?
                        update_job.directories.join(", ")
                      else
                        update_job.update_config.manifest_directories.to_a.join(", ")
                      end
        name = "#{package_manager} in #{directories}"

        "#{job_type}: #{name} ##{update_job.id}"
      end

      # This is the name of the overall workflow which groups together all runs
      # in the sidebar of the Actions UI.
      #
      # It should be static based on the Dependabot job's command
      def workflow_name
        if update_job.graph?
          "Dependency Graph"
        else
          "Dependabot Updates"
        end
      end

      def slug
        if update_job.graph?
          "update-graph"
        else
          "dependabot-updates"
        end
      end

      def update_job_dir
        @update_job_dir ||= "./dependabot-job-#{update_job.id}-#{update_job.updated_at.to_i}"
      end

      def to_h
        use_self_hosted_workflow? ? self_hosted_workflow : cloud_workflow
      end

      def cloud_workflow # rubocop:disable Metrics/MethodLength
        env_hash = {
          DEPENDABOT_DISABLE_CLEANUP: "1",
          DEPENDABOT_ENABLE_CONNECTIVITY_CHECK: "0",
          GITHUB_TOKEN: %(${{ secrets.GITHUB_TOKEN }}),
          GITHUB_DEPENDABOT_JOB_TOKEN: %(${{ secrets.GITHUB_DEPENDABOT_JOB_TOKEN }}),
          GITHUB_DEPENDABOT_CRED_TOKEN: %(${{ secrets.GITHUB_DEPENDABOT_CRED_TOKEN }}),
        }

        env_hash[:GITHUB_REGISTRIES_PROXY] = %(${{ secrets.GITHUB_REGISTRIES_PROXY }})

        job_def = {
          "runs-on": %w(ubuntu-latest),
          "timeout-minutes": update_job.actions_job_timeout_minutes,
          steps: [
            {
              name: "Create job directory",
              run: create_update_job_directory_command,
            },
            {
              name: "Run Dependabot",
              uses: "#{ACTION_NWO}@#{update_action_branch_name}",
              env: env_hash,
            },
          ],
        }

        permissions_for_oidc(job_def)

        {
          name: run_name,
          on: "dynamic",
          jobs: {
            job_name => job_def,
          },
        }.deep_stringify_keys
      end

      def self_hosted_workflow # rubocop:disable Metrics/MethodLength
        env_hash = {
          GITHUB_TOKEN: %(${{ secrets.GITHUB_TOKEN }}),
          GITHUB_DEPENDABOT_JOB_TOKEN: %(${{ secrets.GITHUB_DEPENDABOT_JOB_TOKEN }}),
          GITHUB_DEPENDABOT_CRED_TOKEN: %(${{ secrets.GITHUB_DEPENDABOT_CRED_TOKEN }}),
        }

        env_hash[:GITHUB_REGISTRIES_PROXY] = %(${{ secrets.GITHUB_REGISTRIES_PROXY }})

        job_def = {
          "runs-on": self_hosted_runs_on,
          steps: [
            {
              name: "Verify actions runner dependencies",
              run: verify_runner_dependencies_command,
            },
            {
              name: "Create job directory",
              run: create_update_job_directory_command,
            },
            {
              name: "Run Dependabot",
              uses: "#{ACTION_NWO}@#{update_action_branch_name}",
              env: env_hash,
            },
            {
              name: "Cleanup job directory",
              run: cleanup_command,
              if: %(${{ always() }}),
            },
          ],
        }

        permissions_for_oidc(job_def)

        {
          name: run_name,
          on: "dynamic",
          jobs: {
            job_name => job_def,
          },
        }.deep_stringify_keys
      end

      def to_yaml # rubocop:disable Rails/Delegate
        to_h.to_yaml
      end

      private

      def permissions_for_oidc(job_definition)
        return if disable_oidc_auth?

        job_definition[:permissions] = {
          contents: "read",
          "id-token": "write",
          packages: "read",
        }
      end

      # This is the name of the task within a specific run, it will be
      # used as a label when viewing the summary for workflow run.
      #
      # This should be static based on the Dependabot job's command
      def job_name
        if update_job.graph?
          package_manager = update_job.package_manager
          "update-#{package_manager}-graph"
        else
          "Dependabot"
        end
      end

      def verify_runner_dependencies_command
        <<~CMD
          errors=()
          if ! [ -x "$(command -v docker)" ]; then
            errors+=('Error: docker is not installed. See https://docs.docker.com/engine/install/#server for info on how to install it.')
          fi
          if ! docker info > /dev/null 2>&1; then
            docker info > /dev/null
            errors+=('Error: Cannot connect to docker. Make sure docker is running and accessible by the actions runner.')
            errors+=("Docker socket permissions: $(ls -la /var/run/docker.sock)")
          fi

          if ! [ ${#errors[@]} -eq 0 ]; then
            echo 'Some required dependencies were not installed, please ensure the following issues are resolved and try again:' >&2
            for err in "${errors[@]}"
            do
              echo "$err" >&2
            done
            echo "Ran ${0} as user $(whoami)" >&2
            exit 1
          fi
        CMD
      end

      def create_update_job_directory_command
        %(mkdir -p  #{update_job_dir})
      end

      def cleanup_command
        %(rm -rf "#{update_job_dir}")
      end

      def update_action_branch_name
        self.class.get_branch_for(repo: repo)
      end

      def use_self_hosted_workflow?
        Dependabot.enterprise? || update_job.self_hosted?
      end

      # Configure runs-on with labels and optional runner group
      def self_hosted_runs_on
        return DEFAULT_RUNNER_LABELS unless runner_settings

        labels = runner_settings[:runner_labels].presence || DEFAULT_RUNNER_LABELS
        runner_group = runner_settings[:runner_group]

        if runner_group.present?
          { group: runner_group, labels: labels }
        else
          labels
        end
      end

      def disable_oidc_auth?
        repo.monolith_feature_enabled?(:disable_oidc_auth) ||
          repo.account.monolith_feature_enabled?(:disable_oidc_auth)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
