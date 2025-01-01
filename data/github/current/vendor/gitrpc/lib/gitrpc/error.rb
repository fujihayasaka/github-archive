# rubocop:disable Style/FrozenStringLiteralComment

module GitRPC
  # Base class for all GitRPC exceptions.
  class Error < StandardError
    attr_reader :original

    # Create a GitRPC::Error with the given message and optional reference to
    # exception that caused the error.
    #
    # message  - String error message
    # original - The exception that led to this error.
    #
    def initialize(message = nil, original = nil)
      message, original = nil, message if message.kind_of?(Exception)
      message ||= original.message if original
      @original = original
      super(message)
    end

    def needs_redacting?
      true
    end
  end

  # Raised when GitMon has killed a Git process because of lack of resources
  class CommandBusy < Error
  end

  # A command failed to complete within the designated amount of time.
  class Timeout < Error
    attr_reader :cached
    attr_reader :argv
    alias cached? cached

    def initialize(message = nil, original = nil, cached: false, argv: nil)
      @cached = cached
      @argv = argv
      super(message, original)
    end

    def failbot_context
      { :cached => @cached, :argv => @argv }
    end
  end

  # BERT encoded request was too large.
  class RequestTooLarge < Error
    attr_reader :request_size
    attr_writer :gitrpc_name

    def initialize(request_size)
      @request_size = request_size
      super("BERT request too large")
    end

    def failbot_context
      {
        "gh.gitrpc.bert.encode_size" => @request_size,
        "gh.gitrpc.name" => @gitrpc_name
      }
    end
  end

  # The command generated too much data on stdout and was halted.
  class MaximumOutputExceeded < Error
  end

  # Raised from GitRPC.new and GitRPC.resolve when no Protocol implementation
  # exists for the requested URL's protocol scheme. The message consists of the
  # scheme name only.
  class NoSuchProtocol < Error
    def initialize(scheme)
      super
    end
  end

  # A connection could not be established for a remote repository. This is
  # usually due to a service not accepting connections on the port.
  class ConnectionError < Error
  end

  # Some kind of network problem (read error, write error, malformed data, etc)
  # caused the client to abort a command.
  class NetworkError < Error
  end

  class NoDataError < Error
  end

  # Exception raised when a git command fails, for commands whose output
  # is parsed within GitRPC.
  class CommandFailed < Error
    attr_reader :out, :err, :argv, :stat

    def initialize(res)
      @out  = res["out"].to_s.empty? ? nil : res["out"].b
      @err  = res["err"].to_s.empty? ? nil : res["err"].b
      @argv = res["argv"].map { |s| s.b }
      @stat = res["status"].to_s.b
      super [@argv.join(" "), @out, @err, "[exit: #{@stat}]".b].compact.join(", ").dump
    end
  end

  # An attempt was made to access a repository that is offline.
  class RepositoryOffline < Error
    def initialize(host, path)
      @host = host
      @path = path
      super "#{host}:#{path} is offline"
    end
  end

  # A system error occurred. This typically include an original exception from
  # the Errno:: hierarchy, such as Errno::ENOENT.
  class SystemError < Error
    attr_accessor :errno

    def failbot_context
      { :errno => original&.errno }
    end
  end

  # Raised when a call's request arguments or response data includes an object
  # type that cannot be serialized.
  class EncodingError < Error
  end

  # An attempt was made to operate on a repository that does not exist or is
  # not a git repository. Backend call implementations must translate lower
  # level exceptions that indicate this state into an exception of this type.
  class InvalidRepository < Error
  end

  class DGitStateInitError < Error
  end

  class EmptyDGitState < InvalidRepository
    def initialize
      super "dgit-state file is empty"
    end
  end

  # An attempt was made to operate on a dgit repository with dgit disabled.
  class DGitRequired < Error
  end

  # An attempt was made to read or write a file outside of the git repository.
  class IllegalPath < Error
    def initalize(path, access = "access")
      super "#{access} attempt on #{path}"
    end
  end

  # An object could not be loaded from the object store either because it simply
  # doesn't exist or possibly because there was a system error that prevented
  # the object from being retrieved. A corrupt pack or object file for instance.
  #
  # The error message MUST include the bad 40 char oid value requested. The
  # message may include additional diagnostic information but the oid must be
  # present.
  class ObjectMissing < Error
    attr_reader :oid

    def initialize(message = nil, oid = nil)
      @oid = oid
      super message
    end
  end

  # Raised when an invalid object or valid object of an un-expected type is found.
  class InvalidObject < Error
  end

  # Raised when a ref update fails.
  class RefUpdateError < Error
  end

  # An attempt was made to operate on a repository that exists and is a git
  # repository but is in a bad state. More granular subclasses will be raised
  # if possible.
  class BadRepositoryState < Error
  end

  # An attempt was made to access an object that exists but is in a bad state
  # (for example, a commit with a malformed timestamp).
  class BadObjectState < BadRepositoryState
  end

  # Raised when you try to blame a line range that doesn't exist for the path
  class BadLineRange < Error
  end

  # Raised when you try to lookup a path that does not exist in the tree
  class NoSuchPath < Error
  end

  # Raised when an object other than a short or full oid is passed
  class InvalidOid < Error
  end

  # Raised when an object other than a full 40-character oid is passed
  class InvalidFullOid < Error
  end

  # Raised when an unrecognized diff algorithm is requested for diff stats
  class InvalidDiffAlgorithm < Error
  end

  # Raised when an invalid reference name is passed.
  class InvalidReferenceName < Error
  end

  # Raised when an invalid commitish is passed.
  class InvalidCommitish < Error
  end

  # Raised when an argument that is considered unsanitary is passed.
  class UnsafeArgument < Error
  end

  # Raised when a bad revision is requested.
  class BadRevision < Error
  end

  # Raised when a gitmodules file is suspicious
  class BadGitmodules < Error
  end

  # Raised when a .gitattributes file is suspicious
  class BadGitattributes < Error
  end

  # Raised when a .gitmodules, .gitignore or .gitattributes is a symlink
  class SymlinkDisallowed < Error
  end

  # Raised when a .git-blame-ignore-revs file is invalid (ex: contains an invalid commit OID)
  class InvalidIgnoreRevs < Error
  end

  # Raised when a .git-blame-ignore-revs file is too large
  class IgnoreRevsTooBig < Error
  end
end
