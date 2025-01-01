# typed: false
# frozen_string_literal: true

require "spokes/spokes_pb"
require "spokes/spokes_twirp"
require "spokes-proto"
require "github/dgit/error"

module GitHub
  module Spokes
    class Client
      # Spokes client implementation that makes RPC calls to spokesd.
      # We use Twirp over protobufs to communicate with spokesd.
      class Spokesd
        SERVICE_NAME = "spokesd"

        # These need to be the same as the error reason strings in the spokesd codebase.
        ERROR_REASON_FAILED_TO_LOCK = "failed-to-lock"
        ERROR_REASON_THREEPC        = "threepc"
        ERROR_REASON_TOO_BUSY       = "too-busy"
        ERROR_REASON_TIMEOUT        = "timeout"
        ERROR_REASON_DATABASE       = "database"

        def self.instance
          @instance ||= new
        end

        private_class_method :new

        def client_name
          "spokesd"
        end

        def available?(repository)
          req = ::Spokes::StatusRequest.new(repository: build_repository(repository))

          resp = client.status req
          if resp.error
            # Twirp Errors are not exceptions, so wrap it on our own interpretation
            raise GitHub::Spokes::ClientError.new(resp.error.to_s)
          else
            resp.data.available
          end
        end

        def pick_fileservers
          req = ::Spokes::PickFileServersRequest.new

          resp = client.pick_file_servers req
          # Twirp Errors are not exceptions, so wrap it on our own interpretation
          raise GitHub::Spokes::ClientError.new(resp.error.to_s) if resp.error

          raise GitHub::DGit::UnroutedError, "no hosts found for placement" if resp.data.file_server.empty?

          resp.data.file_server.map do |fs|
            GitHub::DGit::Fileserver.new(
              name: fs.name,
              ip: field_or_nil(fs.ip),
              fqdn: field_or_nil(fs.fqdn),
              datacenter: field_or_nil(fs.datacenter),
              rack: field_or_nil(fs.rack),
              online: fs.online,
              embargoed: fs.embargoed,
              evacuating: fs.evacuating,
              voting: fs.voting,
              hdd_storage: fs.hddStorage)
          end
        end

        def field_or_nil(field)
          # In spokesd values that are NULL are passed around as empty
          # strings, and also put on the wire as such.  However in
          # ruby we actually need NULLable fields in the database to
          # be nil.  This function makes it so.
          field != "" ? field : nil
        end

        def number_field_or_nil(field)
          # In spokesd values that are NULL are passed around as zero
          # values, and also put on the wire as such.  However in
          # ruby we actually need NULLable fields in the database to
          # be nil.  This function makes it so.
          field != 0 ? field : nil
        end

        def repo_type_to_twirp(repo_type)
          case repo_type
          when GitHub::DGit::RepoType::REPO
            ::Spokes::Repository::RepositoryType::REPO
          when GitHub::DGit::RepoType::WIKI
            ::Spokes::Repository::RepositoryType::WIKI
          when GitHub::DGit::RepoType::GIST
            ::Spokes::Repository::RepositoryType::GIST
          when GitHub::DGit::RepoType::NETWORK
            ::Spokes::Repository::RepositoryType::NETWORK
          end
        end

        def create_replica_from_route(route, fileserver, repo_type)
          case repo_type
          when GitHub::DGit::RepoType::REPO, GitHub::DGit::RepoType::WIKI
            GitHub::DGit::Replica::Repo.new(
              db_name: route.db_name,
              fileserver: fileserver,
              read_weight: route.read_weight,
              quiescing: route.quiescing,
              checksum: route.checksum,
              expected_checksum: field_or_nil(route.expected_checksum),
              state: route.replica_state,
              created_at: Time.at(route.created_at),
              updated_at: Time.at(route.updated_at),
              db_network_replica_id: number_field_or_nil(route.network_replica_id),
            )
          when GitHub::DGit::RepoType::GIST
            GitHub::DGit::Replica::Gist.new(
              db_name: route.db_name,
              fileserver: fileserver,
              read_weight: route.read_weight,
              quiescing: route.quiescing,
              state: route.replica_state,
              checksum: route.checksum,
              expected_checksum: field_or_nil(route.expected_checksum),
              created_at: Time.at(route.created_at),
              updated_at: Time.at(route.updated_at),
            )
          when GitHub::DGit::RepoType::NETWORK
            GitHub::DGit::Replica::Network.new(
              db_name: route.db_name,
              fileserver: fileserver,
              read_weight: route.read_weight,
              quiescing: route.quiescing,
              state: route.replica_state,
              created_at: Time.at(route.created_at),
              updated_at: Time.at(route.updated_at),
              db_network_replica_id: number_field_or_nil(route.network_replica_id),
            )
          end
        end

        def all_replicas(network_id, repo_id, repo_type)
          req = ::Spokes::AllRepoReplicasRequest.new(
            repository: ::Spokes::Repository.new(
              type: repo_type_to_twirp(repo_type),
              networkId: network_id,
              repositoryId: repo_id))
          resp = client.all_repo_replicas req
          # Twirp Errors are not exceptions, so wrap it on our own interpretation
          raise GitHub::Spokes::ClientError.new(resp.error.to_s) if resp.error

          resp.data.replicas.map do |route|
            fileserver = GitHub::DGit::Fileserver.new(
              name: route.file_server.name,
              ip: field_or_nil(route.file_server.ip),
              fqdn: field_or_nil(route.file_server.fqdn),
              datacenter: field_or_nil(route.file_server.datacenter) || GitHub.default_datacenter,
              rack: field_or_nil(route.file_server.rack) || GitHub.default_rack,
              online: route.file_server.online,
              embargoed: route.file_server.embargoed,
              evacuating: route.file_server.evacuating,
              voting: route.file_server.voting,
              hdd_storage: route.file_server.hddStorage,
              cache_location: field_or_nil(route.file_server.cacheLocation),
              unreachable: route.file_server.unreachable,
              overloaded: route.file_server.overloaded)
            create_replica_from_route(route, fileserver, repo_type)
          end
        end

        def commit_refs(network_id:, repo_id:, repo_type:, nwo:, priority:, refs:, reflog_msg: "", sockstat:, name: nil, fileservers: nil)
          req = ::GitHub::Spokes::Proto::References::V1::UpdateRequest.new(
            repository: ::GitHub::Spokes::Proto::Types::V1::Repository.new(
              type: repo_type_to_twirp(repo_type),
              id: repo_id || 0,
            ),
            nwo: nwo,
            priority: priority_to_twirp(priority),
            txn: transaction_to_twirp(refs, reflog_msg, sockstat),
            sockstat: sockstat_to_twirp(sockstat),
            fileservers: fileservers,
          )

          req_opts = {}
          unless name.nil?
            req_opts[:headers] = { "GitHub-Gist-Name-Hint" => name }
          end

          client = reference_updates_client
          resp = client.update(req, req_opts)
          if resp&.error
            twirp_to_update_refs_exception(resp.error)
            raise GitHub::Spokes::ClientError.new(resp.error.to_s)
          end

          twirp_to_ref_update_response(resp.data)
        end

        def update_default_branch(network_id:, repo_id:, repo_type:, nwo:, priority:, new_value:, sockstat:, name: nil)
          req = ::GitHub::Spokes::Proto::References::V1::UpdateDefaultBranchRequest.new(
            repository: ::GitHub::Spokes::Proto::Types::V1::Repository.new(
              type: repo_type_to_twirp(repo_type),
              id: repo_id || 0,
            ),
            nwo: nwo,
            priority: priority_to_twirp(priority),
            new_value: ::GitHub::Spokes::Proto::Types::V1::Reference.new(name: new_value.b),
            sockstat: sockstat_to_twirp(sockstat),
            request_context: { quality_of_service: :QUALITY_OF_SERVICE_NO_DELAY },
          )

          req_opts = {}
          unless name.nil?
            req_opts[:headers] = { "GitHub-Gist-Name-Hint" => name }
          end

          client = reference_updates_client
          resp = client.update_default_branch(req, req_opts)
          if resp&.error
            twirp_to_update_refs_exception(resp.error)
            raise GitHub::Spokes::ClientError.new(resp.error.to_s)
          end

          twirp_to_3pc_response(resp.data)
        end

        # Client for the UpdateInfoNWO spokes-api (writer) endpoint.
        # Updates the content of the info/nwo file that is stored in DFS hosts.
        def update_info_nwo(nwo:, repo_id:, repo_type:, priority:, sockstat:, name: nil)
          req = ::GitHub::Spokes::Proto::Repositories::V1::UpdateInfoNWORequest.new(
            repository: ::GitHub::Spokes::Proto::Types::V1::Repository.new(
              type: repo_type_to_twirp(repo_type),
              id: repo_id || 0,
            ),
            nwo: nwo,
            # We use "no delay" here for this request. Should this request fail to
            # write to one replica then the repairs will be more costly than allowing
            # this operation to complete, e.g. the nwo file is used to compute a replica
            # checksum and if that fails then the replica will be marked as bad and in need
            # of repair.
            request_context: { quality_of_service: :QUALITY_OF_SERVICE_NO_DELAY },
            priority: priority_to_twirp(priority),
            sockstat: sockstat_to_twirp(sockstat),
          )

          req_opts = {}
          unless name.nil?
            req_opts[:headers] = { "GitHub-Gist-Name-Hint" => name }
          end

          client = repositories_client
          resp = client.update_info_n_w_o(req, req_opts)
          if resp&.error
            twirp_to_update_refs_exception(resp.error)
            raise GitHub::Spokes::ClientError.new(resp.error.to_s)
          end

          twirp_to_3pc_response(resp.data)
        end

        def recompute_checksums(network_id:, repo_id:, repo_type:, nwo:, priority:, sockstat:, name: nil)
          req = ::GitHub::Spokes::Proto::Repositories::V1::RecomputeChecksumsRequest.new(
            repository: ::GitHub::Spokes::Proto::Types::V1::Repository.new(
              type: repo_type_to_twirp(repo_type),
              id: repo_id || 0,
            ),
            priority: priority_to_twirp(priority),
            sockstat: sockstat_to_twirp(sockstat),
            checksum_strategy: ::GitHub::Spokes::Proto::Repositories::V1::RecomputeChecksumsRequest::ChecksumStrategy::CHECKSUM_STRATEGY_FORGET_CHECKSUMS,
            request_context: { quality_of_service: :QUALITY_OF_SERVICE_NO_DELAY },
          )

          req_opts = {}
          unless name.nil?
            req_opts[:headers] = { "GitHub-Gist-Name-Hint" => name }
          end

          client = repositories_client
          resp = client.recompute_checksums(req, req_opts)
          if resp&.error
            twirp_to_update_refs_exception(resp.error)
            raise GitHub::Spokes::ClientError.new(resp.error.to_s)
          end

          twirp_to_3pc_response(resp.data)
        end

        # TODO - move this to packages/spokes_api.
        #
        # Aside from a few special cases, clients of spokes-proto endpoints
        # should all be wrapped with the client in pacakges/spokes_api instead
        # of the one here.
        def get_all_filepaths_from_repo(repo_id, reference_name, file_extensions: nil, recursive: true)
          file_paths = Array.new
          next_cursor = nil
          loop do
            req = ::GitHub::Spokes::Proto::Trees::V1::ListTreesRequest.new(
              repository: ::GitHub::Spokes::Proto::Types::V1::Repository.new(
                type: ::Spokes::Repository::RepositoryType::REPO,
                id: repo_id || 0,
              ),
              request_context: { quality_of_service: SpokesAPI.quality_of_service ? SpokesAPI.quality_of_service : :QUALITY_OF_SERVICE_NO_DELAY },
              recursive: recursive,
              cursor: next_cursor,
              treeish_selector: {
                treeish: { reference: { name: reference_name } },
              }
            )
            resp = trees_client.list_trees(req)
            raise GitHub::Spokes::ClientError.new(resp.error.to_s) if resp&.error
            resp.data.entries.each do |entry|
              if entry.object.type == :TYPE_BLOB
                file_paths << entry.path.name if file_extensions.empty? || entry.path.name.end_with?(*file_extensions)
              end
            end
            next_cursor = resp.data.next_cursor
            break if next_cursor.nil?
          end
          file_paths
        end

        def build_topology_context(routes)
          ::GitHub::Spokes::Proto::LegacyGitrpc::V1::TopologyContext.new(data_servers: routes&.map { |r| ::GitHub::Spokes::Proto::LegacyGitrpc::V1::DataServer.new(name: r.original_host, voting: r.voting?) })
        end

        def build_legacy_gitrpc_read_request(repo_type, id, options, function, args, kwargs, topology_context)
          ::GitHub::Spokes::Proto::LegacyGitrpc::V1::LegacyGitrpcReaderRequest.new(
            repository: ::GitHub::Spokes::Proto::Types::V1::Repository.new(
              type: repo_type_to_twirp(repo_type),
              id: id),
            request_context: { quality_of_service: :QUALITY_OF_SERVICE_NO_DELAY },
            ernicorn_request: ::GitHub::Spokes::Proto::LegacyGitrpc::V1::ErnicornRequest.new(
              options: options,
              function: function,
              args: args,
              kwargs: kwargs),
            topology_context: topology_context)
        end

        def build_legacy_gitrpc_write_request(repo_type, id, options, function, args, kwargs)
          ::GitHub::Spokes::Proto::LegacyGitrpc::V1::LegacyGitrpcWriterRequest.new(
            repository: ::GitHub::Spokes::Proto::Types::V1::Repository.new(
              type: repo_type_to_twirp(repo_type),
              id: id),
            request_context: { quality_of_service: :QUALITY_OF_SERVICE_NO_DELAY },
            ernicorn_request: ::GitHub::Spokes::Proto::LegacyGitrpc::V1::ErnicornRequest.new(
              options: options,
              function: function,
              args: args,
              kwargs: kwargs))
        end

        def legacy_gitrpc_reader(repo_type, id, timeout, options, function, args, kwargs, topology_context)
          req = build_legacy_gitrpc_read_request(repo_type, id, options, function, args, kwargs, topology_context)
          legacy_gitrpc_client(timeout).legacy_gitrpc_reader(req)
        end

        def async_legacy_gitrpc_reader(repo_type, id, timeout, options, function, args, kwargs, topology_context)
          req = build_legacy_gitrpc_read_request(repo_type, id, options, function, args, kwargs, topology_context)
          async_legacy_gitrpc_client(timeout).legacy_gitrpc_reader(req)
        end

        def legacy_gitrpc_writer(repo_type, id, timeout, options, function, args, kwargs)
          req = build_legacy_gitrpc_write_request(repo_type, id, options, function, args, kwargs)
          legacy_gitrpc_client(timeout).legacy_gitrpc_writer(req)
        end

        def async_legacy_gitrpc_writer(repo_type, id, timeout, options, function, args, kwargs)
          req = build_legacy_gitrpc_write_request(repo_type, id, options, function, args, kwargs)
          async_legacy_gitrpc_client(timeout).legacy_gitrpc_writer(req)
        end

        def bertrpc(host, path, timeout, options, function, args, kwargs)
          req = ::GitHub::Spokes::Proto::LegacyGitrpc::V1::BertrpcRequest.new(
            host: host,
            path: path,
            request_context: { quality_of_service: :QUALITY_OF_SERVICE_NO_DELAY },
            ernicorn_request: ::GitHub::Spokes::Proto::LegacyGitrpc::V1::ErnicornRequest.new(
              options: options,
              function: function,
              args: args,
              kwargs: kwargs))

          legacy_gitrpc_client(timeout).bertrpc(req)
        end

        private

        # build_repository constructs a Repository protobuf object based on the
        # repository-like ActiveRecord object we provide.
        #
        # Raises ArgumentError for an unsupported object.
        def build_repository(repository)
          case repository
          when Repository
            ::Spokes::Repository.new(
              nwo: repository.name_with_owner,
              type: ::Spokes::Repository::RepositoryType::REPO,
              networkId: repository.network.id,
              repositoryId: repository.id)
          when ::GitHub::Unsullied::Wiki
            ::Spokes::Repository.new(
              nwo: repository.nwo,
              type: ::Spokes::Repository::RepositoryType::WIKI,
              networkId: repository.network.id,
              repositoryId: repository.id)
          when Gist
            ::Spokes::Repository.new(
              nwo: repository.name_with_owner,
              type: ::Spokes::Repository::RepositoryType::GIST,
              repositoryId: repository.id)
          when RepositoryNetwork
            ::Spokes::Repository.new(
              nwo: repository.nwo,
              type: ::Spokes::Repository::RepositoryType::NETWORK,
              networkId: repository.id)
          else
            raise ArgumentError, "Unsupported repository type #{repository}"
          end
        end

        def priority_to_twirp(prio)
          value = case prio
          when :high
            ::GitHub::Spokes::Proto::Types::V1::UpdateReferencesPriority::Priority::PRIORITY_HIGH
          when :low
            ::GitHub::Spokes::Proto::Types::V1::UpdateReferencesPriority::Priority::PRIORITY_LOW
          else
            raise ArgumentError, "Unsuppported priority"
          end
          ::GitHub::Spokes::Proto::Types::V1::UpdateReferencesPriority.new(priority: value)
        end

        def sockstat_to_twirp(sockstat)
          ::GitHub::Spokes::Proto::Types::V1::Sockstat.new(data: sockstat.to_h.map do |k, v|
            case v
            when String
              ::GitHub::Spokes::Proto::Types::V1::SockstatKV.new(key: k, bytes_value: v.b)
            when Integer
              ::GitHub::Spokes::Proto::Types::V1::SockstatKV.new(key: k, uint64_value: v)
            when TrueClass, FalseClass
              ::GitHub::Spokes::Proto::Types::V1::SockstatKV.new(key: k, bool_value: v)
            end
          end.to_a)
        end

        def transaction_to_twirp(refs, reflog_message, sockstat)
          now = Time.current

          committer_name = sockstat[:committer_name] || "gitauth"
          committer_email = sockstat[:committer_email] || "gitauth@localhost"
          ::GitHub::Spokes::Proto::References::V1::Transaction.new(
            committer_name:  committer_name.b,
            committer_email: committer_email.b,
            committer_time: now.to_formatted_s(:git),
            reflog_msg: reflog_message,
            ref_update: refs.map do |(refname, before, after, status)|
              ref = ::GitHub::Spokes::Proto::Types::V1::Reference.new(name: refname.b)
              args = if after.nil?
                {
                    ref_verify: ::GitHub::Spokes::Proto::References::V1::UpdateRefOpVerify.new(
                      # reference: ref,
                      oid: ::GitHub::Spokes::Proto::Types::V1::ObjectID.new(id: before.to_s),
                    )
                }
              elsif before.nil?
                {
                  ref_update: ::GitHub::Spokes::Proto::References::V1::UpdateRefOpUpdate.new(
                    # reference: ref,
                    oid: ::GitHub::Spokes::Proto::Types::V1::ObjectID.new(id: after.to_s),
                  )
                }
              else
                {
                    ref_verify_update: ::GitHub::Spokes::Proto::References::V1::UpdateRefOpVerifyUpdate.new(
                      # reference: ref,
                      before: ::GitHub::Spokes::Proto::Types::V1::ObjectID.new(id: before.to_s),
                      after: ::GitHub::Spokes::Proto::Types::V1::ObjectID.new(id: after.to_s),
                    )
                }
              end
              ::GitHub::Spokes::Proto::References::V1::UpdateRefRequest.new(
                fast_forward: ff_status_to_twirp(status),
                reference: ref,
                **args
              )
            end
          )
        end

        def ff_status_to_twirp(ff_status)
          case ff_status
          when "ff"
            ::GitHub::Spokes::Proto::References::V1::UpdateRefRequest::FastForward::FAST_FORWARD_TRUE
          when "nf"
            ::GitHub::Spokes::Proto::References::V1::UpdateRefRequest::FastForward::FAST_FORWARD_FALSE
          when nil
            ::GitHub::Spokes::Proto::References::V1::UpdateRefRequest::FastForward::FAST_FORWARD_OMIT
          else
            ::GitHub::Spokes::Proto::References::V1::UpdateRefRequest::FastForward::FAST_FORWARD_COMPUTE
          end
        end

        def twirp_to_ref_update_response(resp)
          res = {}
          res[:refs_status] = {}
          resp.refs_status.each do |item|
            refname = item.reference.name
            ref_failure_reason = item.reason
            if refname && ref_failure_reason
              res[:refs_status][refname] = ref_failure_reason
            end
          end

          res.merge(twirp_to_3pc_response(resp))
        end

        def twirp_to_3pc_response(resp)
          res = {}

          # Tests need the ability to mock the timestamp with Timecop.freeze, so
          # let's use Time.current rather than the actual response time in tests
          # only when Timecop.freeze is in use.
          res[:committed_at] = Rails.env.test? && Timecop.frozen? ? Time.current : Time.at(resp.committed_at).utc # rubocop:disable GitHub/DoNotBranchOnRailsEnv
          res[:checksum] = resp.checksum
          if resp.error_message != ""
            # The error_message is always set. It is "" if there is no error.
            res[:err] = resp.error_message
          end

          res
        end

        def twirp_to_update_refs_exception(err)
          msg = err.meta[:error_message]
          case err.meta["error_reason"]
          when ERROR_REASON_FAILED_TO_LOCK
            raise GitHub::DGit::ThreepcFailedToLock, msg
          when ERROR_REASON_THREEPC
            raise GitHub::DGit::ThreepcError, msg
          when ERROR_REASON_TOO_BUSY
            raise GitHub::DGit::ThreepcBusyError, msg
          when ERROR_REASON_TIMEOUT
            raise GitHub::DGit::ThreepcError, msg
          when ERROR_REASON_DATABASE
            raise GitHub::DGit::ThreepcError, msg
          end
        end

        def client
          ::Spokes::SpokesClient.new(connection)
        end

        # Helper to check if a feature flag is enabled
        def flipper_enabled?(flipper_key)
          GitHub.respond_to?(:flipper) && GitHub.flipper[flipper_key].enabled?
        end

        # Returns a ReferencesAPI client that is configured with timeouts and
        # retry behavior for the Update method only.
        def reference_updates_client
          ::GitHub::Spokes::Proto::References::V1::ReferencesAPIClient.new(connection_for_3pc)
        end

        def repositories_client
          @repositories_client ||= ::GitHub::Spokes::Proto::Repositories::V1::RepositoriesAPIClient.new(connection_for_3pc)
        end

        def trees_client
          ::GitHub::Spokes::Proto::Trees::V1::TreesAPIClient.new(connection)
        end

        def legacy_gitrpc_client(timeout)
          conn = connection_for_gitrpc
          conn.options.timeout = timeout
          ::GitHub::Spokes::Proto::LegacyGitrpc::V1::LegacyGitrpcAPIClient.new(conn)
        end

        def async_legacy_gitrpc_client(timeout)
          conn = async_connection_for_gitrpc
          conn.options.timeout = timeout
          ::GitHub::Spokes::Proto::LegacyGitrpc::V1::LegacyGitrpcAPIClient.new(conn)
        end

        def async_connection_for_gitrpc
          ssl = nil

          certs = GitHub.spokesd_certs
          unless certs.nil?
            ssl = {
              ca_file: certs[0],
              client_key: certs[1],
              client_cert: certs[2],
            }
          end

          @async_connection_for_gitrpc ||= ::ConcurrentFaraday.new(GitHub.spokesd_url, ssl: ssl) do |conn|
            conn.options[:open_timeout] = 0.250
            conn.options[:timeout]      = 9.3
            conn.headers[:user_agent]   = "GitHub::Spokes::Client github-#{GitHub.role} (#{GitHub.current_sha})"

            conn.request :retry,
              max:                 3,
              interval:            0.050,
              interval_randomness: 0.5,
              backoff_factor:      1.2,

              # What methods should faraday attempt a retry?
              # In Twirp, everything is a POST...
              methods:     [:post],
              exceptions:  [Faraday::ConnectionFailed, Faraday::RetriableResponse],
              retry_block: method(:on_faraday_retry)

            conn.use ::GitHub::FaradayMiddleware::RequestID
            conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME, enable_path_tag: true
            conn.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
            conn.use ::GitHub::FaradayMiddleware::IncreasingTimeout,
              factor: 2
            if flipper_enabled?(:spokesd_request_timeout_header_gitrpc)
              # Add a fudge factor of 150ms as to allow spokesd to detect the timeout before the
              # client times out and disconnects.
              conn.use ::GitHub::FaradayMiddleware::RequestTimeoutHeader, fudge_factor: 0.150
            end

            conn.adapter :concurrent_adapter, persistent: true
          end
        end

        def connection
          # babeld and codeload have a dependency on this and have a
          # timeout of 5 seconds.  Keep this lower than that, so we
          # can respond to them even if we time out on spokesd.
          @connection ||= build_faraday_connection(default_timeout: 4.0, retry_on: :timeout)
        end

        # We use this separate, persistent connection for proxying GitRPC
        # through spokesd, because we want different timeout/retry
        # behavior for that.
        def connection_for_gitrpc
          # The timeout gets changed on each call to match the GitRPC
          # client_timeout (usually the 9s backend timeout + 300ms fudge, but
          # it can be much longer for some background jobs).
          @connection_for_gitrpc ||= build_faraday_connection(default_timeout: 9.3, retry_on: :retryable_error)
        end

        # We use this separate connection for 3PC because we need different
        # timeout and retry config here.
        def connection_for_3pc
          # Spokesd's 3PC implementation does not have a timeout on the entire
          # transaction, but the individual timeouts add up to about 50
          # seconds. We set the timeout a little higher here.
          req_timeout_header = flipper_enabled?(:spokesd_request_timeout_header_3pc)
          @connection_for_3pc ||= build_faraday_connection(default_timeout: 60.0, retry_on: :connect_error)
        end

        def build_faraday_connection(default_timeout:, retry_on:)
          ssl = nil

          certs = GitHub.spokesd_certs
          unless certs.nil?
            ssl = {
              ca_file: certs[0],
              client_key: certs[1],
              client_cert: certs[2],
            }
          end

          # Always retry on connect errors.
          retry_on_exceptions =
            case retry_on
            when :connect_error
              [Faraday::ConnectionFailed]
            when :retryable_error
              [Faraday::ConnectionFailed, Faraday::RetriableResponse]
            when :timeout
              [Faraday::ConnectionFailed, Faraday::RetriableResponse, Faraday::TimeoutError]
            else
              raise ArgumentError, "retry_on (#{retry_on.inspect}) must be one of :connect_error, :retryable_error, or :timeout"
            end

          GitHub::FaradayClient.internal(SERVICE_NAME, GitHub.spokesd_url, {
            request: {
              open_timeout: 0.250,
              timeout: default_timeout,
            },
            ssl: ssl,
          }) do |conn|
            conn.headers[:user_agent] = "GitHub::Spokes::Client github-#{GitHub.role} (#{GitHub.current_sha})"

            conn.use GitHub::FaradayMiddleware::Datadog, enable_path_tag: true
            conn.use GitHub::FaradayMiddleware::Retries,
              max:                 2,
              interval:            0.050,
              interval_randomness: 0.5,
              backoff_factor:      1.2,

              methods:     [:post],
              exceptions:  retry_on_exceptions,
              retry_block: method(:on_faraday_retry)
            conn.use GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2
            # Add a fudge factor of 150ms as to allow spokesd to detect the timeout before the
            # client times out and disconnects.
            conn.use GitHub::FaradayMiddleware::RequestTimeoutHeader, fudge_factor: 0.150
          end
        end

        def on_faraday_retry(env, _, _retries, exception)
          tags = [
            "status:#{env[:status]}",
            "method:#{env[:method]}",
            "path:#{env[:url].request_uri}",
            "error:#{exception.class}",
          ]
          GitHub.dogstats.increment("rpc.#{SERVICE_NAME}.retries", tags: tags)
        end
      end
    end
  end
end
