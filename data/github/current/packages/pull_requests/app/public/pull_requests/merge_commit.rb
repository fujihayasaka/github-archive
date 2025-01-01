# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    extend T::Sig

    # This collection defines the list of repositories that we are temporarily blocking while we test the
    # scalabiilty of the new merge commit request architecture. These repositories have been specifically identified
    # by the git-systems team as being read-heavy
    BLOCKED_REPOSITORY_IDS = T.let([
      3473720, # repository id for 10gen/mongo
      82900897, # repository id for brexhq/credit_card
      6223686, # repository id for Canva/canva
      129701233, # repository id for cloudqwest/environment-configuration
      6049098, # repository id for chromium/chromium
      15539164, # repository id for databricks/universe
      17754802, # repository id for EpicGames/UnrealEngine
      100127661, # repository id for hassio-addons/repository
      85435841, # repository id for home-assistant/addons
      3623050, # repository id for Homebrew/homebrew-cask
      52855516, # repository id for Homebrew/homebrew-core
      20580498, # repository id for kubernetes/kubernetes
      549651800, # repository id for larsxplayground/read-heavy-testing
      606295773, # repository id for liaoth3/coin_new
      20456933, # repository id for mhagger/glorious-junk
      72685026, # repository id for MicrosoftDocs/azure-docs
      31605542, # repository id for Optibus/armada
      561509963, # repository id for pinternal/pinboard
      251663834, # repository id for robinhoodmarkets/rh
      26193547, # repository id for rust-lang/crates.io-index
      233415103, # repository id for snowflakedb/snowflake
      118643380, # repository id for terrorobe/emojibomb2
      1811994, # repository id for terrorobe/pglogparser
      1812003, # repository id for terrorobe/pgworkshop
      619859161, # repository id for twitter/the-algorithm
      619885280, # repository id for twitter/the-algorithm-ml
      542130009, # repository id for uber-code/android-code
      542158940, # repository id for uber-code/go-code
      552863092, # repository id for uber-code/go-code-staging-area
      524426523, # repository id for uber-code/infra-config
      533261869, # repository id for uber-code/ios-code
      542166896, # repository id for uber-code/java-code
      542122000, # repository id for uber-code/web-code
      316713600, # repository id for Visma-Welfare-School/flyt-platform
    ], T::Array[Integer])

    sig { params(pull_request: PullRequest, new_engine_override: T::Boolean, priority: Symbol).void }
    def self.enqueue_create(pull_request:, new_engine_override: false, priority: :low)
      GitHub.dogstats.increment("merge_commit.enqueued", tags: [
        "from:#{GitHub.context[:from].presence || GitHub.context[:job].presence || "unknown"}",
        "catalog_service:#{GitHub.context[:catalog_service]}"
      ])

      # it may make sense to pull the returns below from #enqueue_mergable_update into a separate method,
      # but I'm leaving it here for now to leave a clean abstraction.
      # As we do so I think we'd pull tests from packages/pull_requests/test/models/pull_request_test.rb:3038
      # into packages/pull_requests/test/public/pull_requests/merge_commit_test.rb.
      return unless pull_request.open?

      # currently_mergeable? is not a true predicate method and in this
      # particular scenario we are specifically interested in the nil state.
      # Therefore we need to do this somewhat awkward looking nil check
      # on a predicate method's return value.
      return unless pull_request.currently_mergeable?.nil?

      return unless repository = pull_request.repository
      return unless repository_id = repository.id
      return unless pull_request_id = pull_request.id

      using_new_engine = (new_engine_override ||
        # Don't run this code path in tests as it's going to break all mergeability checks
        # TODO: remove the Rails environment check and address all tests that currently depend on CPRMC running to
        # check mergeability or create a merge commit
        (!Rails.env.test? && # rubocop:disable GitHub/DoNotBranchOnRailsEnv
          repository.feature_enabled?(:use_merge_commit_request_architecture)
        )) &&
        # The check on BLOCKED_REPOSITORY_IDS is temporary while we test the scalability of the new merge commit
        # request architecture. We are purposefully excluding these repositories so that their volume of possible
        # merge commit requests doesn't overwhelm our ability to handle them before we're ready to do so.
        !BLOCKED_REPOSITORY_IDS.include?(repository_id)


      if using_new_engine
        # Priority argument is used to bypass instrumentation of the merge_commit.requested event and the inherent
        # latency/time taken in processing that event. Presently used only in codepaths for direct end user web
        # interactions (e.g. merge box). Guarded by the `skip_processor_batchable_mcr_jobs` feature flag while
        # this is tested in a larger production rollout
        if repository.feature_enabled?(:skip_processor_batchable_mcr_jobs) && priority == :high
          request!(repository_id:, pull_request_id:)
        else
          GlobalInstrumenter.instrument("merge_commit.requested", repository_id:, pull_request_id:)
        end
      else
        CreatePullRequestMergeCommitJob.perform_later(pull_request_id)
      end
    end

    sig { params(repository_id: Integer, pull_request_id: Integer).void }
    def self.request!(repository_id:, pull_request_id:)
      create_merge_commit_request(repository_id:, pull_request_id:)
      enqueue_merge_commit_request_batch_job(repository_id:)
    end

    # Request a bulk insert of MergeCommitRequests.
    #   requests are a collection of tuples [repository_id, pull_request_id, timestamp]
    sig { params(requests: T::Array[[Integer, Integer, Time]], block: T.nilable(T.proc.void)).void }
    def self.batch_request_with_block(requests, &block)
      repository_ids = T.let(Set.new, T::Set[Integer])

      GitHub.dogstats.count("pull_requests.merge_commits.stream_processor.requests", requests.size)

      # TODO: Do we need controls for the batch size?
      requests.in_groups_of(50, false) do |request_batch|
        yield if block_given?

        timestamps = T.let([], T::Array[Time])

        request_batch.each do |(repository_id, _, timestamp)|
          repository_ids << repository_id
          timestamps << timestamp
        end

        # The insert_all API does not let you control the "ON DUPLICATE KEY UPDATE" value. This is a hand
        # rolled version of the same SQL statements, but with a different clause.
        sql = <<~SQL
          INSERT INTO `merge_commit_requests` (`pull_request_id`,`repository_id`,`created_at`,`updated_at`)
          VALUES #{request_batch.map do |(repository_id, pull_request_id, _)|
            "(#{pull_request_id}, #{repository_id}, CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6))"
          end.join(", ")} ON DUPLICATE KEY UPDATE `updated_at`=`updated_at`
        SQL

        result = T.let(MergeCommitRequest.connection.execute(sql), Trilogy::Result) # rubocop:disable GitHub/DoNotReferenceTrilogy

        GitHub.dogstats.count("pull_requests.merge_commit_requests.created", result.affected_rows, tags: ["source:batch"])

        now = Time.now
        timestamps.each do |timestamp|
          GitHub.dogstats.distribution(
            "pull_requests.merge_commits.stream_processor.time_to_enqueue",
            ((now - timestamp).to_f * 1000),
            tags: ["batched:true"]
          )
        end
      end

      repository_ids.each do |repository_id|
        enqueue_merge_commit_request_batch_job(repository_id:)
      end
    end

    # private

    sig { params(repository_id: Integer, pull_request_id: Integer).void }
    def self.create_merge_commit_request(repository_id:, pull_request_id:)
      begin
        MergeCommitRequest.create!(repository_id:, pull_request_id:)
        GitHub.dogstats.count("pull_requests.merge_commit_requests.created", 1, tags: ["source:single"])
      rescue => error # rubocop:disable Lint/GenericRescue
        error_type = T.must(error.class.name).demodulize.underscore
        GitHub.dogstats.increment("pull_requests.merge_commit_requests.error", tags: ["error:#{error_type}"])

        unless error.kind_of?(ActiveRecord::RecordNotUnique)
          GitHub.logger.error(
            "merge commit request record could not be created",
            "error.type": error_type,
            "error.message": error.message,
            "gh.repo.id": repository_id,
            "gh.pull.id": pull_request_id
          )

          Failbot.report(error)
        end
      end
    end

    private_class_method :create_merge_commit_request

    sig { params(repository_id: Integer).void }
    def self.enqueue_merge_commit_request_batch_job(repository_id:)
      PullRequests::MergeCommitRequestBatchJob.perform_later(repository_id)
    end

    private_class_method :enqueue_merge_commit_request_batch_job
  end
end
