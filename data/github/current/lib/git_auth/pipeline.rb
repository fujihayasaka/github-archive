# typed: true
# frozen_string_literal: true

require "forwardable"

module GitAuth
  # Try one authentication method after the other, until we reach a conclusion.
  # The conclusion could be:
  # - success => authentication succeeded, proceed with authorization.
  # - failure => authentication failed, bail.
  class Pipeline
    autoload :Auth, "git_auth/pipeline/auth"
    autoload :AuthenticationMethod, "git_auth/pipeline/authentication_method"
    autoload :Input, "git_auth/pipeline/input"
    autoload :Result, "git_auth/pipeline/result"

    extend Forwardable
    include GitHub::Tracing

    # To add new authentication methods, implement a new class that
    # inherits from GitAuth::Pipeline::AuthenticationMethod,
    # overriding :applicable? and :process.
    # Then add it to this array.
    #
    # Each authentication method is attempted in turn.
    # It will only process that method if there is not yet
    # a conclusion and that method is deemed applicable.
    METHODS = [
      Auth::Anonymous,
      Auth::Slumlord,
      Auth::SignedToken,
      Auth::SSHCertificate,
      Auth::SSHKey,
      Auth::TempCloneToken,
      # This one needs to come last otherwise passwords that look
      # like temp clone tokens or signed tokens may be blocked
      # as we soon won't allow password auth to git
      # see https://github.com/github/github/pull/142856 for more info
      Auth::RequestCredentials,
    ]

    delegate [
      :member, :ssh_ca, :public_key, :token, :user, :status,
      :failed?, :succeeded?, :inconclusive?
    ] => :result

    attr_reader :input
    def initialize(protocol:, action:, member:, password:, key:, target:, ip:, original_user_agent:, request_id:, sigtype:, request_access_security_header:)
      @input = Input.new(
        protocol: protocol,
        action: action,
        member: member,
        password: password,
        key: key,
        target: target,
        ip: ip,
        original_user_agent: original_user_agent,
        request_id: request_id,
        sigtype: sigtype,
        request_access_security_header: request_access_security_header,
      )
    end

    def process
      GitAuth::Metrics.time("pipeline.process") do
        METHODS.each do |method|
          @result = method.new(input: input).result
          return result unless result.inconclusive?
        end

        # If we're still here then it means that we
        # didn't get a conclusive result in the pipeline.
        # We need to fail closed.
        result.fail_with :auth_error
        result
      end
    end
    trace_method :process

    def protocol
      input.protocol
    end

    def action
      input.action
    end

    def ip
      input.ip
    end

    def request_access_security_header
      input.request_access_security_header
    end

    private

    def result
      @result ||= Result.new(input)
    end
  end
end
