# typed: true
# frozen_string_literal: true

module Billing
  module Stafftools
    class MeteredUsageAggregation
      class SharedStorageUsage
        attr_reader :repo_name, :repo_visibility, :total_usage_in_bytes, :aggregated_actions_usage,
          :unaggregated_actions_usage, :aggregated_gpr_usage, :unaggregated_gpr_usage, :aggregated_gpr_v2_usage,
          :unaggregated_gpr_v2_usage, :sum_aggregated_events

        def initialize(
          repo_name,
          repo_visibility,
          total_usage_in_bytes,
          aggregated_actions_usage:,
          unaggregated_actions_usage:,
          aggregated_gpr_usage:,
          unaggregated_gpr_usage:,
          aggregated_gpr_v2_usage:,
          unaggregated_gpr_v2_usage:,
          sum_aggregated_events:
        )
          @repo_name = repo_name
          @repo_visibility = repo_visibility
          @total_usage_in_bytes = total_usage_in_bytes
          @aggregated_actions_usage = aggregated_actions_usage
          @unaggregated_actions_usage = unaggregated_actions_usage
          @aggregated_gpr_usage = aggregated_gpr_usage
          @unaggregated_gpr_usage = unaggregated_gpr_usage
          @aggregated_gpr_v2_usage = aggregated_gpr_v2_usage
          @unaggregated_gpr_v2_usage = unaggregated_gpr_v2_usage
          @sum_aggregated_events = sum_aggregated_events
        end
      end

      def initialize(owner_id:)
        @owner_id = owner_id
      end

      # Public: Data around upcoming artifact expirations
      #
      # # All dates are in the future
      # # RepoOne id is 1
      # [
      #   {
      #     name: "RepoOne",
      #     size_by_date: {
      #       [1, "2019-12-24"] => 123,
      #       [1, "2019-12-25"] => 124,
      #     },
      #     total_size: 147,
      #   },
      # ]
      #
      # Returns: An Array of Hashes
      def upcoming_actions_artifact_storage_expirations(artifact_event: ::Billing::SharedStorage::ArtifactEvent)
        upcoming_expirations = artifact_event.upcoming_actions_expirations_by_repo_and_effective_at(owner_id)
        actions_artifacts_expiration_fields(upcoming_expirations)
      end

      # Public: Data about package download bandwidth
      #
      # # All dates are in the past
      # # RubyGem1 id is 1
      # [
      #   {
      #     name: "RubyGem1",
      #     bandwidth_by_date: {
      #       [1, "2019-12-24"] => 123,
      #       [1, "2019-12-25"] => 124,
      #     },
      #     total_bandwidth: 147,
      #   },
      # ]
      #
      # Returns: An Array of Hashes
      def packages_bandwidth_since_cycle_reset
        recent_usage = data_transfer_since_reset_by_package_registry_and_downloaded_at
        registry_package_fields(recent_usage)
      end

      # Public: Data about shared storage usage, with repository name and aggregate size in bytes
      #
      # Returns: An Array of SharedStorageUsage instances
      def shared_storage_usage
        return {} unless owner

        artifact_storage_fields(aggregate_size_in_bytes_by_repository_id, owner)
      end

      # Public: Data about actions usage minutes
      #
      # # All dates are in the past
      # # RepoName id is 1
      # [
      #   {
      #     name: "RepoName",
      #     minutes_per_runtime: {
      #       [1, "UBUNTU"] => 123,
      #       [1, "MACOS"] => 124,
      #     },
      #     total_minutes: 147,
      #   },
      # ]
      #
      # Returns: An Array of Hashes
      def actions_usage_since_cycle_reset
        recent_usage = recent_actions_usage
        repository_actions_fields(recent_usage)
      end

      # Public: Data about copilot usage
      def copilot_usage_since_cycle_reset
        return [] unless owner

        line_items_response = billing_api_client.get_usage_line_items(
          product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:copilot],
          usage_starts_at: owner.current_metered_billing_cycle_starts_at,
        )

        line_items_response.map do |line_item|
          usage_at_date = Time.at(line_item.usage_at.seconds, line_item.usage_at.nanos, :nsec, in: GitHub::Billing.timezone).to_date
          { quantity: line_item.quantity, date: usage_at_date }
        end.sort_by { |usage| usage[:date] }.reverse
      end

      private

      attr_reader :owner_id

      def owner
        @owner ||= User.find_by(id: owner_id)
      end

      def billing_api_client
        return @billing_api_client if defined?(@billing_api_client)

        @billing_api_client = ::Billing::Api::ClientWrapper.new(
          billable_owner: owner.billable_owner,
          owner: owner.is_organization_billed_through_business? ? owner : nil,
        )
      end

      def recent_actions_usage
        return {} unless owner

        recent_usage = {}
        GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal) do
          line_items_response = billing_api_client.get_usage_line_items(
            product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions],
            usage_starts_at: owner.current_metered_billing_cycle_starts_at,
          )

          wrapped_line_items = line_items_response.map do |line_item|
            Billing::Actions::UsageLineItemWrapper.new(line_item)
          end
          line_items_by_repository_and_runtime_environment = wrapped_line_items.group_by do |line_item|
            [line_item.repository_id.to_i, line_item.job_runtime_environment]
          end
          line_items_by_repository_and_runtime_environment = line_items_by_repository_and_runtime_environment
            .sort_by do |(_repo_id, runtime_env), _line_items|
              runtime_env
            end
          line_items_by_repository_and_runtime_environment.each do |repo_id_and_runtime_env, line_items|
            recent_usage[repo_id_and_runtime_env] = line_items.sum { |line_item| line_item.effective_duration_in_minutes }
          end
        end

        recent_usage
      end

      def repository_actions_fields(recent_usage)
        repos = Repository.where(id: recent_usage.keys.map(&:first)).select(:id, :name)

        repos.map do |repo|
          minutes_per_runtime = recent_usage.select do |(repo_id, _runtime), _minutes|
            repo.id == repo_id
          end

          {
            name: repo.name,
            minutes_per_runtime: minutes_per_runtime,
            total_minutes: minutes_per_runtime.values.sum,
          }
        end.sort_by { |elem| -1 * elem[:total_minutes] }
      end

      def data_transfer_since_reset_by_package_registry_and_downloaded_at
        return {} unless owner

        line_items_response = billing_api_client.get_usage_line_items(
          product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:packages],
          usage_starts_at: owner.current_metered_billing_cycle_starts_at,
        )
        line_item_by_package_id_and_usage_at = line_items_response.group_by do |line_item|
          usage_at_date = Time.at(line_item.usage_at.seconds, line_item.usage_at.nanos, :nsec, in: GitHub::Billing.timezone).to_date
          [line_item.custom_fields["package.id"].to_i, usage_at_date]
        end
        data_transfer_since_reset = {}

        line_item_by_package_id_and_usage_at.each do |package_id_and_usage_at, line_item|
          data_transfer_since_reset[package_id_and_usage_at] = line_item.sum { |line_item| line_item.quantity.to_i }
        end

        data_transfer_since_reset.sort_by do |(_package_id, usage_at), bytes|
          [usage_at.to_time.to_i, bytes]
        end.to_h
      end

      def registry_package_fields(recent_usage)
        package_ids = recent_usage.keys.map(&:first)
        packages = Registry::Package.where(id: package_ids).select(:id, :name)

        package_fields = packages.map do |package|
          bandwidth_per_package = recent_usage.select do |(package_id, _downloaded_at), _size_in_bytes|
            package.id == package_id
          end

          {
            name: package.name,
            bandwidth_by_date: bandwidth_per_package,
            total_bandwidth: bandwidth_per_package.values.sum,
          }
        end

        missing_package_ids = package_ids - packages.pluck(:id)
        return package_fields if missing_package_ids.empty?

        # package ID 0 indicates a v2 package ( ghcr, npm )
        deleted_package_recent_usage = recent_usage.
          select { |(package_id, _downloaded_at), _| missing_package_ids.include?(package_id) && !package_id.zero? }

        org_package_recent_usage = recent_usage.
          select { |(package_id, _downloaded_at), _| package_id.zero? }

        package_fields << {
          name: "Organization Packages",
          bandwidth_by_date: org_package_recent_usage,
          total_bandwidth: org_package_recent_usage.values.sum,
        } if org_package_recent_usage.count > 0

        package_fields << {
          name: "DELETED PACKAGES",
          bandwidth_by_date: deleted_package_recent_usage,
          total_bandwidth: deleted_package_recent_usage.values.sum,
        }

        package_fields.sort_by { |elem| -1 * elem[:total_bandwidth] }
      end

      def actions_artifacts_expiration_fields(upcoming_expirations)
        repo_ids = upcoming_expirations.keys.map(&:first)

        repos = Repository.where(id: repo_ids).select(:id, :name)

        repos.map do |repo|
          size_by_date = upcoming_expirations.select do |(repo_id, _effective_at), _size|
            repo.id == repo_id
          end

          {
            name: repo.name,
            size_by_date: size_by_date,
            total_size: size_by_date.values.sum,
          }
        end.sort_by { |elem| -1 * elem[:total_size] }
      end

      def artifact_storage_fields(current_storage, owner)
        events = ::Billing::SharedStorage::ArtifactEvent.billable_events_by_repo_and_source(owner_id)

        repos = Repository.where(id: current_storage.keys).select(:id, :name, :public)

        repo_info = repos.map do |repo|
          if current_storage[repo.id].to_i > 0
            repo_visibility = repo.public ? "public" : "private"
            build_shared_storage_usage_entry(
              repo.id,
              repo.name,
              repo_visibility,
              current_storage,
              events: events.select { |k, _| k.first == repo.id },
            )
          end
        end

        if current_storage[nil].to_i > 0
          repo_info << build_shared_storage_usage_entry(
            nil,
            nil,
            nil,
            current_storage,
            events: events.select { |k, _| k.first.nil? },
          )
        end

        repo_info.compact.sort_by { |elem| -1 * elem.total_usage_in_bytes.to_i }
      end

      # Internal: Build a shared storage usage record based on this repos usage
      #
      # events is a hash where the key is an array of [repo_id, source, is_aggregated?]
      # and the value is the summed total size in bytes for the grouped attributes.
      #
      # Example of the sum of 1024 for the aggregated events for actions storage on repo 12345:
      # {
      #   [ 12345, "actions", 1 ] => 1024
      # }
      #
      # Returns an instance of SharedStorageUsage
      def build_shared_storage_usage_entry(repo_id, repo_name, repo_visibility, current_storage, events:)
        total_usage = current_storage[repo_id]

        SharedStorageUsage.new(
          repo_name,
          repo_visibility,
          total_usage.to_i,
          aggregated_actions_usage: [events[[repo_id, "actions", 1]].to_i, 0].max,
          aggregated_gpr_usage: [events[[repo_id, "gpr", 1]].to_i, 0].max,
          aggregated_gpr_v2_usage: [events[[repo_id, "packages_v2", 1]].to_i, 0].max,
          sum_aggregated_events: [sum_aggregated_events(events, repo_id), 0].max,
          unaggregated_actions_usage: events[[repo_id, "actions", 0]].to_i,
          unaggregated_gpr_usage: events[[repo_id, "gpr", 0]].to_i,
          unaggregated_gpr_v2_usage: events[[repo_id, "packages_v2", 0]].to_i,
        )
      end

      def sum_aggregated_events(events, repo_id)
        events[[repo_id, "actions", 1]].to_i +
          events[[repo_id, "gpr", 1]].to_i +
          events[[repo_id, "packages_v2", 1]].to_i
      end

      def aggregate_size_in_bytes_by_repository_id
        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub.dogstats.time("billing.shared_storage.current_usage.aggregate_size_in_bytes_by_repository_id") do
            ::Billing::SharedStorage::CurrentUsage
              .for_reporting(billable_owner: owner.billable_owner, owner_id: owner_id)
              .pluck(:repository_id, :aggregate_size_in_bytes)
              .to_h.transform_keys(0 => nil)
          end
        end
      end
    end
  end
end
