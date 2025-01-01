# typed: true
# frozen_string_literal: true

module GitAuth
  class Pipeline
    class Input
      attr_reader :protocol, :action, :member, :password, :key, :repository, :target_path, :ip, :original_user_agent, :request_id, :sigtype, :request_access_security_header
      def initialize(protocol:, action:, member:, password:, key:, target:, ip:, original_user_agent:, request_id:, sigtype:, request_access_security_header:)
        @protocol   = protocol
        @action     = action
        @member     = member
        @password   = password
        @key        = key
        @repository = target.repository
        @ip         = ip
        @sigtype    = sigtype
        @request_access_security_header = request_access_security_header

        # For logging purposes only
        @target_path = target.path
        @original_user_agent = original_user_agent
        @request_id  = request_id
      end

      def base_sigtype
        return @base_sigtype if defined?(@base_sigtype)
        @base_sigtype = sigtype&.sub(/-cert-v01@openssh.com\z/, "")
      end
    end
  end
end
