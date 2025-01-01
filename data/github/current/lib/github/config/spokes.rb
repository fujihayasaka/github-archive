# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Spokes
      # A list of datacenters that can be used when placing new repository replicas.
      #
      # If this is not set, all datacenters are acceptable for placement.
      attr_reader :spokes_voting_datacenters
      def spokes_voting_datacenters=(val)
        @spokes_voting_datacenters =
          case val
          when "", []
            nil
          when String
            val.split(",")
          else
            val
          end
      end

      # Whether 'spokes_receive' should be set in sockstat for Git client
      # traffic. When this is true, babeld will connect to githttpdaemon (in
      # the gitrpcd container) instead of git-daemon. It's called
      # "spokes_receive" because the main goal here is to let us run
      # "spokes-receive-pack" in place of "git-receive-pack" during a push.
      #
      # This is only enabled for dotcom and Proxima until
      # https://github.com/github/git-access/issues/65 is complete.
      def spokes_receive?
        GitHub.spokesd_enabled? && !git_receive_fallback_enabled?
      end

      # In DotCom pushes have been flowing through our custom receive-pack
      # implementation (spokes-receive-pack) for a while. Now we are ready to ship
      # it to GHES. This config option exists to allow us to fallback to the
      # traditional push mechanism in case something goes wrong in an enterprise setup
      #
      # If needed, GHES admins can bring back the fallback code by running this:
      #   ghe-config app.github.git-receive-fallback-enabled true
      attr_writer :git_receive_fallback_enabled
      def git_receive_fallback_enabled?
        @git_receive_fallback_enabled
      end

      # The pre-receive hook is now executed more directly instead of going
      # through the "in"-repository shell script.
      #
      # If needed, GHES admins can bring back the fallback code by running this:
      #   ghe-config app.github.pre-receive-fallback-enabled true
      attr_writer :pre_receive_fallback_enabled
      def pre_receive_fallback_enabled?
        !!@pre_receive_fallback_enabled
      end
    end
  end

  extend Config::Spokes
end
