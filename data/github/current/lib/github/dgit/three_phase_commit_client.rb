# typed: true
# frozen_string_literal: true

require "github/dgit/constants"
require "time"
require "github/dgit/replica_3pc_client"
require "github/spokes"

module GitHub
  class DGit
    # Manage 3PC reference updates with multiple replicas at the same
    # time, ensuring that there is a consensus among replicas about
    # the new state of the repository before committing.
    #
    # This class uses one Replica3PCClient instance per replica to
    # conduct the low-level 3PC negotiation.
    class ThreePhaseCommitClient
      class PhaseQuorumError < GitHub::DGit::Error; end
      class PhaseQuorumUnattainableError < PhaseQuorumError; end
      class FirstReplicaTooBusyError < PhaseQuorumError; end

      # Log information to help compare old and new implementations of 3pc.
      def log_3pc_compare(at, start_time, threepc_client, status, result)
        if start_time
          finish = Time.now
          start_time = T.let(start_time, Time)
          GitHub.stats.timing "dgit.3pc.timing", (finish - start_time) * 1000 if GitHub.enterprise?
          GitHub.dogstats.timing "dgit.3pc.timing", (finish - start_time) * 1000,
                                  tags: ["priority:#{@priority}",
                                        "threepc_client:#{threepc_client}",
                                        "result:#{result}",
                                        "client_err:#{status[:err].nil? ? :ok : :failure}"]
          log_blob = { "gh.dgit.3pc.method" => "commit",
            "gh.dgit.3pc.priority" => @priority,
            "gh.repo.name_with_owner" => @repo_name,
            "gh.timing.elapsed_seconds" => finish - start_time,
            "gh.dgit.3pc.before_checksum" => @threepc_before_checksum,
            "gh.dgit.3pc.at" => at,
            "gh.dgit.3pc.result" => result,
            "gh.dgit.3pc.client_err" => status[:err],
            "gh.spokes.threepc_client" => threepc_client }

          log_blob["gh.request_id"] = @request_id unless @request_id.nil?

          GitHub.logger.info("3PC client stats", log_blob)
        end
      end

      # initialize - create a ThreePhaseCommitClient object bound to a
      # particular repo. Instances of this class can be created via
      # GitHub::DGit.update_refs_coordinator.
      #  - repo_name - the repo's full name, like "owner/name" or "owner/name.wiki".
      #                This is used for error reporting. This is added to sockstat if
      #                sockstat does not include repo_name.
      #  - delegate - a GitHub::DGit::Delegate instance
      #
      # Returns: nothing.  It's a constructor.
      def initialize(repo_name, delegate, coalesce: false, priority: :high, request_id: nil)
        @repo_name = repo_name
        @delegate = delegate
        @replica_client_class = Replica3PCClient
        @priority = priority
        @request_id = request_id
        @default_sockstat = {}
        @default_sockstat[:repo_name] = repo_name if repo_name
        @default_sockstat[:request_id] = request_id if request_id
        @connections = []
      end

      # commit - atomically change, create, or delete zero or more
      # refs (branches) in the repo or wiki bound by the constructor.
      #  - refs_before_after_status - an array of
      #    `[ refname, before, after, status ]` tuples.
      #    - `refname` is the name of the reference to be changed,
      #      created, or deleted
      #    - `before` is a string containing a 40-byte SHA1 value of
      #      the commit that the branch must atomically match, or the
      #      update will be aborted. `before` can be GitHub::NULL_OID to
      #      check that the reference doesn't already exist. `before` can
      #      be `nil` to skip the check.
      #    - `after` is a string containing a 40-byte SHA1 value of
      #      the commit that the branch will point to after a
      #      successful update. `after` can be `GitHub::NULL_OID` (all
      #      zeros) to delete the reference. If `after` is `nil`, then
      #      the `before` value (if any) is checked but the reference
      #      is not changed.
      #    - `status` can be the string "ff" or "nf" to denote that a
      #      non-create, non-delete update is a fast-forward or
      #      non-fast-forward.  `status` can be `nil` to skip recording
      #      the fast-forward-ness in the audit_log.
      #  - sockstat - a hash of key-value pairs that will be recorded
      #    in system logs and the `audit_log` file
      #
      # Returns: a hash with four keys:
      #  - :checksum => the replica checksum (a version + SHA1) agreed
      #    upon by more than half the replicas. This is distinct from
      #    the SHA1 the refs are checked against and changed to.
      #  - :refs_status => if the update fails, a hash mapping a
      #    refname to a human-readable description of the reason that
      #    it could not be updated (for example, `lock exists` or
      #    `failed`). Note that only the first failure that was
      #    noticed is reported.
      #  - :err => a human-readable description of the reason 3PC
      #    failed, if any. `nil` means everything succeeded.
      #  - :committed_at => the time the commit was written.
      #
      # commit can also raise several different exceptions that
      # subclass `GitHub::DGit::Error`.
      def commit(refs_before_after_status, sockstat = {}, reflog_msg = "")
        start_time = Time.now
        @mode = :commit
        all_routes = get_all_routes
        @quorum = determine_quorum(all_routes)
        routes = @delegate.get_3pc_routes

        begin
          status = do_3pc(routes, refs_before_after_status, sockstat, reflog_msg, nil, nil, nil, nil)
        rescue GitHub::DGit::Error => e
          at = "commit_error"
          result = e
          status = {}
          log_3pc_compare(at, start_time, "Monolith", status, result)
          raise
        else
          at = "commit_finish"
          result = "ok"
          log_3pc_compare(at, start_time, "Monolith", status, result)
        end

        status
      end

      # This works exactly like commit, but uses all routes.  It should not be
      # used except by the testsuite.
      def commit_all_routes(refs_before_after_status, sockstat = {}, reflog_msg = "")
        @mode = :commit
        routes = get_all_routes
        @quorum = determine_quorum(routes)
        do_3pc(routes, refs_before_after_status, sockstat, reflog_msg, nil, nil, nil, nil)
      end

      # with_dgit_lock - run the given block with the DGit lock held
      # on all replicas. The call only succeeds if a majority of all
      # voting replicas (not just healthy ones) can obtain the lock.
      # Note that this is different from a normal 3PC write, which
      # contacts only healthy replicas.
      #
      #   - block           - the block to call once the lock is held
      #
      # Returns
      #   - a hash of host=>checksum, for all hosts that have the repo
      def with_dgit_lock(block)
        start_time = Time.now
        @mode = :with_dgit_lock
        fail unless block
        routes = get_all_routes
        @quorum = determine_quorum(routes, voting_strategy: :vote)
        begin
          status = do_3pc(routes, [], {}, "", block, nil, :vote, nil)
        rescue GitHub::DGit::Error => e
          at = "with_dgit_lock_error"
          result = e
          status = {}
          log_3pc_compare(at, start_time, "Monolith", status, result)
          raise
        else
          at = "with_dgit_lock_finish"
          result = "ok"
          log_3pc_compare(at, start_time, "Monolith", status, result)
        end

        status
      end

      # Recompute the checksums for the repository's replicas.
      #
      #   - voting_strategy - One of :vote, :vote_fallback, :checksum_host.
      #                       Must not be nil.
      #                       - vote: take a vote, and bail out immediately if
      #                         the majority is smaller than the quorum.
      #                       - vote_fallback: take a vote, but use the checksum
      #                         of checksum_host as fallback if there is no quorum.
      #                       - checksum_host: always use the checksum of
      #                         checksum_host as the repo checksum.
      #   - checksum_host   - the host whose checksum will become definitive
      #                       after the operation completes.  Used if either
      #                       :checksum_host or :vote_fallback are used as
      #                       voting strategies.
      #   - ignore_dissent  - don't report dissenters from a quorum.
      #
      # Returns
      #   - a hash of host=>checksum, for all hosts that have the repo
      def recompute_checksums(voting_strategy, checksum_host, ignore_dissent: false)
        start_time = Time.now
        @mode = :recompute_checksums
        @ignore_dissent = ignore_dissent
        fail unless voting_strategy
        routes = get_all_routes
        @quorum = determine_quorum(routes, voting_strategy: voting_strategy)
        begin
          status = do_3pc(routes, [], {}, "", nil, nil, voting_strategy, checksum_host)
        rescue GitHub::DGit::Error => e
          at = "recompute_checksums_error"
          result = e
          status = {}
          log_3pc_compare(at, start_time, "Monolith", status, result)
          raise
        else
          at = "recompute_checksums_finish"
          result = "ok"
          log_3pc_compare(at, start_time, "Monolith", status, result)
        end

        status
      end

      # Return the quorum needed to get a majority of voting routes:
      def determine_quorum(routes, voting_strategy: nil)
        case voting_strategy
        when nil, :vote
          GitHub.dgit_quorum(routes.count(&:voting?))
        else
          1
        end
      end

      # Return a list of all of the read routes, sorted
      # deterministically as per Route#<=> to avoid dining philsophers
      # deadlocks.
      #
      # We exclude cache replicas because we never want them to participate
      # in 3PC; they get updated asynchronously.
      def get_all_routes
        @delegate.get_all_routes(live_only: false).reject(&:cache_server?).sort
      end

      # Execute the three phase commit.
      #
      #   - routes - the routes which should be used for the 3pc.
      #   - refs_before_after_states - an array of
      #       [ refname, before, after, status ] tuples.
      #       See also `commit`
      #   - sockstat - sockstat variables that are being passed along
      #       to dgit_update.
      #   - reflog_msg - the message that should end up in the reflog.
      #   - under_lock_block - a block of code that should be executed
      #       under lock, just before the commit commands are sent.
      #   - precompute_checksum_block - a block of code that should be
      #       executed after connecting to the replica, but before
      #       getting the lock.
      #   - voting_strategy - One of nil, :vote, :vote_fallback, :checksum_host
      #      - nil: take a vote, and write the majority checksum to the db before bailing out.
      #      - vote: take a vote, and bail out immediately if the majority is smaller than the quorum.
      #      - vote_fallback: take a vote, but use the checksum of checksum_host as fallback if there is no quorum.
      #      - checksum_host: always use the checksum of checksum_host as the repo checksum.
      # Returns
      #   - a hash with the repo checksum, the refs status, eventual errors
      #       and the commit time.
      def do_3pc(routes, refs_before_after_status, sockstat, reflog_msg, under_lock_block,
                 precompute_checksum_block, voting_strategy, checksum_host)

        # Usage of legacy 3PC for this call is limited only to tests. All production
        # calls should use the Spokes Access API endpoints
        # This is a temporary measure to handle the fact that we cannot run all CI tests
        # using the spokes version of 3pc, but we want to make sure that we only use the
        # spokesd implementation in production.
        raise "Legacy 3PC code is only available in tests" unless Rails.env.test? && !GitHub.spokesd_enabled? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

        sockstat ||= {}
        sockstat = @default_sockstat.merge(sockstat)
        reflog_msg ||= ""
        @threepc_before_checksum = nil
        @start = Time.now

        begin
          git_commit_time = Time.current
          checksum_from_scratch = !!voting_strategy
          create_connections(routes, refs_before_after_status, git_commit_time.to_formatted_s(:git), sockstat, reflog_msg,
                             checksum_from_scratch: checksum_from_scratch)

          initiate_connections
          precompute_checksums if checksum_from_scratch
          precompute_checksum_block.call if precompute_checksum_block
          @lock_start = Time.now
          acquire_lock_quorum
          @lock_acquired = Time.now

          # Now we hold the distributed lock. Fetch the DB checksum
          # under that lock while waiting for the other replicas to
          # acquire their locks. (This returns nil during gist
          # creation.)
          @threepc_before_checksum = @delegate.read_checksum_from_db

          # Now wait for the rest of the replicas to acquire their
          # locks (or fail).
          prepare_for_ok

          if @threepc_before_checksum
            maybe_autorepair_checksum
          else
            initialize_checksum(checksum_host)
          end

          # If we're recalculating checksums, lie and tell each replica that
          # the desired checksum is the one it just sent.  A `nil` argument
          # here does that.
          send_ok_queries(voting_strategy ? nil : @threepc_before_checksum)

          begin
            prepare_for_pre_commit

            under_lock_block.call if under_lock_block

            send_pre_commit_commands(checksum_host ? nil : @threepc_before_checksum)

            wait_for_ack
            send_commit_commands
          rescue PhaseQuorumError
            # Nothing to do; the steps below will fall through.
          end

          prepare_for_done

          log_3pc_state "finish", result: :ok

          # The new per-replica checksums that we will write to the
          # database, as a {host => checksum} hash:
          replica_checksums = {}

          # Voting replicas' votes for checksums, in the form
          # {checksum => count}:
          csum_counts = Hash.new(0)

          @connections.each do |cn|
            case cn.checksum
            when :indeterminate
              # The transaction failed at a point that leaves us
              # unsure about the on-disk checksum. Record that as
              # "bad" in the database, and don't count it as a vote:
              replica_checksums[cn.host] = "bad"
            when :unchanged
              # The transaction failed before we ever learned this
              # replica's on-disk checksum; all we know is that it
              # wasn't changed by the transaction. So don't overwrite
              # whatever checksum value is stored in the database for
              # this replica.

              # FIXME: it seems very questionable to count such a
              # replica as a vote for `@threepc_before_checksum`.
              cn.checksum = @threepc_before_checksum
              if cn.eligible_to_vote? && cn.voting?
                csum_counts[cn.checksum] += 1
                GitHub.logger.info("unchanged replica", "gh.spokes.fileserver" => cn.host)
              end

              replica_checksums[cn.host] = cn.was_healthy? ? @threepc_before_checksum : "bad"
            when String
              replica_checksums[cn.host] = cn.checksum
              if cn.eligible_to_vote? && cn.voting?
                csum_counts[cn.checksum] += 1
              end
            else
              fail "unexpected replica checksum type"
            end
          end

          case voting_strategy
          when nil
            repo_checksum, _ = csum_counts.max_by { |_k, v| v }
          when :vote
            repo_checksum, _ = csum_counts.max_by { |_k, v| v }
            if csum_counts[repo_checksum] < @quorum
              raise GitHub::DGit::ThreepcError,
                    "couldn't determine majority checksum: " \
                    "before=#{@threepc_before_checksum.inspect}"
            end
          when :vote_fallback
            repo_checksum, _ = csum_counts.max_by { |_k, v| v }
            if csum_counts[repo_checksum] < determine_quorum(routes, voting_strategy: :vote)
              cn = @connections.find { |cn| cn.host == checksum_host }
              if !cn || cn.err
                raise GitHub::DGit::ThreepcError,
                      "no checksum for requested host #{checksum_host.inspect}"
              end
              repo_checksum = cn.checksum
            end
          else
            # Let the checksum on the designated host override the
            # majority, if `checksum_host` is a specific host.
            cn = @connections.find { |cn| cn.host == checksum_host }
            if !cn || cn.err
              raise GitHub::DGit::ThreepcError,
                    "no checksum for requested host #{checksum_host.inspect}"
            end
            repo_checksum = cn.checksum
          end

          # Write the checksums to the database while we are still
          # holding the distributed lock. (This is a NOOP during gist
          # creation.)
          @delegate.write_checksums_to_db(replica_checksums.transform_values do |checksum|
            checksum == repo_checksum ? "ok" : "bad"
          end, repo_checksum)

          if csum_counts[repo_checksum] < @quorum
            GitHub.logger.info("no quorum", "count" => csum_counts[repo_checksum])
            message =
              "couldn't determine majority checksum for update: " \
              "before=#{@threepc_before_checksum.inspect}"
            if GitRPC.test_tracer
              message +=
                "\nquorum=#{@quorum} csum_counts=#{csum_counts.inspect}\n" +
                GitRPC.test_tracer.log_of_3pc
            end
            raise GitHub::DGit::ThreepcError, message
          end

          refs_status_counts = Hash.new(0)
          @connections.each do |cn|
            if cn.checksum == repo_checksum
              refs_status_counts[cn.refs_status] += 1 if cn.voting?
            end
          end

          # The number of voting replicas that agree with the
          # majority:
          ok_voter_count = 0

          err = T.let(nil, T.nilable(String))

          # The connections whose final checksums didn't match the
          # majority:
          dissented = []

          # The connections that failed (aren't eligible to vote):
          failed = []

          majority_refs_status = refs_status_counts.max_by { |_k, v| v }.first
          @connections.each do |cn|
            if !cn.eligible_to_vote?
              failed << cn
            elsif cn.checksum != repo_checksum
              cn.err ||= "final checksum didn't match majority"
              dissented << cn
            elsif cn.refs_status != majority_refs_status
              cn.err ||= "ref status didn't match majority"
              dissented << cn
            else
              ok_voter_count += 1 if cn.voting?
              err ||= cn.err
            end
          end

          if ok_voter_count >= @quorum
            report_dissent(ok_voter_count, repo_checksum, dissented, failed)

            # Return a hash of host=>checksum, if recalculating checksums.
            unless @mode == :commit
              ret = Hash[@connections
                .select { |cn| cn.in_phase?(Replica3PCReadyForDonePhase) || cn.in_phase?(Replica3PCFinishedPhase) }
                .map { |cn| [cn.host, cn.checksum] }
              ]
              ret[:repo] = repo_checksum
              return ret
            end

            {
              checksum: repo_checksum,
              refs_status: majority_refs_status,
              err: err,
              committed_at: git_commit_time,
            }
          else
            # XXX need a real exception class here? failbot context?
            GitHub::DGit::threepc_debug "ref commit failed: #{@connections.inspect}"
            raise GitHub::DGit::ThreepcError,
                  "ref commit failed: before=#{@threepc_before_checksum.inspect}"
          end
        ensure
          destroy_connections
        end
      end

      def create_connections(routes, refs_before_after_status,
                             git_commit_time, sockstat, reflog_msg,
                             checksum_from_scratch:)

        # A client should never be re-used. Just to ensure this, verify we don't
        # already have connections.
        fail unless @connections.empty?

        routes.each_with_index do |route, index|
          @connections << @replica_client_class.new(
            index, refs_before_after_status, git_commit_time,
            sockstat, reflog_msg, route, @priority,
            checksum_from_scratch: checksum_from_scratch,
          )
        end
        # Do the DNS resolution now, before we have started creating
        # connections to any of the replicas. This avoids timeouts of
        # `dgit-update` for earlier replicas if DNS resolution of
        # later replicas is slow.
        @connections.each do |cn|
          with_replica_error_handler(cn) do
            cn.resolve_host
          end
        end
      end

      # Initate connections to each of the replicas, and wait until a
      # quorum are connected. On failure, raise `ThreepcFailedToLock`.
      def initiate_connections
        connections_in_phase(Replica3PCUninitializedPhase).each do |cn|
          with_replica_error_handler(cn) do
            cn.start_connection
          end
        end
        wait_for_phase(Replica3PCConnectedPhase)
      rescue PhaseQuorumError
        log_3pc_state "failure", result: :failed_to_lock
        abort_all_transactions "aborted due to too few connections to replicas"
        raise GitHub::DGit::ThreepcFailedToLock, "failed to lock checksum"
      end

      # Precompute the checksum on each of the replicas, before we lock them.
      # This precomputed checksum is the used to speed the checksum
      # recomputation step up.
      def precompute_checksums
        connections_in_phase(Replica3PCConnectedPhase).each do |cn|
          with_replica_error_handler(cn) do
            cn.send_precompute_checksum
          end
        end
        wait_for_phase(Replica3PCChecksumPrecomputedPhase)
      rescue PhaseQuorumError => e
        log_3pc_state "failure", result: :failed_to_precompute
        abort_all_transactions "aborted due to too few connections to replicas"
        raise GitHub::DGit::ThreepcError, "failed to precompute checksum #{e}"
      end

      # Destroy all connections by releasing locks and failing open
      # transactions as needed.
      def destroy_connections
        @connections.each do |cn|
          if cn.locked?
            with_replica_error_handler(cn) do
              cn.release_lock
            end
          end
          if !cn.decided?
            cn.fail_transaction "replica aborted due to overall failure"
          end
        end
      end

      def ready_for_3pc_ref_list?(cn)
        cn.in_phase?(Replica3PCConnectedPhase) || cn.in_phase?(Replica3PCChecksumPrecomputedPhase)
      end

      # Acquire a quorum of replicas' locks, then ask the other
      # replicas to grab their locks, too (but don't wait for them to
      # finish). The locks in the quorum are acquired serially and in
      # a globally consistent order to avoid a dining philosophers
      # deadlock with another 3PC client.
      #
      # Success is when at least @quorum voting replicas end up locked
      # but not failed. In this case, return normally.
      #
      # If the first replica fails due to Replica3PCBusyError, fail
      # all replicas and raise ThreepcBusyError. If fewer than @quorum
      # voting replicas overall acquire the lock successfully, fail
      # all replicas and raise ThreepcFailedToLock.
      def acquire_lock_quorum
        # Remember: @connections is in the order specified by
        # GitHub::DGit::Delegate#get_write_routes.

        ready_voters_count = 0

        abort_if_hopeless "acquiring locks"

        @connections.each_with_index do |cn, i|
          next unless ready_for_3pc_ref_list?(cn)

          with_replica_error_handler(cn) do
            cn.send_3pc_ref_list
            while cn.in_phase?(Replica3PCWaitingForLockPhase) && process_events
              abort_if_hopeless "acquiring locks"
            end
          end

          if cn.locked? && !cn.failed?
            # We successfully acquired the lock for this connection.
            if cn.voting?
              ready_voters_count += 1

              if ready_voters_count >= @quorum
                # That one put us over the top. The rest of the locks
                # can be acquired in parallel. Get them all started at
                # once, but don't wait for them:
                @connections[i + 1..-1].each do |cn|
                  if ready_for_3pc_ref_list?(cn)
                    with_replica_error_handler(cn) do
                      cn.send_3pc_ref_list(have_quorum: true)
                    end
                  end
                end
                return
              end
            end
          elsif cn.index == 0 && cn.in_phase?(Replica3PCFailedTooBusyPhase)
            # The first replica failed to acquire its dgit-state lock
            # because of lock contention with other processes trying
            # to write to it. We don't want to failover to the other
            # replicas, because (at best) we might end up completing
            # the transaction with a 2/3 quorum using replicas 2 and
            # 3, which would leave replica 1 out of sync. So just give
            # up in this case:
            raise FirstReplicaTooBusyError, "aborted because the repository is too busy"
          end
        end

        if ready_voters_count < @quorum
          raise PhaseQuorumError,
                "only #{ready_voters_count} voting replicas reached phase " \
                "#{Replica3PCCanCommitQueryPhase}"
        end
      rescue FirstReplicaTooBusyError
        log_3pc_state "failure", result: :too_busy
        abort_all_transactions "aborted due to lock contention on the first replica"
        raise GitHub::DGit::ThreepcBusyError, "repo is too busy"
      rescue PhaseQuorumError
        log_3pc_state "failure", result: :insufficient_quorum
        abort_all_transactions "aborted due to insufficient quorum for dgit lock"
        message = "failed to lock checksum"
        if GitRPC.test_tracer
          message = message + "\n" + GitRPC.test_tracer.log_of_3pc
        end
        raise GitHub::DGit::ThreepcFailedToLock, message
      end

      # Get all replicas to one of the old_checksum_reported states or some
      # other decided state. If a quorum doesn't succeed, fail all other
      # replicas and raise PhaseQuorumError.
      def prepare_for_ok
        wait_for_phase(Replica3PCPhase::OldChecksumReported)
      rescue PhaseQuorumError
        log_3pc_state "failure", result: :insufficient_ok_quorum
        abort_all_transactions "aborted due to insufficient quorum ready for 'ok?'"
        raise GitHub::DGit::ThreepcFailedToLock, "failed preparing for 'ok?'"
      end

      # If all voting replicas are unanimous about the checksum, and
      # that value differs from @threepc_before_checksum, then assume
      # the replicas are right and adjust @threepc_before_checksum to
      # match.
      def maybe_autorepair_checksum
        # figure out if the replicas all have the same on-disk checksum
        votes = connections_in_phase(Replica3PCPhase::OldChecksumReported)
                .select(&:voting?)
                .group_by(&:checksum)
        majority_checksum, majority_voters = votes.max_by { |_k, v| v.length }

        # We require unanimity among voting replicas.
        return unless majority_checksum.is_a?(String) &&
                      majority_voters.length == @connections.count(&:voting?) &&
                      majority_voters.length >= @quorum

        if @threepc_before_checksum != majority_checksum
          GitHub.logger.info("auto-corrected db repo checksum",
                             "from_checksum" => @threepc_before_checksum,
                             "to_checksum" => majority_checksum)

          @threepc_before_checksum = majority_checksum
          log_3pc_state "auto-corrected-checksum"
        end
      end

      # If @quorum is met, set @threepc_before_checksum to reflect the
      # majority. Otherwise, raise PhaseQuorumError.
      def initialize_checksum(checksum_host)
        if checksum_host && checksum_host != :vote
          cn = @connections.find { |cn| cn.host == checksum_host }
          unless cn &&
                 cn.in_phase?(Replica3PCPhase::OldChecksumReported) &&
                 cn.checksum.is_a?(String)
            raise GitHub::DGit::ThreepcError,
                  "no checksum for requested host #{checksum_host.inspect}"
          end
          repo_checksum = cn.checksum
        else
          votes = connections_in_phase(Replica3PCPhase::OldChecksumReported)
                  .select(&:voting?)
                  .group_by(&:checksum)
          repo_checksum, majority_voters = votes.max_by { |_k, v| v.length }
          if !repo_checksum.is_a?(String)
            abort_all_transactions "aborted due to failure to determine checksum"
            log_3pc_state "failure", result: :unknown_checksum
            raise GitHub::DGit::ThreepcFailedToLock, "no initial checksum could be determined"
          elsif majority_voters.length < @quorum
            abort_all_transactions "aborted due to insufficient quorum for initializing checksum"
            log_3pc_state "failure", result: :backends_disagreed
            raise GitHub::DGit::ThreepcFailedToLock, "too few replicas agree on the initial checksum"
          end
        end

        GitHub::DGit::threepc_debug "initial_checksum " \
                                    "#{@delegate.namespace}: #{@delegate.id} " \
                                    "#{votes.inspect} #{repo_checksum.inspect}"
        @threepc_before_checksum = repo_checksum
      end

      # Send the "ok?" queries to the replicas that are still with us.
      # This switches them to WAITING_FOR_OK PHASE.
      def send_ok_queries(checksum)
        connections_in_phase(Replica3PCCanCommitQueryPhase).each do |cn|
          with_replica_error_handler(cn) do
            cn.send_ok_query(checksum)
          end
        end
      end

      # wait for all the connections to either fail or reach the
      # precommit phase
      def prepare_for_pre_commit
        wait_for_phase(Replica3PCReadyForPreCommitPhase)
      rescue PhaseQuorumError
        abort_all_transactions "aborted due to insufficient quorum ready for pre-commit"
        raise
      end

      def send_pre_commit_commands(checksum)
        connections_in_phase(Replica3PCReadyForPreCommitPhase).each do |cn|
          with_replica_error_handler(cn) do
            cn.maybe_send_pre_commit_command(checksum)
          end
        end
      end

      def wait_for_ack
        wait_for_phase(Replica3PCReadyForCommitPhase)
      rescue PhaseQuorumError
        @connections.each do |cn|
          if cn.in_phase?(Replica3PCReadyForCommitPhase)
            with_replica_error_handler(cn) do
              cn.abort_update("aborted due to lack of consensus during precommit")
            end
          elsif !cn.decided?
            cn.fail_transaction("unexpected phase #{cn.phase} waiting for ack")
          end
        end
        raise
      end

      def send_commit_commands
        connections_in_phase(Replica3PCReadyForCommitPhase).each do |cn|
          with_replica_error_handler(cn) do
            cn.send_commit_command
          end
        end
      end

      # wait for all the connections to be decided
      def prepare_for_done
        while !@connections.all?(&:decided?) && process_events
        end
      end

      # If there are not enough non-failed voting replicas to attain
      # `@quorum`, raise PhaseQuorumError.
      def abort_if_hopeless(action)
        voters = @connections.select(&:voting?)
        failed = voters.count(&:failed?)

        if voters.length - failed >= @quorum
          # There is still hope
        elsif voters.length < @quorum
          raise PhaseQuorumUnattainableError, "too few voting replicas while #{action}"
        elsif failed == voters.length
          raise PhaseQuorumError, "all voting replicas failed while #{action}"
        else
          raise PhaseQuorumUnattainableError, "too many voting replicas failed while #{action}"
        end
      end

      # If all replicas (including nonvoting replicas) have either
      # reached the requested phase or are decided, then assess the
      # outcome:
      #
      # * If at least @quorum voting replicas have reached the desired
      #   phase, then return the number that reached it.
      #
      # * If too few voting replicas have reached the desired phase,
      #   raise PhaseQuorumError.
      #
      # If one or more replicas are still undecided, return nil.
      def phase_reached?(phase)
        return nil unless @connections.all? { |cn| cn.in_phase?(phase) || cn.decided? }

        succeeded = @connections.count { |cn| cn.in_phase?(phase) && cn.voting? }
        if succeeded < @quorum
          raise PhaseQuorumError,
                "only #{succeeded} voting replicas reached phase #{phase}"
        end

        succeeded
      end

      def wait_for_phase(phase)
        while !phase_reached?(phase) && process_events
        end
      end

      # Process a single round of I/O. Return false iff there is
      # nothing left to do (i.e., if all connections are completely
      # done). This method must only be called when all connections
      # are in "done" state (in which case it will return false) or
      # when at least one connection has a timeout set.
      def process_events
        write_sockets = []
        read_sockets = []
        connectionmap = {}
        @connections.each do |cn|
          if cn.want_to_read?
            read_sockets << cn.socket
            connectionmap[cn.socket] = cn
          end
          if cn.want_to_write?
            write_sockets << cn.socket
            connectionmap[cn.socket] = cn
          end
        end

        return false if write_sockets.empty? && read_sockets.empty?

        # Make sure that select() doesn't wait longer than the next
        # connection timeout:
        timeout = @connections.map(&:time_remaining).compact.min
        if !timeout
          phase_names = @connections.map { |cn| "#{cn.host}: #{cn.phase}" }.join(", ")
          raise GitHub::DGit::ThreepcInternalError,
                "process_io called with no timeout active; phases=[#{phase_names}]"
        elsif timeout < 0
          # A connection has nominally timed out, but poll one more
          # time:
          timeout = 0
        end

        ready = IO.select(read_sockets, write_sockets,
                          read_sockets + write_sockets,
                          timeout)

        if ready.nil?
          # If no sockets are ready for I/O then it means that we
          # hit a timeout. Note that we can't guarantee that
          # IO.select's timeout will exactly line up with our own,
          # so it's possible that we might not actually process
          # this until we poll again.
          @connections.each &:process_timeout
          return true
        end

        r, w, e = ready

        T.must(w).map { |socket| connectionmap[socket] }.each do |cn|
          with_replica_error_handler(cn) do
            cn.process_output
          end
        end

        T.must(r).map { |socket| connectionmap[socket] }.each do |cn|
          with_replica_error_handler(cn) do
            cn.process_input
          end
        end

        T.must(e).map { |socket| connectionmap[socket] }.each do |cn|
          with_replica_error_handler(cn) do
            cn.process_exception
          end
        end

        true
      end

      # Abort any transactions that can be aborted. This is gentler
      # than failing; it retains the lock if possible.
      def abort_all_transactions(msg)
        @connections.each do |cn|
          if cn.abortable?
            with_replica_error_handler(cn) do
              cn.abort_update(msg)
            end
          elsif !cn.decided?
            # This code shouldn't be reached, because all of the
            # phases after UNINITIALIZED are either Abortable or
            # Decided.
            cn.fail_transaction(msg)
          end
        end
      end

      # Fail any connections that are not yet decided.
      def fail_all_transactions(msg)
        @connections.each do |cn|
          cn.fail_transaction(msg) unless cn.decided?
        end
      end

      def with_replica_error_handler(cn)
        yield
      rescue Replica3PCFailedError => e
        GitHub::DGit::threepc_debug "#{cn.inspect} failed: #{e.message}"
      end

      # Return a lazy Enumerator over the connections that are in the
      # specified phase (or any of its subclasses). It is important
      # that this be lazy, so that if the code processing one
      # connection changes the phase of a connection later in the
      # list, the later connection is filtered based on its phase at
      # the time we get to it.
      def connections_in_phase(phase)
        @connections.lazy.select { |cn| cn.in_phase?(phase) }
      end

      # The transaction succeeded, but there may have been dissenting
      # or failed replicas (possibly among nonvoting replicas). This
      # is still slightly worrying, so log this to splunk.
      #
      # Report some common cases as more specific needles to make them
      # easier to scan for patterns.
      def report_dissent(ok_voter_count, repo_checksum, dissented, failed)
        return if @ignore_dissent || (dissented.empty? && failed.empty?)

        if dissented.size == 1 && failed.empty?
          cn = dissented.first
          if cn.voting?
            GitHub.logger.info("one voting replica dissented",
                               "gh.dgit.3pc.method" => "report_dissent",
                               "gh.dgit.delegate.flipper_id" => "#{@delegate.namespace}##{@delegate.id}",
                               "gh.dgit.3pc.ok_voter_count" => ok_voter_count,
                               "gh.dgit.3pc.quorum_count" => @quorum,
                               "gh.dgit.3pc.conn.error" => cn.err,
                               "gh.spokes.fileserver" => cn.host)
          else
            GitHub.logger.info("one nonvoting replica dissented",
                               "gh.dgit.3pc.method" => "report_dissent",
                               "gh.dgit.delegate.flipper_id" => "#{@delegate.namespace}##{@delegate.id}",
                               "gh.dgit.3pc.conn.error" => cn.err,
                               "gh.spokes.fileserver" => cn.host)
          end
        elsif failed.size == 1 && dissented.empty?
          cn = failed.first
          if cn.voting?
            GitHub.logger.info("one voting replica failed",
                               "gh.dgit.3pc.method" => "report_dissent",
                               "gh.dgit.delegate.flipper_id" => "#{@delegate.namespace}##{@delegate.id}",
                               "gh.dgit.3pc.ok_voter_count" => ok_voter_count,
                               "gh.dgit.3pc.quorum_count" => @quorum,
                               "gh.dgit.3pc.conn.error" => cn.err,
                               "gh.spokes.fileserver" => cn.host)
          else
            GitHub.logger.info("one nonvoting replica failed",
                               "gh.dgit.3pc.method" => "report_dissent",
                               "gh.dgit.delegate.flipper_id" => "#{@delegate.namespace}##{@delegate.id}",
                               "gh.dgit.3pc.conn.error" => cn.err,
                               "gh.spokes.fileserver" => cn.host)
          end
        else
          dissented_voters, dissented_nonvoters = dissented.partition(&:voting?).map(&:length)
          failed_voters, failed_nonvoters = failed.partition(&:voting?).map(&:length)

          problems = [
            [dissented_voters, "voting", "dissented"],
            [failed_voters, "voting", "failed"],
            [dissented_nonvoters, "nonvoting", "dissented"],
            [failed_nonvoters, "nonvoting", "failed"],
          ].map do |count, v, p|
            if count > 0
              r = (count == 1) ? "replica" : "replicas"
              "#{count} #{v} #{r} #{p}"
            end
          end.compact.join("; ")

          if dissented_voters > 0 || failed_voters > 0
            GitHub.logger.info("voting replicas were not unanimous",
                               "gh.dgit.3pc.method" => "report_dissent",
                               "gh.dgit.delegate.flipper_id" => "#{@delegate.namespace}##{@delegate.id}",
                               "gh.dgit.3pc.problems" => problems)
          else
            GitHub.logger.info("voting replicas were unanimous, but not nonvoting replicas",
                               "gh.dgit.3pc.method" => "report_dissent",
                               "gh.dgit.delegate.flipper_id" => "#{@delegate.namespace}##{@delegate.id}",
                               "gh.dgit.3pc.problems" => problems)
          end
        end
      end

      def histories
        @connections.map { |cn| [cn.shorthost, cn.history] }
      end

      # Write a structured log record with the state, phase, and checksum for
      # each host.
      def log_3pc_state(at, result: :unknown)
        log_blob = { "gh.dgit.3pc.method" => "refs_3pc",
                    "gh.dgit.3pc.priority" => @priority,
                    "gh.repo.name_with_owner" => @repo_name,
                    "gh.timing.elapsed_seconds" => Time.now - @start,
                    "gh.dgit.3pc.before_checksum" => @threepc_before_checksum,
                    "gh.dgit.3pc.at" => at,
                    "gh.dgit.3pc.result" => result }

        log_blob["gh.request_id"] = @request_id unless @request_id.nil?
        log_blob["gh.dgit.3pc.elapsed_locking_seconds"] = @lock_acquired - @lock_start unless @lock_acquired.nil? || @lock_start.nil?
        log_blob["gh.dgit.3pc.elapsed_under_lock_seconds"] = Time.now - @lock_acquired unless @lock_acquired.nil?

        @connections.each do |cn|
          log_blob.merge!(cn.log_state)
        end
        GitHub.logger.info("3PC state", log_blob)
        if GitRPC.test_tracer
          GitRPC.test_tracer.log_3pc_state(log_blob)
        end

        if %w[failure finish].include?(at)
          @status = at == "finish" ? :ok : :failure
          @result = result
          GitHub.dogstats.increment("dgit.3pc.completed",
                                    tags: ["status:#{@status}", "result:#{@result}", "priority:#{@priority}"])
        end
      end
    end

    # Write `arg` to stdout(!) with a timestamp. This should only be
    # enabled when debugging with test data, because sensitive
    # information might be sent to it.
    def self.threepc_debug(arg)
      return unless GitHub.dgit_threepc_debug_enabled?
      t = Time.now.utc.iso8601(3)
      arg = arg.inspect if !arg.is_a?(String)
      puts "#{t} #{arg}"
    end

    class SpokesdThreePhaseCommitClient < ThreePhaseCommitClient
      def commit(refs_before_after_status, sockstat = {}, reflog_msg = "")
        @start = Time.now

        fileservers = if @delegate.namespace == "gist-creation"
          @delegate.get_3pc_routes.map { |r| r.fileserver.fqdn }
        else
          nil
        end
        network_id = @delegate.respond_to?(:network_id) ? @delegate.network_id : nil
        client = GitHub::Spokes::Client::Spokesd.instance
        begin
          status = client.commit_refs(
            network_id: network_id,
            repo_id: @delegate.id,
            repo_type: @delegate.repo_type,
            nwo: @repo_name,
            priority: @priority,
            refs: refs_before_after_status,
            reflog_msg: reflog_msg,
            sockstat: sockstat,
            name: @delegate.respond_to?(:name) ? @delegate.name : nil,
            fileservers: fileservers,
          )

        rescue GitHub::DGit::Error => e
          at = "commit_error"
          result = e
          status = {}
          log_3pc_compare(at, @start, "Spokesd", status, result)
          raise
        else
          at = "commit_finish"
          result = "ok"
          log_3pc_compare(at, @start, "Spokesd", status, result)
        end

        status
      end

      def update_default_branch(new_value, sockstat = {}, reflog_msg = "")
        @start = Time.now

        network_id = @delegate.respond_to?(:network_id) ? @delegate.network_id : nil
        client = GitHub::Spokes::Client::Spokesd.instance
        begin
          status = client.update_default_branch(
            network_id: network_id,
            repo_id: @delegate.id,
            repo_type: @delegate.repo_type,
            nwo: @repo_name,
            priority: @priority,
            new_value: new_value,
            sockstat: sockstat,
            name: @delegate.respond_to?(:name) ? @delegate.name : nil,
          )
        rescue GitHub::DGit::Error => e
          at = "update_default_branch_error"
          result = e
          status = {}
          log_3pc_compare(at, @start, "Spokesd", status, result)
          raise
        else
          at = "update_default_branch_finish"
          result = "ok"
          log_3pc_compare(at, @start, "Spokesd", status, result)
        end

        status
      end

      # update_nwo_file - Create or update the info/nwo file repository that
      # is stored in DFS hosts.
      #  - nwo - a string representing the name with owner of the repository.
      #
      # Returns: nothing
      #
      # update_nwo_file can also raise several different exceptions that
      # subclass `GitHub::DGit::Error`.
      def update_nwo_file(new_nwo, sockstat = {})
        @start = Time.now
        network_id = @delegate.respond_to?(:network_id) ? @delegate.network_id : nil

        client = GitHub::Spokes::Client::Spokesd.instance
        begin
          status = client.update_info_nwo(
            nwo: new_nwo,
            repo_id: @delegate.id,
            repo_type: @delegate.repo_type,
            priority: @priority,
            sockstat: sockstat,
            name: @delegate.respond_to?(:name) ? @delegate.name : nil,
          )
        rescue GitHub::DGit::Error => e
          at = "update_nwo_file_error"
          result = e
          status = {}
          log_3pc_compare(at, @start, "Spokesd", status, result)
          raise
        else
          at = "update_nwo_file_finish"
          result = "ok"
          log_3pc_compare(at, @start, "Spokesd", status, result)
        end

        status
      end

      # recompute_checksums - Recompute the checksums for all replicas of a git repository,
      # and vote on the new consensus checksum.
      #  - voting_strategy, checksum_host, ignore_dissent: these parameters are not used in spokes,
      #    but are included to maintain compatibility with the monolith 3pc version of this function.
      def recompute_checksums(voting_strategy, checksum_host, sockstat = {}, ignore_dissent: false)
        @start = Time.now

        network_id = @delegate.respond_to?(:network_id) ? @delegate.network_id : nil
        client = GitHub::Spokes::Client::Spokesd.instance
        begin
          status = client.recompute_checksums(
            network_id: network_id,
            repo_id: @delegate.id,
            repo_type: @delegate.repo_type,
            nwo: @repo_name,
            priority: @priority,
            sockstat: sockstat,
            name: @delegate.respond_to?(:name) ? @delegate.name : nil,
          )

        rescue GitHub::DGit::Error => e
          at = "recompute_checksums_error"
          result = e
          status = {}
          log_3pc_compare(at, @start, "Spokesd", status, result)
          raise
        else
          at = "recompute_checksums_finish"
          result = "ok"
          log_3pc_compare(at, @start, "Spokesd", status, result)
        end

        status
      end
    end
  end
end
