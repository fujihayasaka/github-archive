# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class PagesDeploymentStatusProcessor < BaseProcessor
      default_to_write_connection!

      DEFAULT_GROUP_ID = "pages_deployment_status_processor"
      DEFAULT_SUBSCRIBE_TO = /pages_deployer\.v0\.DeploymentStatus\Z/

      # This const value need to match https://github.com/github/pages-deployer/blob/f2a2daa5d2d1c725eff63f19a2cb100b0d6cfa0f/internal/lib/reporter/deployment_status_reporter.go#L18
      DEPLOYMENT_CANCELLED = "deployment_cancelled".freeze
      DEPLOYMENT_MAX_RETRIED_TIMES = 2

      # This is the timeout used for determining if a given Kafka consumer has
      # failed or quit due to e.g. a deploy. Setting it to a lower value is NOT
      # recommended if your Hydro processor interacts with the database, since
      # Freno may wait up to 30 seconds when throttling writes. Processors that
      # do not interact with a database may lower this value to allow faster
      # consumer group rebalancing during deploys and processor failures.
      #
      # See https://kafka.apache.org/documentation/#session.timeout.ms
      options[:session_timeout] = 60.seconds

      # This value must be greater than "session_timeout"
      #
      # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
      options[:socket_timeout] = 65.seconds

      # When the processor starts consuming from a partition for the first time and has no committed offsets,
      # `start_from_beginning` determines if should start from the beginning of the log (i.e. the oldest available messages)
      # or the end of the log (i.e. the newest available messages).
      #
      # This is the equivalent of the java client `auto.offset.reset` consumer config.
      # See: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset
      options[:start_from_beginning] = false

      # Other options you may want to set...
      #
      # This will cause the Kafka consumer to wait until there is at least a
      # given number of bytes available to fetch; but the consumer will wait
      # no longer than "max_wait_time" (described below). This allows the
      # processor to wait for a large enough batch of data. The default is
      # 1 byte, meaning data will be fetched as soon as it's available. Value
      # below is for example purposes only and not a recommendation; the default
      # value of 1 should be suitable for most cases.
      # See https://kafka.apache.org/documentation/#fetch.min.bytes
      # options[:min_bytes] = 1.kilobyte
      #
      # This is the maximum amount of time the Kafka consumer will wait to
      # fetch data. The default is 500ms (0.5.seconds). Value below is for
      # example purposes only and not a recommendation; the default value of
      # 500ms should be suitable for most cases.
      options[:max_wait_time] = 0.1.seconds
      #
      # This is the maximum amount of data that will be fetched at a time. This
      # value is specified in bytes, so the number of distinct Hydro messages
      # fetched depends on the size of those messages. The default is 1MB. You
      # may want to consider lowering this if processing each batch of messages
      # is taking more than 60 seconds in order to ensure that your processor
      # shuts down in a timely manner during deploys.
      # See https://kafka.apache.org/documentation/#max.partition.fetch.bytes
      # options[:max_bytes_per_partition] = 100.kilobytes

      resolve_tenant_context do |message|
        repo = Repository.find_by_id(message.value[:repository_id])
        repo&.enterprise_managed_business
      end

      # Public: Configure the Hydro processor
      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      def feature_enabled?(feature, repository)
        return false if repository.nil?
        repository.feature_enabled?(feature) || repository.owner.feature_enabled?(feature)
      end

      def page_twirp_client
        return @client if defined?(@client)
        @client = Page::Twirp::RequestClient.new(service_name: DEFAULT_GROUP_ID)
      end

      def build_types_enabled?
        return false if repository.nil?
        if GitHub.enterprise?
          return false unless GitHub.actions_enabled?
        end
        true
      end

      def workflow_build_enabled?(repository)
        build_types_enabled? && repository.page.build_type == "workflow"
      end

      # Public: Process a single Hydro message
      #
      # message - The Hydro message to process
      #
      # Returns nothing
      def process_message(message)
        repo = Repository.find_by_id(message.value[:repository_id])
        page = repo.page

        # skip pages deployment if not find repository not with page.
        if !page
          GlobalInstrumenter.instrument("page.deployment", {
            succeed: false,
            message: message
          })
          return message.skip("repository is not associated with pages")
        end

        deployment_id = message.value[:deployment_id]
        pages_build_version = message.value[:pages_build_version]

        if deployment_id == ""
          deployment_id = pages_build_version
        end

        # skip processing if the deployment is cancelled
        cancelled = page_twirp_client.get_status(deployment_id: deployment_id, repository_id: repo.id, owner_id: repo.owner_id) == DEPLOYMENT_CANCELLED
        begin
          if cancelled
            page.fail_build
            return message.skip("deployment cancelled")
          end
          successful_hosts = message.value[:successful_hosts].map { |host| host[:name] }
          failed_hosts = message.value[:failed_hosts].map { |host| host[:name] }
          deployed = successful_hosts.any? && failed_hosts.empty?

          # update the successfully deployed host if succeed, and none failed hosts.
          if deployed
            process_successful_deployment(page, successful_hosts, pages_build_version, deployment_id, message)
            page_twirp_client.clear_status(deployment_id: deployment_id, repository_id: repo.id) if GitHub.enterprise?
          else
            process_failed_deployment(repo, page, message)
          end
        ensure
          page_twirp_client.clear_status(deployment_id: deployment_id, repository_id: repo.id) if cancelled
          GlobalInstrumenter.instrument("page.deployment", {
            succeed: deployed && !cancelled,
            message: message
          })
        end
      end

      def process_successful_deployment(page, hosts, pages_build_version, deployment_id, message)

        # use the relevant head ref/label if this was a preview deployment, or workflow build type
        ref = message.value[:preview] || page.build_type == "workflow" ? message.value[:ref] : page.source_branch

        # find previous replicas
        page_deployment = page.create_or_find_deployment_for(ref)

        recycle_replicas_hosts = ApplicationRecord::Domain::Repositories.connection.select_values(Arel.sql(<<-SQL, page_deployment_id: page_deployment.id, page_id: page.id))
          SELECT host FROM pages_replicas
          WHERE pages_deployment_id = :page_deployment_id AND
          page_id = :page_id
        SQL
        recycle_revision = page_deployment.revision
        GitHub::Pages::Builder.update_deployment_replicas(page_deployment, hosts, pages_build_version, page.build_type == "workflow" && !message.value[:preview])

        # start to recycle
        unless recycle_revision.nil?
          recycle_replicas_hosts = recycle_replicas_hosts.reject { |host| hosts.include?(host) } if pages_build_version == recycle_revision
          PageRecycleJob.set(wait: 3.minutes).perform_later(
            recycle_replicas_hosts,
            GitHub::Routing.dpages_storage_path(page.id, revision: recycle_revision),
            page.id,
            Time.now
          )
        end

        # start to clean build artifact
        PageRecycleArtifactJob.perform_later(page.id)

        # update the build status
        page.complete_build

        # update the deployment status, the deployment should always creted as pages github app.
        DeploymentStatus.create(deployment_id: message.value[:github_deployment_id], creator_id: GitHub.pages_github_app&.bot_id, state: "success", environment_url: page.url) if message.value[:github_deployment_id] > 0

        # purging CDN
        if !GitHub.enterprise? && !GitHub.multi_tenant_enterprise?
          begin
            page_twirp_client.update_status(deployment_id: deployment_id, repository_id: page.repository.id, status: "purging_cdn")
            page.purge_cdn
            GitHub.dogstats.increment("pages.cdn.purge", tags: ["state:succeed"])
          rescue Fastly::CDNPurgeError, Fastly::ValidationError => error
            page_twirp_client.update_status(deployment_id: deployment_id, repository_id: page.repository.id, status: "purge_cdn_failed")
            GitHub.dogstats.increment("pages.cdn.purge", tags: ["state:failure"])
          end
        end

        # send deployment information to audit
        if page.repository.feature_enabled?(:post_deployment_hydro_event) || page.repository.owner.feature_enabled?(:post_deployment_hydro_event)
          send_post_deployment_hydro_event(page, message)
        end
      end

      def process_failed_deployment(repo, page, message)
        deployment_id = message.value[:deployment_id]

        if deployment_id == ""
          deployment_id = message.value[:pages_build_version]
        end

        # TODO, we could add some gate here to disable retry if we are in incident.
        if message.value[:retried_times] >= DEPLOYMENT_MAX_RETRIED_TIMES
          page.fail_build
          DeploymentStatus.create(deployment_id: message.value[:github_deployment_id], creator_id: GitHub.pages_github_app&.bot_id, state: "failure") if message.value[:github_deployment_id] > 0
          page_twirp_client.update_status(deployment_id: deployment_id, repository_id: repo.id, status: "deployment_failed")

        else
          # retry the deployment
          replicator = GitHub::Pages::Replicator.new(repo, feature_enabled?(:pages_preview_deployments, repo) && message.value[:preview])
          build_id = rand(0..100)
          pages_build_version = message.value[:pages_build_version]
          hosts = replicator.hosts_with_datacenter(build_id)
          payload = {
            hosts: hosts,
            path: GitHub::Routing.dpages_storage_path(page.id, revision: pages_build_version),
            artifact_url: message.value[:artifact_url],
            environment: message.value[:environment],
            pages_build_version: pages_build_version,
            deployment_id: message.value[:deployment_id],
            global_id: message.value[:global_id],
            repo_id: message.value[:repository_id],
            writing_non_voting: replicator.write_non_voting_replicas?,
            ref: message.value[:ref],
            preview: message.value[:preview],
            preview_token: message.value[:preview_token],
            retried_times: message.value[:retried_times] + 1, # increase the retry count,
            deployment_type: message.value[:type],
            sub_dir: message.value[:sub_dir],
            nwo: message.value[:nwo],
            github_deployment_id: message.value[:github_deployment_id],
          }

          # sending to review-lab environment if the repo within paper-spa organization on dotcom
          queue_name = (repo.owner.name == "paper-spa" && !GitHub.enterprise?) ? "pages-deployer-review-lab" : "pages-deployer"
          GitHub::Pages::PagesDeployerClient.enqueue(payload, queue_name)
          page_twirp_client.update_status(deployment_id: deployment_id, repository_id: repo.id, status: "deployment_queued")
        end
      end

      # emit page build info
      def send_post_deployment_hydro_event(page, message)
        # reload information from DB
        page = page.reload
        repository = page.repository

        # do not directly use last/first here, as the statement last/first is confusing. (last returns oldest, first return latest)
        pusher = page.builds.order(updated_at: :desc).limit(1).last&.pusher
        GlobalInstrumenter.instrument "pages.actions.build", {
          actor: pusher,
          repository_owner: repository.owner,
          page: page,
          aqueduct_message: message.value[:aqueduct_message],
          artifact_hash: message.value[:artifact_hash]
        }
        true
      end
    end
  end
end
