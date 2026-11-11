# typed: strict
# frozen_string_literal: true

module PullRequests
  module GitSystems
    module RefSpecs
      # Merge Queue private refspec: `refs/gh/queue/main-23-*`
      MERGE_QUEUE = %r{\A#{MergeQueue::READ_ONLY_REF_PREFIX.delete_suffix('/')}(/|\z)}

      # PRs specific refspec: `refs/pull/1/head`
      PULL = %r{\Arefs/pull(/|\z)}

      # GitHub global refspec, used by PRs: `refs/__gh__/pull/1/heads`
      PRIVATE = %r{\Arefs/__gh__(/|\z)}

      # Internal refspecs that are "owned" by GitHub.
      INTERNAL = T.let([MERGE_QUEUE, PULL, PRIVATE], T::Array[Regexp])
    end

    # Attempt to encapsulate all the potential errors raised from our systems calls in to
    # a subset of errors. Due to the large combination of both classes and error messages,
    # this method attempts to pattern match on the known error paths.
    #
    # Optional `repository:` is retained for caller compatibility.
    sig { params(exception: Exception, repository: T.nilable(Repository)).returns(T.nilable(Errors)) }
    def self.classify_exception(exception, repository: nil)
      classify_exception_brackets(exception)
    end

    # Bracketed implementation. Each arm MUST be written in `[Class, /regex/]`
    # (or `[Class, _]`) form, with `|` alternations between bracketed shapes.
    # The unbracketed multi-positional form
    #
    #     in A, /one/ | B | C, /two/
    #
    # is parsed by Ruby as a single array pattern (`[A, /one/|B|C, /two/]`),
    # not as three alternative `[Class, Message]` shapes against the
    # `[exception, exception.message]` scrutinee, which silently makes every
    # arm after the first dead code. See
    # packages/pull_requests/test/lib/pull_requests/git_systems_test.rb.
    sig { params(exception: Exception).returns(T.nilable(Errors)) }
    private_class_method def self.classify_exception_brackets(exception)
      case [exception, exception.message]

      # Fatal - errors are considered never retryable or recoverable.
      in [GitRPC::Error, /request is too large/] |
         [GitRPC::RequestTooLarge, _] |
         [GpgVerify::RevokedKeyError, _]
        Errors::Fatal.new(exception:)

      # NOTE: The unbracketed `A, B | C, D` syntax is parsed in a way that
      # does not match real input — new patterns here should use bracketed
      # `[Class, /regex/]` or `[Class, _]` forms.
      in [GitRPC::Failure, /NUL byte in commit log message/]
        Errors::Fatal.new(exception:)

      # Outages - hints to let us know there may be an issue with git with a particular repo
      # or the service as a whole.
      in [GitRPC::Protocol::DGit::ResponseError, /backends disagreed/i]
        Errors::Outage.new(reason: Errors::Outage::Reason::BackendsDisagree, exception:)

      in [GitRPC::Protocol::DGit::ResponseError, /insufficient quorum/i] |
         [GitHub::DGit::UnroutedError, /no available servers/] |
         [GitHub::DGit::InsufficientQuorumError, _]
        Errors::Outage.new(reason: Errors::Outage::Reason::UnavailableServers, exception:)

      in [GitHub::DGit::ThreepcBusyError, _] |
         [GitHub::DGit::ThreepcError, _] |
         [GitHub::DGit::ThreepcFailedToLock, _]
        Errors::Outage.new(reason: Errors::Outage::Reason::ThreePhaseCommit, exception:)

      in [GitHub::DGit::UnroutedError, /network not found/]
        Errors::Outage.new(reason: Errors::Outage::Reason::RepositoryNetwork, exception:)

      in [SpokesAPI::ResourceExhausted, _] |
         [GitRPC::CommandBusy, _]
        Errors::Outage.new(reason: Errors::Outage::Reason::RateLimited, exception:)

      in [Git::Ref::UpdateFailedSensitive, /cannot lock ref/i] |
         [Git::Ref::UpdateFailedSensitive, /failed to update ref/i]
        Errors::Outage.new(reason: Errors::Outage::Reason::RefContention, exception:)

      in [GitRPC::Error, /contain a valid header/i] |
         [GitRPC::Error, /does not match header/i]
        Errors::Outage.new(reason: Errors::Outage::Reason::MalformedResponse, exception:)

      # Timeouts - similar to outages, but a specific type of outage.
      in [OpenSSL::SSL::SSLErrorWaitReadable, _] |
         [Faraday::TimeoutError, _] |
         [SpokesAPI::TwirpServerError, _] |
         [GitHub::Spokes::ClientError, /invalid connection/] |
         [GitHub::Spokes::ClientError, /no such host/] |
         [GitRPC::Timeout, _] |
         [GitRPC::ConnectionError, _] |
         [GitRPC::Failure, /failure in name resolution/i] |
         [GitRPC::Failure, /AbortError/i]
        Errors::Timeout.new(exception:)
      else
        nil
      end
    end
  end
end
