# frozen_string_literal: true

module HydroHandlers
  module GitHub
    class DependencyUpdate
      SUPPORTED_TRIGGER_TYPES = %i(
        INSTALL
        MANUAL
        SCAN
        PUSH
        DRY_RUN
      ).freeze

      PERMITTED_ATTRIBUTES = %i(
        repository_dependency_update_id
        trigger
        dry_run
      ).freeze

      attr_reader :id, :triggered_at

      def self.from_message(message)
        attributes = message.value.slice(*PERMITTED_ATTRIBUTES).tap do |a|
          a[:id] = a.fetch(:repository_dependency_update_id)
        end
        manifest_path = message.value.
                        dig(:repository_vulnerability_alert, :path)

        new attributes.merge(
          manifest_path: manifest_path,
          triggered_at: Time.at(message.timestamp).utc,
        )
      end

      def initialize(attributes)
        @id            = attributes.fetch(:id)
        @manifest_path = attributes.fetch(:manifest_path)
        @trigger       = attributes.fetch(:trigger)
        @triggered_at  = attributes.fetch(:triggered_at)
        @dry_run       = attributes.fetch(:dry_run, false)
      end

      def attributes
        {
          id: @id,
          manifest_path: @manifest_path,
          trigger: @trigger,
          triggered_at: @triggered_at,
          dry_run: @dry_run,
        }
      end

      def trigger
        # A trigger type of DRY_RUN is deprecated, but in the event we ingest
        # historic data, we should map it explicitly to an unknown trigger type.
        #
        # This can be removed once we have finished cleaning up these rows in
        # GitHub and feel certain we won't need to reconsume our logs-to-date.
        return "unknown" if @trigger.nil? || @trigger == :DRY_RUN

        @trigger.downcase.to_s
      end

      def user_requested?
        @trigger == :MANUAL
      end

      def dry_run?
        @trigger == :DRY_RUN || @dry_run
      end

      def supported_trigger_type?
        SUPPORTED_TRIGGER_TYPES.include?(@trigger)
      end

      def manifest_dir
        File.dirname(@manifest_path)
      end

      def manifest_name
        File.basename(@manifest_path)
      end

      def already_consumed?
        UpdateJob.exists?(github_request_id: @id)
      end
    end
  end
end
