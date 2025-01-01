# typed: false
# frozen_string_literal: true

require "chatops-controller"
require "github_chatops_extensions"
require "github_chatops_extensions/checks"

module Chatops
  class SpokesController < ApplicationController
    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    class SpokesProcessError < StandardError
    end

    class SpokesScriptRunner
      def run(cmd, *args)
        script = File.join(Rails.root, "bin", cmd)
        raise "Attempted to run a script that doesn't exist on disk: #{script}" unless File.exist?(script)

        process = Progeny::Command.new(script, *args)

        if !process.status.success?
          "Script failed (#{process.status.inspect}):\n#{process.err}".chomp
        else
          process.out.chomp
        end
      end
    end

    ALLOWED_ROOMS = ["#git-systems-ops", "#git-systems-alerts", "#git-systems", "#incident-command"].freeze
    CHATOPS_GROUP = ["apps/chatops/github-spokes"].freeze

    include ::Chatops::Controller
    include ::GitHubChatopsExtensions::Checks::Includable::Fido
    include ::GitHubChatopsExtensions::Checks::Includable::Entitlements
    include ::GitHubChatopsExtensions::Checks::Includable::Room

    GIT_CONTROLLED_ACTIONS = [
      :diagnose,
      :"find-on-replicas",
      :resolve,
      :server,
      :"set_read_replica-weights",
      :unresolve,
    ].freeze

    PARTNER_ENABLED_ACTIONS = [
      :"set_read_replica",
    ].freeze

    CONTROLLED_ACTIONS = (GIT_CONTROLLED_ACTIONS + PARTNER_ENABLED_ACTIONS).freeze

    before_action -> { require_in_room(ALLOWED_ROOMS) }, only: CONTROLLED_ACTIONS
    before_action :require_fido_2fa, only: CONTROLLED_ACTIONS
    before_action -> { require_ldap_entitlement(CHATOPS_GROUP) }, only: CONTROLLED_ACTIONS

    # staff only endpoint
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
    skip_before_action :verify_authenticity_token


    chatops_namespace :spokes
    chatops_help "Manage repos and replicas in the Spokes cluster."
    chatops_error_response "More information is available in the [Sentry](https://sentry.io/organizations/github/issues/)."

    chatop :diagnose,
           /diagnose(?:(?:\s+(?<verbose>-v))|(?:\s+(?<nwo>\S+)))*\s*/,
           "diagnose <nwo> [--verbose]" do

      proc_params = jsonrpc_params.permit(:nwo, :verbose, :help, :message_id)
      proc_args = [proc_params[:nwo]]

      if ["true", "-v"].include? proc_params[:verbose]
        proc_args << "-v"
      end

      if maybe_help(:diagnose, proc_params, proc_args)
        return
      end

      chatop_send spokes_run("dgit-diagnose", *proc_args)
    end

    chatop :"find-on-replicas",
           /find-on-replicas\s*(?<hosts>\S+(?:\s+\S+)*)?\s*?/,
           "find-on-replicas host [host2 [host3 [...]]] [--gist]" do

      proc_params = jsonrpc_params.permit(:hosts, :gist, :help, :message_id)
      proc_args = []

      if proc_params[:hosts].present?
        proc_params[:hosts].split(" ").each { |h| proc_args << h }
      end

      if proc_params[:gist] == "true"
        proc_args << "--gist"
      end

      if maybe_help(:"find-on-replicas", proc_params, proc_args)
        return
      end

      chatop_send spokes_run("dgit-find-on-replicas", *proc_args)
    end

    chatop :help, /help/, "help" do
      chatop_send HELP_STRINGS[:help]
    end

    chatop :repair,
           /repair\s*(?<nwo>\S+)?\s*?/,
            "repair <nwo> [--quiet]" do

      chatop_send "`.spokes repair` is deprecated.  Try `.spokesctl repair`."
    end

    chatop :resolve,
            /resolve\s*(?<dfs_node>\S+)?\s*?/,
             "resolve <dfs_node>" do

      proc_params = jsonrpc_params.permit(:dfs_node, :help, :message_id)
      proc_args = proc_params.values.compact

      if maybe_help(:resolve, proc_params, proc_args)
        return
      end

      chatop_send spokes_run("dgit-server", "resolve", *proc_args)
    end

    chatop :route,
           /(dat|route)((?:(?:\s+(?<verbose>-v))|(?:\s+(?<json>-j))|(?:\s+(?<nwo>\S+)))+)?\s*/,
           "dat/route <nwo> [--verbose]" do

      chatop_send "`.spokes dat` is deprecated.  Try `.spokesctl dat`."
    end

    chatop :server,
           /server\s*(?<cmd>\S+)?\s*(?<host>\S+)?\s*(?<reason>.*)/,
           "server <cmd> <host> reason" do

      proc_params = jsonrpc_params.permit(:cmd, :host, :reason, :json, :help, :message_id)
      proc_params.delete_if { |_k, v| v.blank? }
      proc_args = proc_params.except(:json).values

      if proc_params.delete(:json) == "true"
        proc_args << "--json"
      end

      if maybe_help(:server, proc_params, proc_args)
        return
      end

      chatop_send spokes_run("dgit-server", *proc_args)
    end

    chatop :"set_read_replica",
           /set-read-replica\s*(?<nwo>\S+)?\s*(?<dfs_node>\S+)?/,
           "set-read-replica <nwo> <host>" do

      proc_params = jsonrpc_params.permit(:nwo, :dfs_node, :help, :message_id)
      proc_args = proc_params.values.compact
      if maybe_help(:"set_read_replica", proc_params, proc_args)
        return
      end

      chatop_send spokes_run("dgit-set-read-replica", *proc_args)
    end

    # This command doesn't need --help handling because the above command will
    # match any of the help options
    chatop :"set_read_replica-weights",
           /set-read-replica\s+(?<nwo>\S+)\s*(?<dfs_nodes_weight>\S+(?:\s+\S+)*)/,
           "set-read-replica <nwo> <dfs_node>=X <dfs_node>=Y <dfs_node>=Z" do

      proc_params = jsonrpc_params.permit(:nwo, :dfs_nodes_weight, :message_id)
      proc_args = [proc_params[:nwo]]

      if proc_params[:dfs_nodes_weight].present?
        proc_params[:dfs_nodes_weight].split(" ").each { |h| proc_args << h }
      end

      chatop_send spokes_run("dgit-set-read-replica", *proc_args)
    end

    chatop :unresolve,
            /unresolve\s*(?<dfs_node>\S+)?/,
            "unresolve <dfs_node>" do

      proc_params = jsonrpc_params.permit(:dfs_node, :help, :message_id)
      proc_args = proc_params.values.compact
      if maybe_help(:unresolve, proc_params, proc_args)
        return
      end

      chatop_send spokes_run("dgit-server", "unresolve", *proc_args)
    end

    chatop :freeze,
          /freeze\s*(?<nwo>\S+)?/,
          "freeze <nwo>" do

      jsonrpc_params.delete(:message_id)
      proc_params = jsonrpc_params.permit(:nwo, :help)
      proc_args = proc_params.values.compact
      if maybe_help(:freeze, proc_params, proc_args)
        return
      end

      chatop_send spokes_run("dgit-cold-network", "freeze", *proc_args)
    end

    chatop :thaw,
          /thaw\s*(?<nwo>\S+)?/,
          "thaw <nwo>" do

      jsonrpc_params.delete(:message_id)
      proc_params = jsonrpc_params.permit(:nwo, :help)
      proc_args = proc_params.values.compact
      if maybe_help(:thaw, proc_params, proc_args)
        return
      end

      chatop_send spokes_run("dgit-cold-network", "thaw", *proc_args)
    end

    chatop :"never-cold",
          /never-cold\s*(?<nwo>\S+)?/,
          "never-cold <nwo>" do

      jsonrpc_params.delete(:message_id)
      proc_params = jsonrpc_params.permit(:nwo, :help)
      proc_args = proc_params.values.compact
      if maybe_help(:"never-cold", proc_params, proc_args)
        return
      end

      chatop_send spokes_run("dgit-cold-network", "never-cold", *proc_args)
    end

    private

    def spokes_run(cmd, *args)
      %Q{```
#{SpokesScriptRunner.new.run(cmd, *args)}
```}
    end

    HELP_STRINGS = {
      diagnose: %q{
Usage:
  .spokes diagnose [-v] <nwo>

Compare DB and on-disk state of all replicas, showing enough information
for you to make an informed decision about which one to bless.
Information shown: replica state, replica online, expected checksum,
replica checksum in database, replica checksum on disk, all hard-state
files, all refs, the most recent timestamp in the audit log, and the most
recent commit to HEAD},

      "find-on-replicas": %q{
Usage:
  .spokes find-on-replicas host host host [host [...]]

Find all networks on a set of (at least) three hosts.  This is handy for
figuring out which repo or network is the problem when three hosts get
overloaded at the same time.  It's also handy for figuring out which other
repos or networks will suffer when a specific repo or network misbehaves},

      help: %q{
Usage:
  .spokes diagnose [-v] <nwo>
  .spokes find-on-replicas host host host [host [...]]
  .spokes help
  .spokes resolve <dfs-node>
  .spokes server <action> <host> [reason...]
  .spokes set-read-replica <nwo> <dfs-node>
  .spokes set-read-replica <nwo> <dfs-node>=X <dfs-node>=Y <dfs-node>=Z
  .spokes unresolve <dfs-node>
  .spokes freeze <nwo>
  .spokes thaw <nwo>
  .spokes never-cold <nwo>},

      resolve: %q{
Usage:
  .spokes resolve <dfs-node>},

      server: %q{
Usage:
  .spokes server evacuate host reason  Set the evacuation bit to drain all
                                        the repos off a server
  .spokes server unevacuate host       Clear the evacuation bit
  .spokes server embargo host reason   Set the embargo bit to block new
                                        repos on a server
  .spokes server unembargo host        Clear the embargo bit
  .spokes server quiesce host reason   Set the quiescing bit to prevent
                                        read traffic to a server
  .spokes server unquiesce host        Clear the quiescing bit
  .spokes server destroy host          Remove a host and everything routed
                                        to it.  It is recommended but not
                                        required that you evacuate the host
                                        first.  THIS CANNOT BE UNDONE.
  .spokes server retire host           Gracefully destroy a host (with
                                        sanity checks).  THIS CANNOT BE
                                        UNDONE.
  .spokes server online host           Set the online flag, for newly
                                        provisioned hosts.
  .spokes server offline host          Clear the online flag, when destroying
                                        a host.
  .spokes server show {host|status}    Show the embargo, quiesce, and evac
                                        status of a host, or show all hosts
                                        with a given status. Status can be:
                                        inactive, embargoed, quiescing,
                                        evacuating.
  .spokes server provision serial      Provision and install a chassis for
                                        Spokes and deploy apps to it so
                                        that it can begin serving repos.
  .spokes server prepare host          Do initial steps to prepare a host
                                        for Spokes, after it has been
                                        provisioned and installed
  .spokes server ready? host           Check which final steps are needed
                                        before a host can be added to Spokes
  .spokes server resolve host          Update the `ip` column in the fileservers
                                        table for the given host.
  .spokes server unresolve host        Clear the `ip` column in the fileservers
                                        table for the given host (set it to NULL).
  .spokes server add host fqdn <strg>  Add a new fileserver to the database, from
                                        both the short hostname and the fully qualified
                                        name.  Must specify
                                        `storage=(forcessd|forcehdd)`.},

      "set_read_replica": %q{
Usage:
  .spokes set-read-replica <nwo> <dfs-node>
  .spokes set-read-replica <nwo> <dfs-node>=X <dfs-node>=Y <dfs-node>=Z

Reconfigure replicas for a given network so that the given node gets all of the read traffic.  If the given replica is temporarily unhealthy -- offline, or it has a bad checksum -- then read traffic goes to any healthy replica},

      unresolve: %q{
Usage:
  .spokes unresolve <dfs-node>},

      "never-cold": %q{
Usage:
  .spokes never-cold <nwo>

Mark a hot network as not suitable for cold storage, so it is ignored by the sweeper},

      thaw: %q{
Usage:
  .spokes thaw <nwo>

Mark network for nwo as no longer cold, queueing jobs to move replicas back to normal fileservers, from cold storage fileservers},
      freeze: %q{
Usage:
  .spokes freeze <nwo>

Mark network for nwo as cold, queueing jobs to move replicas to cold storage fileservers from normal fileservers},
    }

    def maybe_help(cmd, params, args = nil)
      if params[:help] == "true" || help_args?(args)
        chatop_send HELP_STRINGS[cmd]
        return true
      end

      false
    end

    def help_args?(args)
      return false if args.nil?

      args.any? { |arg| ["-help", "-h"].include?(arg) } || args.empty?
    end
  end
end
