# typed: true
# frozen_string_literal: true

module GitHub
  class DGit
    class Error < StandardError
      attr :failbot_context

      def initialize(*args)
        super
        @failbot_context = {}
      end
    end

    # Including this module will cause failbot to redact the potentially
    # sensitive exception message.
    module NeedsRedacting
      def needs_redacting?
        true
      end
    end

    class UnroutedError < Error; end

    class NotFoundError < UnroutedError
    end

    class InsufficientQuorumError < Error; end
    class HostSelectionError < Error; end
    class ThreepcError < Error; end
    class ThreepcInternalError < Error; end
    class ThreepcFailedToLock < Error; end

    class ThreepcBusyError < ThreepcFailedToLock
      def commit_refs_reason
        "too-busy"
      end
    end

    class CommandError < Error
      include NeedsRedacting
    end

    class ReplicaRepairError < Error; end
    class ReplicaRepairFatalError < Error; end
    class ReplicaSyncError < Error; end

    class ReplicaDestroyError < Error
      include NeedsRedacting
    end

    class ReplicaDestroyNotFoundError < Error; end
    class ReplicaCreateError < Error; end
    class ReplicaCreateAlreadyPresentError < Error; end
    class ReplicaMoveError < Error; end

    class ChecksumInitError < Error
      include NeedsRedacting
    end

    class RepoNotFound < Error; end
    class NetworkNotFound < Error; end

    class ZeroReplicaNetworks < Error; end
    class ZeroReplicaGists < Error; end

    class ColdStateUnchangedError < Error; end

    class LoadAvgHigh < Error; end

    class NoVotingReplicas < Error; end
  end
end
