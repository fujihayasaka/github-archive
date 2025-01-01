# typed: true
# frozen_string_literal: true

require "horcrux/entity"
require "horcrux/multiple"
require "horcrux/serializers/gzip_serializer"
require "horcrux/serializers/message_pack_serializer"
require "stratocaster"

module GitHub
  module Config
    module Services
      # Public: Temporarily disables notification/event services for a block.
      #
      # service - Optional Stratocaster::Service instance.
      #
      # Returns nothing.
      def importing(service = GitHub.stratocaster)
        original_value = !!@importing
        service ||= GitHub.stratocaster
        @importing = true
        service.disable

        yield
      ensure
        unless original_value
          @importing = false
          service.enable
        end
      end

      # Public: Checks to see if Notifications should be sent.
      #
      # Returns a Boolean.
      def send_notifications?
        !@importing && !!@send_notifications
      end

      # Public: Checks to see if an import is in progress.
      #
      # Returns a Boolean.
      def importing?
        !!@importing
      end

      # Public: Checks to see if Events should be triggered.
      #
      # service - Optional Stratocaster::Service instance.
      #
      # Returns a Boolean.
      def trigger_events?(service = GitHub.stratocaster)
        service.enabled?
      end

      def newsies
        @newsies ||= ::Newsies::Service.new
      end

      def stratocaster
        @stratocaster ||= build_stratocaster
      end

      def build_stratocaster(store = stratocaster_store, indexer = stratocaster_indexer)
        ::Stratocaster::Service.new(store, indexer)
      end

      def stratocaster_store
        @stratocaster_store ||= ::Stratocaster::Mysql2Store.new
      end

      def stratocaster_indexer
        @stratocaster_indexer ||= ::Stratocaster::Indexers::Proxy.default
      end

      attr_writer :stratocaster, :send_notifications, :newsies_mysql_web, :newsies

      if Rails.env.test?
        module StratocasterTestOverrides
          def stratocaster_store
            @stratocaster_store ||= ::Stratocaster::MemoryStore.new
          end

          def stratocaster_indexer
            @stratocaster_indexer ||= begin
              indexers = { org_all: ::Stratocaster::Indexers::MemoryIndexer.new(max: ::Stratocaster::OrgAllTimeline::INDEX_LENGTH),
                          other: ::Stratocaster::Indexers::MemoryIndexer.new }

              ::Stratocaster::Indexers::Proxy.new(indexers) do |partitions, timelines|
                partitions[:other] = timelines.except(Stratocaster::TimelineTypes::ORG_ALL)          # all except the org_all timeline (this includes activity_all as well)
                partitions[:org_all] = timelines.slice(Stratocaster::TimelineTypes::ORG_ALL)
              end
            end
          end

          def reset_stratocaster
            @stratocaster_store = @stratocaster_indexer = @stratocaster = nil
          end
        end

        prepend StratocasterTestOverrides
      end
    end
  end

  extend Config::Services
  self.send_notifications = true
end
