# typed: strict
# frozen_string_literal: true

module Permissions
  module EntryPoint
    class ActorContext

      ACTOR_LEVEL_EVENT_KEY = "permissions.service.write_requested"
      NO_ACTOR_CONTEXT_STATS_KEY = "permissions_service.instrumentation.no_actor_context"
      INCOMPLETE_CONTEXT_STATS_KEY = "permissions_actor_context.incomplete_context"
      LOAD_INDIRECT_ATTRS_STATS_KEY = "permissions_actor_context.load_indirect_attributes.time"
      MULTIPLE_ACTOR_CONTEXTS_STATS_KEY = "permissions_actor_context.multiple_actor_contexts.time"
      TOTAL_INSTRUMENTATION_TIME_STATS_KEY = "permissions_actor_context.instrumentation.time"

      sig do
        params(
          metric_suffix: String,
          entry_point: Service::EntryPoint,
          rows: T.any(
            T::Array[T.any(T::Array[Integer], T::Hash[String, T.untyped])],
            ActiveRecord::Relation
          ),
          total: Integer
        ).void
      end
      def self.instrument(metric_suffix, entry_point, rows = [], total = 1)
        tags = [
          "entry_point:#{entry_point.tag_name}",
          "background:#{!GitHub.foreground?}",
        ]

        GitHub.dogstats.distribution_time(TOTAL_INSTRUMENTATION_TIME_STATS_KEY, tags: tags) do
          normalized_rows = normalize_rows(rows)
          write_type = WriteType.deserialize(metric_suffix)
          is_custom_entry_point = entry_point.actor_owner.present? # Mag5 entry points have an owner

          if is_custom_entry_point
            instrument_custom_entry_point(write_type, entry_point, normalized_rows, total)
          else
            instrument_each_actor_context(write_type, entry_point, normalized_rows)
          end
        end
      end

      # Internal use only
      # These are single actor contexts, manually defined because of their
      # volume and activity. The Magnificent 5 with different write types.
      # See: https://github.com/github/ecosystem-apps/issues/4327
      sig do
        params(
          write_type: WriteType,
          entry_point: Service::EntryPoint,
          rows: T::Array[T::Hash[Symbol, T.untyped]],
          total: Integer
        ).void
      end
      def self.instrument_custom_entry_point(write_type, entry_point, rows = [], total = 1)
        context =
          case write_type
          when WriteType::CREATE, WriteType::UPDATE
            build_from_custom_entry_point(write_type, entry_point, rows)
          when WriteType::DELETE
            build_from_entry_point_only(write_type, entry_point, total)
          else
            T.absurd(write_type)
          end

        unless context
          stat_bad_entry_point(entry_point, write_type.serialize)
          return
        end

        load_indirect_attributes_and_instrument(context)
      end

      # Internal use only
      # Contexts here are dynamically built from rows and might incur in extra queries.
      sig do
        params(
          write_type: WriteType,
          entry_point: Service::EntryPoint,
          rows: T::Array[T::Hash[Symbol, T.untyped]]
        ).void
      end
      def self.instrument_each_actor_context(write_type, entry_point, rows = [])
        grouped_by_actor = rows.group_by { |row| [row[:actor_id], row[:actor_type]] }
        has_missing_actor_info = grouped_by_actor.keys.any? { |id, type| id.blank? || type.blank? }

        if grouped_by_actor.empty? || has_missing_actor_info
          stat_bad_entry_point(entry_point, write_type.serialize)
          return
        end

        contexts = grouped_by_actor.map do |(actor_id, actor_type), entries|
          new(
            entry_point_tag: entry_point.tag_name,
            total: entries.count,
            actor_id: actor_id,
            actor_type: actor_type,
            subject_type_total: subtotals_by_subject_type(entries),
            write_type: write_type,
            digest: digest_from_rows(entries),
          )
        end

        tags = [
          "entry_point:#{entry_point.tag_name}",
          "multiple_actors:#{contexts.count > 1}",
          "background:#{!GitHub.foreground?}",
        ]

        GitHub.dogstats.distribution_time(MULTIPLE_ACTOR_CONTEXTS_STATS_KEY, tags: tags) do
          contexts.each { |context| load_indirect_attributes_and_instrument(context) }
        end
      end

      sig do
        params(
          context: ActorContext,
          decorator: T.class_of(HydroDecorator),
          instrumenter: T.class_of(GlobalInstrumenter)
        ).void
      end
      def self.load_indirect_attributes_and_instrument(context, decorator: HydroDecorator, instrumenter: GlobalInstrumenter)
        context.load_indirect_attributes # i.e. owner & target
        instrumenter.instrument(ACTOR_LEVEL_EVENT_KEY, context.to_params(decorator:))
      end

      # Internal use only
      # Builds contexts for custom entrypoints without rows (Mag5 updates/deletes)
      sig do
        params(
          write_type: WriteType,
          entry_point: Service::EntryPoint,
          total: Integer
        ).returns(T.nilable(ActorContext))
      end
      def self.build_from_entry_point_only(write_type, entry_point, total)
        # updates and deletes do not have rows
        # only mag5 have actors present
        return unless entry_point.actor_owner
        return unless entry_point.actor.present?

        new(
          entry_point_tag: entry_point.tag_name,
          total: total,
          actor_id: entry_point.actor.id,
          actor_type: entry_point.actor.class.to_s,
          subject_type_total: {}, # In this step we won't have a breakdown by subject type
          write_type: write_type,
          owner: entry_point.actor_owner,
          target: entry_point.target,
          parent_installation_id: entry_point.parent_installation&.id,
          scope_type: entry_point.scope_type,
        )
      end

      sig do
        params(
          write_type: WriteType,
          entry_point: Service::EntryPoint,
          rows: T::Array[T::Hash[Symbol, T.untyped]],
        ).returns(T.nilable(ActorContext))
      end
      def self.build_from_custom_entry_point(write_type, entry_point, rows)
        # mag5 inserts have rows and actors
        return unless entry_point.actor_owner

        actor_id, actor_type = fetch_actor_info(rows)
        return unless actor_id && actor_type

        new(
          entry_point_tag: entry_point.tag_name,
          total: rows.count,
          actor_id: actor_id,
          actor_type: actor_type,
          subject_type_total: subtotals_by_subject_type(rows),
          write_type: write_type,
          owner: entry_point.actor_owner,
          target: entry_point.target,
          parent_installation_id: entry_point.parent_installation&.id,
          digest: digest_from_rows(rows),
          scope_type: entry_point.scope_type,
        )
      end

      sig { params(rows: T::Array[T::Hash[Symbol, T.any(Integer, String)]]).returns(T.nilable(String)) }
      def self.digest_from_rows(rows)
        return unless rows.present?
        return unless FeatureFlag.vexi.enabled?(:permissions_entry_point_digest, default: false)

        digest = Digest::SHA256.new
        # ensure rows are consistently sorted
        rows.sort_by do |row|
          row.values.map(&:to_s).sort
        end.each do |row|
          # ensure hash values are digested in the same order every time
          row.keys.sort.each do |key|
            digest << row[key].to_s
          end
        end
        digest.hexdigest
      end

      sig { params(rows: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T.untyped]) }
      def self.fetch_actor_info(rows = [])
        return [nil, nil] if rows.blank?

        first_row = T.must(rows.first)
        [first_row[:actor_id], first_row[:actor_type]]
      end

      sig { params(rows: T::Array[T.untyped]).returns(T::Hash[String, Integer]) }
      def self.subtotals_by_subject_type(rows = [])
        rows = rows.reject(&:blank?)
        return {} if rows.blank?

        rows.group_by { |row| row[:subject_type] }.transform_values(&:count)
      end

      # Transforms rows into a consistent format, from all the possible sources
      # in which permission records can be represented, to simplify further processing.
      #
      # It supports:
      # - ActiveRecord::Relation of Permission records
      # - Array of hashes that include the following keys:
      #   - actor_id
      #   - actor_type
      #   - subject_type
      # - [Legacy] Array of arrays with the following information at indexes:
      #   - 0: actor_id
      #   - 1: actor_type
      #   - 4: subject_id
      #
      # Returns an empty array or an array of hashes with the following keys:
      # - actor_id
      # - actor_type
      # - subject_type
      sig do
        params(
          rows: T.any(
            T::Array[T.untyped],
            ActiveRecord::Relation
          )
        ).returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def self.normalize_rows(rows)
        keys = %i[actor_id actor_type subject_type]

        if rows.is_a?(ActiveRecord::Relation) && rows.klass == Permission
          ActiveRecord::Base.connected_to(role: :reading) do
            rows.pluck(*keys).map { |values| keys.zip(values).to_h }
          end
        elsif rows.first.is_a?(Array) && rows.first.size > 3
          rows.map do |attrs|
            values = [attrs[0], attrs[1], attrs[4]] # actor_id, actor_type, subject_type
            keys.zip(values).to_h
          end
        elsif rows.first.is_a?(Hash)
          rows.map { |h| h.symbolize_keys.slice(*keys) }
        else
          []
        end
      end

      sig { params(entry_point: Service::EntryPoint, metric_suffix: String).void }
      def self.stat_bad_entry_point(entry_point, metric_suffix)
        GitHub.dogstats.increment(
          NO_ACTOR_CONTEXT_STATS_KEY,
          tags: [
            "entry_point:#{entry_point.tag_name}",
            "metric_suffix:#{metric_suffix}"
          ],
        )
      end

      sig { returns(String) }
      attr_reader :entry_point_tag

      sig { returns(Integer) }
      attr_reader :actor_id

      sig { returns(T::Hash[String, Integer]) }
      attr_reader :subject_type_total

      sig { returns(WriteType) }
      attr_reader :write_type

      sig { returns(String) }
      attr_reader :actor_type

      sig { returns(T.nilable(T.any(Integration, Organization, UserProgrammaticAccess))) }
      attr_reader :owner

      sig { returns(T.nilable(T.any(Organization, User, Business))) }
      attr_reader :target

      sig do
        params(
          write_type: WriteType,
          entry_point_tag: String,
          actor_id: Integer,
          actor_type: String,
          total: Integer,
          target: T.nilable(T.any(Organization, User, Business)),
          subject_type_total: T::Hash[String, Integer],
          owner: T.nilable(T.any(Integration, Organization, UserProgrammaticAccess)),
          parent_installation_id: T.nilable(Integer),
          digest: T.nilable(String),
          scope_type: Symbol,
        ).void
      end
      def initialize(write_type:, entry_point_tag:, actor_id:, actor_type:, total:, target: nil, subject_type_total: {}, owner: nil, parent_installation_id: nil, digest: nil, scope_type: :SCOPE_TYPE_UNKNOWN)
        @write_type = write_type
        @entry_point_tag = entry_point_tag
        @actor_id = actor_id
        @actor_type = actor_type
        @subject_type_total = subject_type_total
        @total = total
        @owner = owner
        @target = target
        @parent_installation_id = parent_installation_id
        @digest = digest
        @scope_type = scope_type
      end

      sig { returns(String) }
      def owner_type
        return "" unless @owner

        @owner.class.to_s
      end

      sig { returns(String) }
      def target_type
        return "" unless @target

        @target.class.to_s
      end

      sig { returns(T::Boolean) }
      def has_indirect_attributes?
        # only mag5 will have these attributes present
        @owner.present? && @target.present?
      end

      sig { void }
      def load_indirect_attributes
        return if has_indirect_attributes?

        tags = [
          "actor_type:#{@actor_type}",
          "entry_point:#{@entry_point_tag}",
          "background:#{!GitHub.foreground?}",
        ]

        actor = T.let(nil, T.nilable(ActiveRecord::Base))

        GitHub.dogstats.distribution_time(LOAD_INDIRECT_ATTRS_STATS_KEY, tags: tags) do
          ActiveRecord::Base.connected_to(role: :reading) do
            case @actor_type
            when "IntegrationInstallation"
              actor = IntegrationInstallation.find_by(id: @actor_id)
              @owner = actor&.integration
              @target = actor&.target
            when "OauthAuthorization"
              actor = OauthAuthorization.find_by(id: @actor_id)
              @owner = actor&.application
              @target = actor&.user # Confirm this assumption
            when "OrganizationProgrammaticAccessGrant"
              actor = OrganizationProgrammaticAccessGrant.find_by(id: @actor_id)
              @owner = actor&.user_programmatic_access
              @target = actor&.target
            when "OrganizationProgrammaticAccessGrantRequest"
              actor = OrganizationProgrammaticAccessGrantRequest.find_by(id: @actor_id)
              @owner = actor&.user_programmatic_access
              @target = actor&.target
            when "UserProgrammaticAccessGrant"
              actor = UserProgrammaticAccessGrant.find_by(id: @actor_id)
              @owner = actor&.user_programmatic_access
              @target = actor&.target
            when "UserProgrammaticAccessGrantRequest"
              actor = UserProgrammaticAccessGrantRequest.find_by(id: @actor_id)
              @owner = actor&.user_programmatic_access
              @target = actor&.target
            when "ScopedIntegrationInstallation"
              actor = ScopedIntegrationInstallation.find_by(id: @actor_id)
              @owner = actor&.integration
              @target = actor&.target if actor&.parent.present?
              @parent_installation_id = actor&.integration_installation_id
            when "SiteScopedIntegrationInstallation"
              actor = SiteScopedIntegrationInstallation.find_by(id: @actor_id)
              @owner = actor&.integration
              @target = actor&.target
            end
          end

          if !actor
            GitHub.dogstats.increment(
              INCOMPLETE_CONTEXT_STATS_KEY,
              tags: tags + ["reason:actor_not_found"],
            )
          elsif !@owner || !@target
            GitHub.dogstats.increment(
              INCOMPLETE_CONTEXT_STATS_KEY,
              tags: tags + ["reason:indirect_attributes_not_found"],
            )
          end
        end
      end

      sig { params(decorator: T.class_of(HydroDecorator)).returns(T::Hash[Symbol, T.untyped]) }
      def to_params(decorator: HydroDecorator)
        decorated = decorator.new(self)

        {
          actor_type: decorated.actor_type,
          target_type: decorated.target_type,
          write_type: decorated.write_type,
          owner_type: decorated.owner_type,
          actor_id: @actor_id,
          target_id: @target&.id,
          total: @total,
          parent_installation_id: @parent_installation_id,
          owner_id: @owner&.id,
          owner_name: @owner&.name,
          entry_point: @entry_point_tag,
          subject_type_total: @subject_type_total,
          digest: @digest,
          scope_type: @scope_type,
        }
      end
    end
  end
end
