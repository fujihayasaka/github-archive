# typed: false
# frozen_string_literal: true

require "time"
require "socket"

module GitHub
  class DGit
    # Times the client is willing to wait:
    TXN_COMMITTING_TIMEOUT = 5.0
    TXN_CHECKSUMMING_FROM_SCRATCH_TIMEOUT = 300.0

    TXN_READ_TIMEOUT = 2.0

    # The time for `get-checksum` to respond can include the time it
    # takes to compute the checksum from scratch. So give it more
    # time. This won't always suffice, but even if it fails, hopefully
    # `dgit-helper` will write the new checksum to disk, allowing
    # subsequent attempts to succeed.
    TXN_READ_CHECKSUM_TIMEOUT = 6.0

    class Replica3PCFailedError < GitHub::DGit::Error; end

    # Base class for the objects stored in Replica3PCPhase#phase.
    # These classes implement the state pattern for the 3PC protocol
    # with a single replica.
    class Replica3PCPhase
      class << self
        attr_accessor :phase_name
        protected :phase_name= # only the inherited hook should call the setter
      end

      # Precompute the phase_name when a class is created.
      def self.inherited(klass)
        if klass.name =~ /Replica3PC(.*)Phase/
          klass.phase_name = Regexp.last_match[1].gsub(/(.)([A-Z])/, '\1_\2').downcase
        else
          raise GitHub::DGit::ThreepcError,
            "unexpected class name #{klass.name.inspect}, all descendants of Replica3PCPhase must match /Replica3PC(.*)Phase/"
        end
      end

      # Mixin for phases with generic read time limits.
      module Deadline
        def time_limit
          GitHub.threepc_read_txn_timeout || TXN_READ_TIMEOUT
        end
      end

      # Mixin for phases during which, if there is a bailout, we no
      # longer know what the replica's checksum is.
      module ChecksumIndeterminateOnBailOut
        def bail_out(msg, new_phase_type: Replica3PCFailedPhase)
          @cn.checksum = :indeterminate
          super
        end
      end

      module OldChecksumReported
      end

      module Locked
        def locked?
          true
        end
      end

      module Abortable
        def abortable?
          true
        end

        def abort_update(msg, checksum_on_success:, checksum_on_failure:)
          @cn.send_3pc_line("abort")
          @cn.err ||= msg
          new_phase_type =
            if locked?
              Replica3PCAbortingWhileLockedPhase
            else
              Replica3PCAbortingWhileUnlockedPhase
            end
          new_phase = new_phase_type.new(
            @cn,
            checksum_on_success: checksum_on_success,
            checksum_on_failure: checksum_on_failure,
          )
          @cn.set_phase(new_phase)
        end
      end

      # Mixin to include the short_string method in the classes which need it
      module ShortString
        # Return a short version of String s, replacing the middle with
        # "[...]" if necessary to include at most maxlen characters from
        # the string in the output.
        def short_string(s, maxlen: 1050)
          if s.length <= maxlen
            s.inspect
          else
            tail_len = (0.25 * maxlen).round
            abbrev = "#{s[0...(maxlen - tail_len)]}[...]#{s[-tail_len..-1]}"
            s = "#{abbrev.inspect} (#{s.length} chars total)"
          end
        end
      end

      # Mixin for phases where we still might be waiting for the
      # protocol to start via an HTTP header. Whether it has already
      # been seen depends on `@cn.accepted`.
      module Startup
        include Abortable
        include ShortString

        # If `input` is part of the HTTP response header, then handle
        # it and return true. Otherwise, return false.
        def handle_http_header_line(input)
          case @cn.accepted
          when nil
            m = /\AHTTP\/1.1 (\d{3}) (.*)\r\z/.match(input)
            if !m
              raise GitHub::DGit::ThreepcError,
                    "gitrpcd returned an unrecognized HTTP error"
            end

            if m[1] == "200"
              @cn.accepted = :partial
            else
              err = m[2]
              @cn.log_event "read error #{short_string(err)}"
              @cn.accepted = true
              bail_out(err)
            end

            true
          when :partial
            # Make sure that this is the blank line following the header:
            if input != "\r"
              raise GitHub::DGit::ThreepcError,
                    "gitrpcd did not properly terminate the HTTP response header"
            end

            @cn.accepted = true
            true
          when true
            false
          end
        end

        def handle_input
          # Read the line, then determine whether it is part of the
          # HTTP header or whether it should be processed
          # generically:
          input = @cn.recv_3pc_line
          return false unless input
          handle_http_header_line(input) || handle_line(input)
          true
        end

        def abort_update(msg)
          super(
            msg,
            checksum_on_success: :indeterminate,
            checksum_on_failure: :indeterminate,
          )
        end
      end

      module Decided
        def decided?
          true
        end
      end

      module Failed
        def failed?
          true
        end
      end

      module Closed
        def open?
          false
        end

        def write_pending?
          false
        end

        def want_to_read?
          false
        end
      end

      def initialize(cn)
        @cn = cn
      end

      # Does this phase have a time limit? If so, return the time
      # limit in seconds.
      def time_limit
        nil
      end

      # Is the socket open in this phase?
      def open?
        true
      end

      # Are we known to hold the replica's dgit-state lock?
      def locked?
        false
      end

      def abortable?
        false
      end

      # Release the `dgit-state` lock and transition to the next
      # phase.
      def release_lock
        raise GitHub::DGit::ThreepcError,
              "#{__method__} called in phase #{self}"
      end

      # Has the replica cleanly made it all the way through the
      # protocol (except possibly for the "unlock" command) and is
      # ready for its checksum to be considered as part of a consensus
      # vote? The answer doesn't depend on whether this is a voting
      # vs. nonvoting replica. Note that this can return true even if
      # the update failed for a Git-level reason that we recognize.
      def eligible_to_vote?
        decided? && !failed?
      end

      # Has the final state of this replica been decided? This returns
      # true even if the transaction failed on this replica.
      def decided?
        false
      end

      # Has this replica failed (including
      # Replica3PCFailedReadyForDonePhase)?
      def failed?
        false
      end

      # Do we want to poll for input in this phase?
      def want_to_read?
        true
      end

      # Do we have data we are ready to write to the socket?
      def write_pending?
        !@cn.send_buffer.empty?
      end

      # Do we want to poll to see if we can write to the socket in this phase?
      def want_to_write?
        write_pending?
      end

      # End the transaction in an orderly way, retaining the lock if
      # we currently hold it.
      def abort_update(msg)
        raise GitHub::DGit::ThreepcError,
              "#{__method__} called in phase #{self}"
      end

      # Bail out the transaction with this replica and transfer to the
      # specified phase.
      def bail_out(msg, new_phase_type: Replica3PCFailedPhase)
        @cn.log_event "bailing out (checksum=#{@cn.checksum}): #{msg.inspect}"
        @cn.err = msg
        @cn.set_phase(new_phase_type.new(@cn))
        raise Replica3PCFailedError
      end

      # The client has just switched to this phase. Perform any
      # preparation steps that are necessary.
      def enter_phase(old_phase)
        update_deadline
      end

      def update_deadline
        if time_limit
          @cn.deadline = @cn.phase_begin + time_limit
        else
          @cn.deadline = nil
        end
      end

      # The socket is ready to be written to.
      def handle_output
        @cn.drain_3pc_msg
      end

      # The default is that no input is allowed.
      def handle_line(input)
        bail_out("unexpected input during #{@cn.phase} phase: '#{input.inspect}'")
      end

      # If any input in recv_pending is processable, do so, delete the
      # used input from the buffer, and return true; otherwise, return
      # false.
      def handle_input
        input = @cn.recv_3pc_line
        return false unless input
        handle_line(input)
        true
      end

      # Handle an EOF that happened when reading the socket.
      def handle_eof(msg)
        bail_out("server disconnected during #{@cn.phase} phase: #{msg}")
      end

      # The default is to bail out if timeouts are allowed in this
      # phase, and otherwise to raise an exception.
      def handle_timeout
        if time_limit
          bail_out("timed out during '#{@cn.phase}' phase")
        else
          raise GitHub::DGit::ThreepcError,
                "unexpected timeout in phase #{@cn.phase}"
        end
      end

      def handle_exception
        bail_out("IO#select indicated error on this socket")
      end

      def to_s
        self.class.phase_name
      end
    end

    # Client is not fully initialized; in particular, its socket
    # hasn't been created and no connection attempt has yet been made.
    # Wait for the caller to call start_connection, then transition to
    # STARTING_CONNECTION phase.
    class Replica3PCUninitializedPhase < Replica3PCPhase
      include Replica3PCPhase::Closed
    end

    # This phase is entered at the beginning of start_connection, and
    # left once the DNS lookup is done and a connection attempt has
    # been made. At that point, transition either to CONNECTING or
    # CONNECTED phase (depending on whether the socket
    # connect_nonblock call succeeds immediately). This phase is
    # mainly here to separate the timing of what happens between
    # initialize and start_connection from the timing of actually
    # creating the connection.
    class Replica3PCStartingConnectionPhase < Replica3PCPhase
      include Replica3PCPhase::Closed
    end

    # Socket is still not (necessarily) fully connected. Wait for the
    # socket to be ready for write, then finish connecting and switch
    # to CONNECTED phase.
    class Replica3PCConnectingPhase < Replica3PCPhase
      include Replica3PCPhase::Abortable
      include Replica3PCPhase::Deadline

      def write_pending?
        false
      end

      # In connecting phase, we always want to poll for writability
      # because that gives us our indication that the connection has
      # been established.
      def want_to_write?
        true
      end

      def handle_output
        @cn.finish_connecting
        super
      end

      def abort_update(msg)
        bail_out(msg)
      end
    end

    # Socket is connected. On entry to this phase, send the commands
    # to gitrpcd to start up dgit-update. Then wait for the caller to
    # call cn.send_3pc_ref_list or cn.send_precompute_checksum at which
    # point we transition to WAITING_FOR_LOCK or WAITING_FOR_CHECKSUM_PRECOMPUTE
    # phase.
    class Replica3PCConnectedPhase < Replica3PCPhase
      include Replica3PCPhase::Startup

      def enter_phase(old_phase)
        super
        @cn.send_initial_commands
      end
    end

    class Replica3PCWaitingForChecksumPrecomputePhase < Replica3PCPhase
      include Replica3PCPhase::Startup

      def time_limit
        TXN_CHECKSUMMING_FROM_SCRATCH_TIMEOUT
      end

      def handle_line(input)
        case input
        when /\Aprecomputed/
          @cn.set_phase(Replica3PCChecksumPrecomputedPhase.new(@cn))
        else
          super
        end
      end
    end

    class Replica3PCChecksumPrecomputedPhase < Replica3PCPhase
      include Replica3PCPhase::Startup
    end

    # We've sent the `lock --fast` command to the fileserver. Wait for
    # it to reply with "locked", then transition to
    # WAITING_FOR_CHECKSUM phase.
    class Replica3PCWaitingForLockPhase < Replica3PCPhase
      include Replica3PCPhase::Startup

      def time_limit
        @cn.class.lock_timeout(@cn.index)
      end

      def handle_line(input)
        case input
        when /\Alocked( [0-9a-f:]+)?/
          # We don't read the checksum here since we'll get it as the
          # result of `get-checksum`.
          @cn.set_phase(Replica3PCWaitingForChecksumPhase.new(@cn))
        when /\Alocking-failed (?<reason>.*)/
          reason = Regexp.last_match[:reason]
          bail_out("failed to acquire dgit-state lock: #{reason}")
        when /\Arepo-busy/
          bail_out("failed to acquire dgit-state lock: repo is too busy",
                   new_phase_type: Replica3PCFailedTooBusyPhase)
        else
          super
        end
      end
    end

    # We just got the result of `lock --fast` and have already sent
    # `get-checksum` and possibly `forget-checksum`. Wait for the
    # response to the latter, then transition to CAN_COMMIT_QUERY or
    # WAITING_FOR_FORGOTTEN phase.
    class Replica3PCWaitingForChecksumPhase < Replica3PCPhase
      include Replica3PCPhase::Locked
      include Replica3PCPhase::Abortable

      def time_limit
        TXN_READ_CHECKSUM_TIMEOUT
      end

      def handle_line(input)
        case input
        when /\Achecksum (?<checksum>[0-9a-f:]+)/
          @cn.pre_checksum = Regexp.last_match[:checksum]
          if @cn.checksum_from_scratch
            @cn.checksum = :indeterminate
          else
            @cn.checksum = @cn.pre_checksum
          end
          if @cn.streamlined_ok?
            @cn.set_phase(Replica3PCWaitingForOkPhase.new(@cn))
          else
            @cn.set_phase(Replica3PCCanCommitQueryPhase.new(@cn))
          end
        when /\Anot-locked/
          bail_out("not-locked error when waiting for checksum")
        else
          super
        end
      end

      def abort_update(msg)
        super(
          msg,
          checksum_on_success: @cn.checksum,
          checksum_on_failure: @cn.checksum,
        )
      end
    end

    # The fileserver is "ready" to accept our "ok?" query. Wait for
    # the caller to call cn.send_ok_query.
    class Replica3PCCanCommitQueryPhase < Replica3PCPhase
      include Replica3PCPhase::Locked
      include Replica3PCPhase::OldChecksumReported
      include Replica3PCPhase::Abortable

      # Note that we don't set a deadline here, because the other side
      # is still waiting for our "ok?".

      def abort_update(msg)
        super(
          msg,
          checksum_on_success: @cn.checksum,
          checksum_on_failure: @cn.checksum,
        )
      end
    end

    # We have sent the "ok?" query. Wait for the fileserver to respond
    # with "ok", then transition to READY_FOR_PRE_COMMIT phase. If the
    # fileserver reports an error, handle it.
    class Replica3PCWaitingForOkPhase < Replica3PCPhase
      include Replica3PCPhase::Locked
      include Replica3PCPhase::OldChecksumReported
      include Replica3PCPhase::Abortable
      include Replica3PCPhase::Deadline

      def handle_line(input)
        case input
        when "ok"
          @cn.set_phase(Replica3PCReadyForPreCommitPhase.new(@cn))
        when /\Awrong-checksum (?<checksum>.*)/
          @cn.checksum = Regexp.last_match[:checksum]
          bail_out("server reported mismatched checksum #{@cn.checksum}",
                   new_phase_type: Replica3PCFailedReadyForDonePhase)
        when /\Afailure (?<reason>.*)/
          reason = Regexp.last_match[:reason]
          case reason
          when /\Acannot lock ref '(?<refname>.*?)': .*file exists/i
            _ref_update_failed(Regexp.last_match[:refname], "lock exists")
          when /\Acannot lock ref '(?<refname>.*?)': (?<details>.*)/i
            _ref_update_failed(Regexp.last_match[:refname], reason, Regexp.last_match[:details])
          when /\Acannot update (the )?ref '(?<refname>.*?)': (?<details>.*)/i
            _ref_update_failed(Regexp.last_match[:refname], "failed", Regexp.last_match[:details])
          when /\A[mM]ultiple updates for ref '(?<refname>.*?)' not allowed/i
            _ref_update_failed(Regexp.last_match[:refname], "multiple updates not allowed")
          when /\Aunable to create '[a-z0-9\/\._-]+\/(?<lockfile>[a-z0-9\._-]+)': File exists\..*/i
            bail_out("update failed because file '#{Regexp.last_match[:lockfile]}' exists",
                     new_phase_type: Replica3PCFailedReadyForDonePhase)
          else
            bail_out("update failed for unrecognized reason: #{reason}",
                     new_phase_type: Replica3PCFailedReadyForDonePhase)
          end
        else
          super
        end
      end

      def _ref_update_failed(refname, reason, details = nil)
        @cn.refs_status[refname] = reason
        err = details ? details.gsub(/'refs\/.+?'/, "'refs/XXXXXXXX'").gsub(/[0-9a-f]{40}/, "HASH") : reason
        @cn.err = "reference update failure: #{err}"
        @cn.set_phase(Replica3PCReadyForDonePhase.new(@cn))
      end

      def abort_update(msg)
        super(
          msg,
          checksum_on_success: @cn.checksum,
          checksum_on_failure: @cn.checksum,
        )
      end
    end

    # The fileserver has answered "ok" and is ready for the
    # "pre-commit" command. Wait for the caller to call
    # cn.send_pre_commit_command.
    class Replica3PCReadyForPreCommitPhase < Replica3PCPhase
      include Replica3PCPhase::Locked
      include Replica3PCPhase::OldChecksumReported
      include Replica3PCPhase::Abortable

      def abort_update(msg)
        super(
          msg,
          checksum_on_success: @cn.checksum,
          checksum_on_failure: @cn.checksum,
        )
      end
    end

    # We have sent "pre-commit" to the fileserver. Wait for it to
    # reply with "ack", then transition to READY_FOR_COMMIT phase.
    class Replica3PCWaitingForAckPhase < Replica3PCPhase
      include Replica3PCPhase::Locked
      include Replica3PCPhase::Deadline
      include Replica3PCPhase::Abortable
      include Replica3PCPhase::ChecksumIndeterminateOnBailOut

      def handle_line(input)
        case input
        when "ack"
          @cn.set_phase(Replica3PCReadyForCommitPhase.new(@cn))
        else
          super
        end
      end

      def abort_update(msg)
        super(
          msg,
          checksum_on_success: @cn.checksum,
          checksum_on_failure: :indeterminate,
        )
      end
    end

    # The fileserver has "ack"ed our "pre-commit" command. Wait for
    # the caller to call cn.send_commit_command, then transition to
    # COMMITTING phase.
    class Replica3PCReadyForCommitPhase < Replica3PCPhase
      include Replica3PCPhase::Locked
      include Replica3PCPhase::Abortable
      include Replica3PCPhase::ChecksumIndeterminateOnBailOut

      def abort_update(msg)
        super(
          msg,
          checksum_on_success: @cn.checksum,
          checksum_on_failure: :indeterminate,
        )
      end
    end

    # We have sent the "commit" command to the fileserver. Wait for it
    # to respond with "committed", then transition to
    # READY_FOR_DONE phase.
    class Replica3PCCommittingPhase < Replica3PCPhase
      include Replica3PCPhase::Locked
      include Replica3PCPhase::Abortable

      def time_limit
        TXN_COMMITTING_TIMEOUT
      end

      def handle_line(input)
        case input
        when /\Acommitted /
          @cn.checksum = input[10..-1]
          if @cn.streamlined_unlock?
            @cn.set_phase(Replica3PCFinishedPhase.new(@cn))
          else
            @cn.set_phase(Replica3PCReadyForDonePhase.new(@cn))
          end
        else
          super
        end
      end

      def abort_update(msg)
        super(
          msg,
          checksum_on_success: :indeterminate,
          checksum_on_failure: :indeterminate,
        )
      end
    end

    class Replica3PCAbortingPhase < Replica3PCPhase
      include Replica3PCPhase::Abortable
      include Replica3PCPhase::Deadline

      # `checksum_on_success` is the value the checksum will be
      # assumed to have if the `aborted` response is received.
      # `checksum_on_failure` is the value that the checksum is
      # assumed to have if that response is *not* received. Either
      # value can be an actual checksum or `:indeterminate`.
      def initialize(cn, new_phase_type, checksum_on_success:, checksum_on_failure:)
        super(cn)
        @new_phase_type = new_phase_type
        @checksum_on_success = checksum_on_success
        @checksum_on_failure = checksum_on_failure
      end

      def handle_line(input)
        case input
        when /\Aaborted/
          @cn.checksum = @checksum_on_success
          @cn.set_phase(@new_phase_type.new(@cn))
        else
          # Whatever mode we aborted out of might have had a response
          # on the way. So just ignore anything but "aborted" in this
          # mode.
        end
      end

      def abort_update(msg)
        # We're already aborting, so no need to abort again.
      end

      def bail_out(msg, new_phase_type: Replica3PCFailedPhase)
        @cn.checksum = @checksum_on_failure
        super
      end
    end

    # The caller has aborted the update by calling cn.abort_update
    # while locked. Wait for the fileserver to reply with "aborted",
    # then transition to READY_FOR_DONE phase.
    class Replica3PCAbortingWhileLockedPhase < Replica3PCAbortingPhase
      include Replica3PCPhase::Locked

      def initialize(cn, checksum_on_success:, checksum_on_failure:)
        super(cn, Replica3PCReadyForDonePhase,
              checksum_on_success: checksum_on_success,
              checksum_on_failure: checksum_on_failure,
             )
      end

      def release_lock
        @cn.log_event "scheduling release of lock"
        begin
          @cn.socket.write_nonblock("unlock\n")
        rescue SystemCallError => boom
          @cn.log_event "releasing lock failed: #{boom.inspect}"
        end
        # Given that we've already sent "unlock", after we receive the
        # "aborted" that we're waiting for, we can already start
        # waiting for "unlocked":
        @new_phase_type = Replica3PCFinishedPhase
      end
    end

    # The caller has aborted the update by calling cn.abort_update
    # while unlocked. Wait for the fileserver to reply with "aborted",
    # then transition to FINISHED phase.
    class Replica3PCAbortingWhileUnlockedPhase < Replica3PCAbortingPhase
      def initialize(cn, checksum_on_success:, checksum_on_failure:)
        super(cn, Replica3PCFinishedPhase,
              checksum_on_success: checksum_on_success,
              checksum_on_failure: checksum_on_failure,
             )
      end
    end

    # The fileserver has just sent "committed", "failed", or
    # "aborted". Wait for the caller to call cn.release_lock then
    # transition to FINISHED phase.
    class Replica3PCReadyForDonePhase < Replica3PCPhase
      include Replica3PCPhase::Locked
      include Replica3PCPhase::Decided

      def release_lock
        @cn.log_event "releasing lock"
        begin
          @cn.socket.write_nonblock("unlock\n")
        rescue SystemCallError => boom
          @cn.log_event "releasing lock failed: #{boom.inspect}"
        end
        @cn.set_phase(Replica3PCFinishedPhase.new(@cn))
      end
    end

    # The fileserver has just sent "wrong-checksum". Wait for the
    # caller to call cn.release_lock then transition to FINISHED
    # phase.
    class Replica3PCFailedReadyForDonePhase < Replica3PCPhase
      include Replica3PCPhase::Locked
      include Replica3PCPhase::Decided
      include Replica3PCPhase::Failed

      def release_lock
        @cn.log_event "releasing lock"
        begin
          @cn.socket.write_nonblock("unlock\n")
        rescue SystemCallError => boom
          @cn.log_event "releasing lock failed: #{boom.inspect}"
        end
        @cn.set_phase(Replica3PCFailedPhase.new(@cn))
      end
    end

    # Abstract base class for finished and failed phases.
    class Replica3PCDonePhase < Replica3PCPhase
      include Replica3PCPhase::Decided
      include Replica3PCPhase::Closed

      # Once we are done, ignore eofs or anything else

      def bail_out(msg, new_phase_type: nil)
      end

      def enter_phase(old_phase)
        if old_phase.open?
          begin
            @cn.socket.close
          rescue SystemCallError
            # pass
          end
        end
        super
      end

      def handle_output
      end

      def handle_input
      end

      def handle_eof(msg)
      end

      def handle_timeout
      end

      def handle_exception
      end
    end

    # The transaction is done and the result is stored in the
    # Replica3PCClient instance. The socket is closed on entry to this
    # phase. This is a terminal phase.
    class Replica3PCFinishedPhase < Replica3PCDonePhase
    end

    # The transaction failed somewhere along the way, either due to a
    # transport error or due to a serious error in the protocol. The
    # socket is closed on entry to this phase. This is a terminal
    # phase.
    class Replica3PCFailedPhase < Replica3PCDonePhase
      include Replica3PCPhase::Failed
    end

    # The transaction failed because the repository is getting so much
    # write traffic that the "dgit-state" lock couldn't be acquired.
    # The socket is closed on entry to this phase. This is a terminal
    # phase.
    class Replica3PCFailedTooBusyPhase < Replica3PCFailedPhase
    end

    # The client for conducting a 3PC transaction with a single DGit
    # replica. This client intermediates between
    # ThreePhaseCommitClient (which is mainly concerned with keeping
    # the quorum of replicas in sync) and gitrpcd / dgit-update on the
    # fileserver. It alternates waiting for its caller to trigger the
    # next step in the protocol, and waiting for the fileserver to
    # reply.
    #
    # This class relies on a caller to run a select() loop and call
    #
    # - process_timeout to check if a timeout has occurred
    # - process_output when the socket is ready to be written to
    # - process_input when the socket is ready to be read from
    # - process_exception when the socket has an exception
    #
    # Additionally, it relies on the caller to call the following
    # methods at key junctures in the protocol:
    #
    # - resolve_host (optional)
    # - start_connection
    # - send_precompute_checksum (optional)
    # - send_3pc_ref_list
    # - send_ok_query
    # - send_pre_commit_command (or abort_update)
    # - send_commit_command (or abort_update)
    # - release_lock
    # - fail_transaction (to abruptly break off the transaction)
    #
    # Error handling:
    #
    # If any of the above methods (except for fail_transaction)
    # detects an error that causes the transaction to fail, it
    # switches the object to Replica3PCFailedPhase and raises a
    # Replica3PCFailedError. If the caller wants to cause the
    # transaction to fail, it should call fail_transaction.
    class Replica3PCClient
      include Replica3PCPhase::ShortString

      TXN_FIRST_REPLICA_LOCK_TIMEOUT = 8.0
      TXN_OTHER_REPLICA_LOCK_TIMEOUT = 2.0

      # Times the server is asked to wait for the dgit-state lock (can
      # be special-cased by priority), in seconds:
      TXN_FIRST_REPLICA_FLOCK_TIMEOUTS = Hash.new(7.0).update(low: 1.0)
      TXN_OTHER_REPLICA_FLOCK_TIMEOUTS = Hash.new(1.0)

      # What is the index of this client in order of being contacted
      # (e.g., the first replica has index==0, etc)?
      attr_reader :index

      # Our best up-to-date knowledge about the replica's on-disk
      # checksum. This attribute starts out at :unchanged, meaning
      # that we have no independent knowledge of the checksum, but we
      # haven't done anything to change it (i.e., the DB checksum can
      # probably still be trusted). Once the replica has reported the
      # pre-checksum in its "ready" line, that value is stored here.
      # If there is a failure between the time we send "pre-commit"
      # and the time we get the "committed" confirmation from the
      # replica, this attribute is set to :indeterminate. If we
      # receive a "committed" confirmation, this attribute is changed
      # to reflect the post-checksum. Alternately, if we "abort" the
      # transaction and receive the "aborted" confirmation, then this
      # attribute is set back to the pre-checksum.
      attr_accessor :checksum

      # The pre-checksum reported by the replica in its "ready" line,
      # or :indeterminate if we haven't gotten that information yet.
      attr_accessor :pre_checksum

      # Should the checksum be forced to be computed from scratch (as
      # opposed to computed incrementally from the previous value of
      # the checksum when possible)?
      attr_reader :checksum_from_scratch

      # This field indicates the state of HTTP header processing:
      #
      # * `nil` — we haven't read any of the header yet.
      #
      # * `:partial` — we have read the (single) header line and are
      #   waiting for the terminating blank line.
      #
      # * `true` — we have read the whole header and any further input
      #   is part of the 3PC protocol.
      attr_accessor :accepted

      attr_accessor :err

      attr_reader :host
      attr_reader :phase

      # The time we entered the current phase:
      attr_reader :phase_begin

      # The deadline for the next transition, or nil if no deadline is
      # currently active:
      attr_accessor :deadline

      attr_reader :send_buffer

      attr_accessor :refs_status
      attr_reader :socket

      attr_reader :priority

      # Used for the client to access the histories which is used in tests
      attr_reader :history

      def initialize(index, refs_before_after_status, git_commit_time,
                     sockstat, reflog_msg, route, priority,
                     checksum_from_scratch:)
        @index = index
        @refs_before_after_status = refs_before_after_status
        @git_commit_time = git_commit_time
        @sockstat = sockstat
        @reflog_msg = reflog_msg
        @route = route
        @host = @route.original_host || @route.host
        @path = @route.path
        @priority = priority
        @checksum_from_scratch = checksum_from_scratch
        @start_time = Time.now

        @recv_buffer = "".b
        @send_buffer = "".b
        @buffering_output = 0

        @checksum = :unchanged
        @pre_checksum = :indeterminate
        @refs_status = {}

        @history = []

        # These are filled by resolve_host, called either directly by
        # the caller or implicitly as part of start_connection:
        @route_host = nil
        @sockaddr = nil
        @socket = nil

        set_phase(Replica3PCUninitializedPhase.new(self))
      end

      def voting?
        @route.voting?
      end

      # Was the replica healty (according to the database) before any transaction took place?
      def was_healthy?
        @route.healthy
      end

      def resolve_host
        with_error_handler do
          initial_gc_stats = GC.stat
          start = Time.now

          @route_host = @route.resolved_host
          t1 = Time.now
          addrinfo = Addrinfo.getaddrinfo(@route_host,
                                          GitHub.dgit_gitrpcd_port,
                                          Socket::AF_INET,
                                          Socket::SOCK_STREAM).first
          t2 = Time.now
          @sockaddr = addrinfo.to_sockaddr

          finish = Time.now
          ms = ((finish - start) * 1000).round(5)
          if ms > 200
            final_gc_stats = GC.stat
            GitHub.logger.info("slow getaddrinfo",
                               "gh.spokes.fileserver" => @route_host,
                               "gh.timing.elapsed_seconds" => finish - start,
                               "gh.dgit.3pc.resolved_host_ms" => ((t1 - start) * 1000).round(5),
                               "gh.dgit.3pc.getaddrinfo_ms" => ((t2 - t1) * 1000).round(5),
                               "gh.dgit.3pc.to_sockaddr_ms" => ((finish - t2) * 1000).round(5),
                               "gh.dgit.3pc.initial_gc_stats" => initial_gc_stats.inspect,
                               "gh.dgit.3pc.final_gc_stats" => final_gc_stats.inspect)
          end

          @socket = Socket.new(addrinfo.afamily, addrinfo.socktype)
        end
      end

      def start_connection
        set_phase(Replica3PCStartingConnectionPhase.new(self))
        with_error_handler do
          resolve_host if !@sockaddr
          start = Time.now

          begin
            @socket.connect_nonblock(@sockaddr)
            set_phase(Replica3PCConnectedPhase.new(self))
          rescue Errno::EINPROGRESS
            set_phase(Replica3PCConnectingPhase.new(self))
          end

          finish = Time.now
          ms = ((finish - start) * 1000).round(5)
          if ms > 200
            GitHub.logger.info("slow connect_nonblock",
                               "gh.spokes.fileserver" => @route_host,
                               "gh.timing.elapsed_seconds" => finish - start)
          end
        end
      end

      def send_precompute_checksum
        set_phase(Replica3PCWaitingForChecksumPrecomputePhase.new(self))
        send_3pc_line("forget-checksum --precompute")
      end

      def self.flock_timeout(replica_index, priority)
        if replica_index == 0
          TXN_FIRST_REPLICA_FLOCK_TIMEOUTS[priority]
        else
          TXN_OTHER_REPLICA_FLOCK_TIMEOUTS[priority]
        end
      end

      def self.lock_timeout(replica_index)
        if replica_index == 0
          TXN_FIRST_REPLICA_LOCK_TIMEOUT
        else
          TXN_OTHER_REPLICA_LOCK_TIMEOUT
        end
      end

      # If this connection currently has an active deadline, return
      # the length of time remaining, or a negative value if the
      # deadline has already expired. If no deadline is active,
      # return nil.
      def time_remaining
        @deadline && @deadline - Time.now
      end

      def countdown_expired?
        @deadline && Time.now > @deadline
      end

      def elapsed_ms
        @phase_begin && (Time.now - @phase_begin) * 1000
      end

      def set_phase(new_phase)
        if @phase
          t = elapsed_ms.round
          log_event "phase transition: #{@phase} -> #{new_phase} after #{t}ms"
        end

        old_phase = @phase
        @phase = new_phase
        @phase_begin = Time.now
        @phase.enter_phase(old_phase)
      end

      def in_phase?(phase_class)
        @phase.is_a?(phase_class)
      end

      def write_pending?
        @phase.write_pending?
      end

      def want_to_read?
        @phase.want_to_read?
      end

      def want_to_write?
        @phase.want_to_write?
      end

      # Do we hold the dgit-state lock?
      def locked?
        @phase.locked?
      end

      # Is this phase abortable?
      def abortable?
        @phase.abortable?
      end

      def eligible_to_vote?
        @phase.eligible_to_vote?
      end

      # Has the success/failure of this transaction been decided?
      def decided?
        @phase.decided?
      end

      # Has this transaction definitely failed?
      def failed?
        @phase.failed?
      end

      # Did we send an ok with the refs list?
      def streamlined_ok?
        @streamlined_ok
      end

      # Did we send an unlock with the commit command?
      def streamlined_unlock?
        @streamlined_unlock
      end

      # Run the provided block within an error handler that handles
      # common network problems. If a problem causes this transaction
      # to fail, call @phase.bail_out, which raises a
      # Replica3PCFailedError.
      def with_error_handler
        yield
      rescue SocketError,
             Errno::ECONNREFUSED, Errno::ENETUNREACH, Errno::ENETDOWN,
             Errno::EHOSTUNREACH, Errno::ETIMEDOUT => e
        @phase.bail_out(e.message)
      rescue EOFError, Errno::EPIPE, Errno::ECONNRESET => e
        @phase.handle_eof(e.message)
      rescue IOError => e
        if e.message == "closed stream"
          @phase.handle_eof(e.message)
        else
          @phase.bail_out("#{@cn} failed due to IOError: #{e.message}")
        end
      rescue => e # rubocop:todo Lint/RescueException
        GitHub::DGit::threepc_debug "Exception occurred: #{e.inspect}"
        GitHub::DGit::threepc_debug "Backtrace: #{e.backtrace.inspect}"
        raise
      end

      # Run a code block while buffering any send_3pc_line
      # output in @send_buffer, then drain it all at once.
      def with_output_buffering
        # Keep track of how many times this call is nested:
        @buffering_output += 1
        begin
          yield
        ensure
          @buffering_output -= 1
        end
        drain_3pc_msg
      end

      def send_3pc_data(msg)
        msg = msg.b
        log_event "sending data #{short_string(msg)}"
        @send_buffer << msg
        drain_3pc_msg
      end

      def send_3pc_line(msg)
        msg = msg.b
        log_event "sending line #{short_string(msg)}"
        if msg.include?("\n")
          raise GitHub::DGit::ThreepcError, "protocol line includes LF"
        end
        @send_buffer << msg << "\n"
        drain_3pc_msg
      end

      def drain_3pc_msg
        return if @buffering_output > 0
        return unless write_pending?
        with_error_handler do
          sent = @socket.write_nonblock(@send_buffer)
          log_event "transmitted #{sent} bytes"
          @send_buffer = @send_buffer[sent..-1]
        end
      end

      # If input is ready, read some and append it to recv_buffer.
      def read_into_buffer
        begin
          buf = @socket.read_nonblock(65535)
        rescue IO::EAGAINWaitReadable
          return false
        end

        if buf
          log_event "received #{short_string(buf)}"
          @recv_buffer << buf
          true
        else
          log_event "received zero bytes"
          false
        end
      end

      # If `@recv_buffer` contains a full LF-terminated line, remove
      # and return it (with the LF stripped off). Otherwise, return
      # `nil`.
      def recv_3pc_line
        i = @recv_buffer.index("\n")
        return nil unless i

        next_line = @recv_buffer[0...i]
        log_event "read line #{short_string(next_line)}"
        @recv_buffer = @recv_buffer[(i + 1)..-1]
        next_line
      end

      def send_3pc_ref_list(have_quorum: false)
        send_3pc_ref_list_commands(send_ok: have_quorum)
      end

      def send_3pc_ref_list_commands(send_ok: false)
        @streamlined_ok = send_ok
        with_output_buffering do
          send_3pc_line("ref-update-begin")
          @refs_before_after_status.each do |refname, before, after, status|
            if before && after
              if before == after
                send_3pc_line("verify #{refname} #{before}")
              else
                if before != GitHub::NULL_OID &&
                    after != GitHub::NULL_OID &&
                    (status == "ff" || status == "nf")
                  send_3pc_line("option ff=#{(status == "ff") ? "true" : "false"}")
                end
                send_3pc_line("update #{refname} #{after} #{before}")
              end
            elsif after
              send_3pc_line("update #{refname} #{after}")
            elsif before
              send_3pc_line("verify #{refname} #{before}")
            end
          end
          send_3pc_line("ref-update-end")

          timeout = self.class.flock_timeout(index, priority)
          with_output_buffering do
            send_3pc_line("lock --fast #{(timeout / 0.001).ceil}")
            send_3pc_line("get-checksum")
            send_3pc_line("ok? version=#{DGit::DGIT_CURRENT_CHECKSUM_VERSION}") if send_ok
          end
        end
        set_phase(Replica3PCWaitingForLockPhase.new(self))
      end

      CONNECT_STR = <<~EOM.freeze
        CONNECT %s HTTP/1.1\r
        Host: %s\r
        X-Git-Path: %s\r
        X-Stat: %s\r
        X-GitHub-Request-ID: %s\r
        \r
      EOM

      # Tell the remote side to spawn dgit-update via gitrpcd.
      def spawn_dgit_update
        # In production, gitrpcd has its base path set to
        # /data/repositories, so we need to strip it here:
        path = @path.gsub(/\A\/data\/repositories/, "").b

        # We run this via gitrpcd's pseudo HTTP proxy tunnel.
        stat = String.new
        @sockstat.each do |key, value|
          stat << "#{key}=#{GitHub::GitSockstat.url_escape(GitHub::GitSockstat.encode(value, key: key).to_s)}; "
        end
        req = CONNECT_STR % ["dgit-update:80".freeze, @route_host, path, stat, @sockstat["request_id"]]
        @send_buffer << req
      end

      def send_initial_commands
        with_output_buffering do
          spawn_dgit_update
          send_3pc_line("committer-name #{@sockstat[:committer_name] || "gitauth"}")
          send_3pc_line("committer-email #{@sockstat[:committer_email] || "gitauth@localhost"}")
          send_3pc_line("committer-date #{@git_commit_time}")
          send_3pc_line("reflog-msg #{@reflog_msg}")
        end
      end

      # A connection was unsuccessfully attempted once, but now the
      # socket is ready for writing so it should be possible to
      # connect now.
      def finish_connecting
        begin
          @socket.connect_nonblock(@sockaddr)
        rescue Errno::EISCONN
          # pass
        end
        set_phase(Replica3PCConnectedPhase.new(self))
      end

      def fail_transaction(msg)
        @phase.bail_out(msg)
      rescue Replica3PCFailedError
        # This is an expected side-effect of calling bail_out; ignore it.
      end

      def send_ok_query(checksum)
        unless in_phase?(Replica3PCCanCommitQueryPhase)
          raise GitHub::DGit::ThreepcError,
                "#{__method__} called in phase #{@phase}"
        end
        query = "ok? version=#{DGit::DGIT_CURRENT_CHECKSUM_VERSION}"
        query << " #{checksum}" if checksum
        send_3pc_line(query)
        set_phase(Replica3PCWaitingForOkPhase.new(self))
      end

      def maybe_send_pre_commit_command(consensus_checksum)
        if [:indeterminate, :unchanged].include?(checksum)
          send_pre_commit_command
        elsif consensus_checksum && checksum && consensus_checksum != checksum
          abort_update("checksum mismatch")
        else
          send_pre_commit_command
        end
      end

      def send_pre_commit_command
        unless in_phase?(Replica3PCReadyForPreCommitPhase)
          raise GitHub::DGit::ThreepcError,
                "#{__method__} called in phase #{@phase}"
        end
        send_3pc_line("pre-commit")
        set_phase(Replica3PCWaitingForAckPhase.new(self))
      end

      def send_commit_command
        do_commit(unlock: !voting?)
      end

      def do_commit(unlock: false)
        unless in_phase?(Replica3PCReadyForCommitPhase)
          raise GitHub::DGit::ThreepcError,
                "#{__method__} called in phase #{@phase}"
        end
        @checksum = :indeterminate
        @streamlined_unlock = unlock
        log_event "committing and releasing lock" if unlock
        with_output_buffering do
          send_3pc_line("commit")
          send_3pc_line("unlock") if unlock
        end
        set_phase(Replica3PCCommittingPhase.new(self))
      end

      def abort_update(msg)
        @phase.abort_update(msg)
      end

      def release_lock
        @phase.release_lock
      end

      def process_output
        with_error_handler do
          @phase.handle_output
        end
      end

      def process_input
        with_error_handler do
          read_into_buffer
          # Note: this might theoretically be a different @phase each
          # time through the loop.
          while @phase.handle_input
          end
        end
      end

      def process_exception
        log_event "exception on socket"
        @phase.handle_exception
      end

      # If this connection has timed out, clean up.
      def process_timeout
        return unless countdown_expired?

        GitHub::DGit::threepc_debug "#{inspect} timed out"
        log_event "timeout"
        begin
          @phase.handle_timeout
        rescue Replica3PCFailedError
          # This is a possible side-effect of calling
          # handle_timeout; ignore it.
        end
      end

      def shorthost
        if GitHub.enterprise?
          @host
        else
          @host.sub(/\Agithub-(dfs-?[0-9a-f]+).*/, '\1')
        end
      end

      def log_event(event)
        t = ((Time.now - @start_time) * 1000).round
        event = event.inspect if !event.is_a?(String)
        @history << "#{t}ms: #{event}"
      end

      # Note that the output of this method might include sensitive
      # information. It should not be included in exceptions!
      def inspect
        attributes = [
          "#{shorthost}:#{@path}",
          "voting=#{voting?}",
          "start=#{@start_time.utc.iso8601(3)}",
          "phase=#{@phase}",
          "pre_checksum=#{@pre_checksum}",
          "checksum=#{@checksum}",
        ]
        if @phase_begin
          attributes << "time_in_phase=#{elapsed_ms.round}ms"
        end
        if @deadline
          attributes << "time_remaining=#{(time_remaining * 1000).round}ms"
        end
        if @err
          attributes << "err=#{@err.inspect}"
        end
        attributes.concat [
          "refs_status=#{@refs_status}",
        ]
        attributes << "history=#{@history.inspect}"
        "#<Replica3PCClient #{attributes.join(", ")}>"
      end

      # Return a hash of values for logging.
      def log_state
        sh = shorthost
        state = {
          "#{sh}_phase"    => @phase,
          "#{sh}_checksum" => @checksum,
        }

        state.update("#{sh}_err" => @err) if @err

        state
      end
    end
  end
end
