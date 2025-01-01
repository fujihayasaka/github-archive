# typed: true
# frozen_string_literal: true

require "monolith-twirp-pages-pagesdfsapi"

module Api::Internal::Twirp::Pages
  module Dfs
    module V1
      class PagesDfsHandler < Api::Internal::Twirp::Handler
        extend T::Helpers

        handles_service MonolithTwirp::Pages::Pagesdfsapi::V1::DfsAPIService
        allow_access_for :client, allowed_clients: %w[pages pages_deployer]
        exempt_from_tenant_context_requirement

        def get_available_hosts(req, env)
          hosts = ActiveRecord::Base.connected_to(role: :reading) do
            ApplicationRecord::Domain::Repositories.connection.select_rows(<<-SQL)
            SELECT host,datacenter FROM pages_fileservers
            WHERE online = 1 AND embargoed = 0
            SQL
          end
          result = []
          hosts.each do |host, datacenter|
            result << MonolithTwirp::Pages::Pagesdfsapi::V1::HostInfo.new(host_name: host, datacenter: datacenter)
          end
          {
            host_info: result
          }
        end

        def get_dfs_status(req, env)
          rows = Page::FileServer.find_by_sql(Arel.sql(<<-SQL))
            SELECT
            host,
            datacenter,
            online,
            embargoed,
            evacuating,
            non_voting,
            disk_free,
            disk_used,
            created_at
          FROM pages_fileservers
          ORDER BY non_voting, datacenter, host ASC
          SQL
          result = []
          rows.each do |row|
            result << MonolithTwirp::Pages::Pagesdfsapi::V1::HostInfo.new(
              host_name: row.host,
              datacenter: row.datacenter,
              is_online: Google::Protobuf::BoolValue.new(value: row.online),
              is_embargoed: Google::Protobuf::BoolValue.new(value: row.embargoed),
              is_evacuating: Google::Protobuf::BoolValue.new(value: row.evacuating),
              is_voting: Google::Protobuf::BoolValue.new(value: !row.non_voting),
              disk_free: row.disk_free.to_s,
              disk_used: row.disk_used.to_s,
              created_at: Google::Protobuf::Timestamp.new(seconds: row.created_at.to_i, nanos: row.created_at.nsec)
            )
          end
          {
            host_info: result
          }
        end

        def list_pages_replicas(req, env)
          page_deployment_id = req.page_deployment_id.present? ? req.page_deployment_id : nil
          replicas = GitHub::Pages::Management::ListReplicas.new(
                      page_id: req.page_id,
                      page_deployment_id: page_deployment_id,
                      delegate: nil
                    ).get_results
          result = []
          replicas.each do |replica|
            result << MonolithTwirp::Pages::Pagesdfsapi::V1::ReplicaInfo.new({
              deployment_id: replica[2].to_s,
              revision: replica[1],
              dfs_host: replica[0]
            })
          end
          {
            replica_info: result
          }
        end

        def get_repairable_replicas(req, env)
          to_be_repaired = GitHub::Pages::Management::Repair.new(delegate: nil).repairable_unhealthy_pages_replica_counts
          result = []
          to_be_repaired.each do |repairable|
            result << MonolithTwirp::Pages::Pagesdfsapi::V1::RepairableReplicaInfo.new(repairable)
          end
          {
            repairable_replica_info: result
          }
        end

        # TODO, sync schema and pass datacenter in request body
        def set_dfs_host_status(req, env)
          host_name = req.host_name
          updated_fileds = {}

          if req.should_online != nil
            updated_fileds[:online] = req.should_online.value
          end

          if req.should_embargoed != nil
            updated_fileds[:embargoed] = req.should_embargoed.value
          end

          if req.should_evacuating != nil
            updated_fileds[:evacuating] = req.should_evacuating.value
          end
          if req.should_voting != nil
            updated_fileds[:non_voting] = !req.should_voting.value
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            if req.should_embargoed != nil
              datacenter = ApplicationRecord::Domain::Repositories.connection.select_value(Arel.sql(<<-SQL, host: host_name))
                SELECT datacenter FROM pages_fileservers WHERE host = :host
              SQL
              return {} unless datacenter.present?
              payload = {
                hostname: host_name,
                datacenter: datacenter,
                embargoed: { value: updated_fileds[:embargoed] },
              }
              result = GitHub.hydro_publisher.publish(
                payload,
                schema: "pages_dfs.v1.DfsStatus",
                topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 })
              return {} unless result.success?
            end
            Page::FileServer.where(host: host_name).update_all(updated_fileds)
          end unless updated_fileds.empty?
          {}
        end

        def update_pages_replica(req, env)
          page_id = req.page_id
          ActiveRecord::Base.connected_to(role: :writing) do
            delegate = GitHub::Pages::Management::Delegate.new
            req.replica_to_add.each do |replica|
              command = GitHub::Pages::Management::AddReplica.new(page_id: page_id, page_deployment_id: nil, delegate: delegate, voting: true)

              # TODO, check add replica succeed or not.
              page_deployment_id = replica.deployment_id.present? ? replica.deployment_id : nil
              command.add_replica(host: replica.dfs_host, page_id: page_id, page_deployment_id: page_deployment_id, revision: replica.revision, find_revision: replica.revision.empty?)
            end unless req.replica_to_add.empty?
            req.replica_to_remove.each do |replica|
              page_deployment_id = replica.deployment_id.present? ? replica.deployment_id : nil
              command = GitHub::Pages::Management::RemoveReplica.new(page_id: page_id, page_deployment_id: page_deployment_id, host: replica.dfs_host, delegate: delegate)

              # TODO, check remove replica succeed or not.
              command.perform
            end unless req.replica_to_remove.empty?
          end
          {}
        end

        # TODO, check why we need offline before remove the db record, since offline only mark db online attribute as offline
        def remove_dfs_host(req, env)
          host_name = req.host_name
          ActiveRecord::Base.connected_to(role: :writing) do
            Page::FileServer.where(host: host_name).delete_all
          end unless host_name.empty?
          {}
        end

        sig do
          params(
            req: ::MonolithTwirp::Pages::Pagesdfsapi::V1::GetPagesVersionByHostRequest,
            env: T::Hash[T.untyped, T.untyped],
          )
          .returns(T::Hash[T.untyped, T.untyped])
        end
        def get_pages_version_by_host(req, env)
          page_ids = req.page_ids.empty? ? [] : req.page_ids.to_a
          host = req.host_name
          current_deployments = []
          GitHub::Pages::GarbageCollector.deployed_revisions_with_replica_count(page_ids: page_ids, host: host).each do |id, built_revision|
            current_deployments << "#{id}_#{built_revision}"
          end
          {
            page_id_version: current_deployments
          }
        end
      end
    end
  end
end
