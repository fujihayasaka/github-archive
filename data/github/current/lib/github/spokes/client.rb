# typed: true
# frozen_string_literal: true

module GitHub
  module Spokes
    # The Spokes Client is in a state of transition (and it may for quite some time)
    # We have the capability then to decide between two implementations of the API:
    #  1. The (legacy) local DGit implementation which will use ActiveRecord and
    #     standard GitRPC calls to generate API responses.
    #  2. A RPC implementation which will communicate with Spokesd.
    #
    # As we migrate we'll want to treat each API call individually to safely
    # control rollout as well as correctly handle Spokes in environments without
    # Spokesd (testing, enterprise).
    class Client
      autoload :DGit,    "github/spokes/client/dgit"
      autoload :Spokesd, "github/spokes/client/spokesd"

      # available? returns true if the specified repository
      # (or repository like object) is routable to an available file server.
      def available?(repository)
        # Not every "repository"-like object is actually a flipper actor
        actor = repository if repository.respond_to? :flipper_id

        rpc :available?,
            repository,
            feature: nil, # feature is fully enabled.
            actor: actor
      end

      def pick_fileservers(actor:)
        rpc :pick_fileservers,
            feature: nil, # feature is fully enabled.
            actor: actor,
            fallback: true
      end

      def self.instrument(event, payload = {}, &blk)
        ActiveSupport::Notifications.instrument("#{event}.client.spokes", payload, &blk)
      end

      def all_replicas(network_id, repo_id, repo_type)
        rpc :all_replicas,
            network_id,
            repo_id,
            repo_type,
            feature: nil, # feature is fully enabled.
            fallback: true
      end

      def write_nwo_file(repository, nwo)
        rpc :write_nwo_file,
            repository,
            nwo,
            feature: nil, # We haven't ported this yet.
            dgit_only: true
      end

      private

      class FallbackClient
        def initialize(spokesd_client, dgit_client)
          @spokesd_client = spokesd_client
          @dgit_client = dgit_client
        end

        def method_missing(meth, *args, &blk)
          super unless @spokesd_client.respond_to?(meth)

          begin
            @spokesd_client.public_send(meth, *args)
          rescue GitHub::Spokes::ClientError, Faraday::Error => e
            Client.instrument "fallback", method: meth, exception: e
            @dgit_client.public_send(meth, *args)
          end
        end
      end

      def rpc(method, *args, feature: nil, actor: nil, fallback: false, dgit_only: false)
        rpc_client = client(feature, actor, fallback, dgit_only)

        Client.instrument "rpc", method: method, client: rpc_client do
          rpc_client.public_send(method, *args)
        end
      end

      def use_spokesd?(feature, actor)
        if !GitHub.spokesd_enabled?
          return false
        end
        if !GitHub::DGit.have_cache_location_column?
          return false
        end

        GitHub.enterprise? || feature.nil? || (GitHub.respond_to?(:flipper) && GitHub.flipper[feature].enabled?(actor))
      end

      def client(feature, actor, fallback, dgit_only)
        if !dgit_only && use_spokesd?(feature, actor)
          if fallback && GitHub.spokesd_fallback_enabled?
            FallbackClient.new spokesd_client, dgit_client
          else
            spokesd_client
          end
        else
          dgit_client
        end
      end

      def dgit_client
        DGit.new
      end

      def spokesd_client
        @spokesd_client ||= Spokesd.instance
      end
    end
  end
end
