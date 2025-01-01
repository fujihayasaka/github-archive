# typed: true
# frozen_string_literal: true

module GitAuth
  class Pipeline
    class Result
      attr_accessor :member, :ssh_ca, :public_key, :token, :credential
      attr_writer :user
      attr_reader :status, :input
      def initialize(input)
        @input      = input
        @member     = input.member
        @status     = :inconclusive
        @credential = nil
      end

      def user
        @user || look_up_user
      end

      def look_up_user
        return if member.is_a?(Symbol) # don't try looking up for slumlord or anonymous
        return if member.include?(":") # don't try looking up if member indicates custom auth types
        return unless GitHub::UTF8.valid_unicode3?(member)
        User.find_by(login: member)
      end

      def failed?
        ![:ok, :inconclusive].include?(status)
      end

      def succeeded?
        status == :ok
      end

      def inconclusive?
        status == :inconclusive
      end

      def fail_with(status)
        @status = status
      end

      def success!
        @status = :ok
      end

      # filter_sensitive_data - log member without identifying information (username, repo name)
      def full_member(filter_sensitive_data: false)
        # This deals with the various cases where we have a user and the
        # existing member data can be in various forms.
        return "user:#{user.id}#{filter_sensitive_data ? nil : ':' + user.display_login}" if user

        case member
        when nil, :anonymous
          "anonymous"
        when :slumlord
          # Let's not use the legacy name.
          "svnbridge"
        when /\A(?:user|repo):\d+:.*\z/
          # if filter is true, we don't want to include the display_login or name with owner
          filter_sensitive_data ? member.split(":")[0..1].join(":") : member
        when /\Agitauth-full-trust:(.*)\z/
          "full-trust:gitauth:#{$1}"
        else
          "unknown"
        end
      end

      # Filter member logs the same information as full_member,
      # but with user identifiable information removed, specifically username and repository names.
      # Instead, we only log the ids
      def filtered_member
        full_member(filter_sensitive_data: true)
      end
    end
  end
end
