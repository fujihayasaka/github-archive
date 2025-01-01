# typed: strict
# frozen_string_literal: true

module GitHub
  module Prioritizable::Context
    extend T::Helpers

    requires_ancestor { ApplicationRecord::Base }

    class LockedForRebalance < StandardError; end
    class InvalidAssociation < StandardError; end

    # Options for how to perform a rebalance.
    class RebalanceMode < T::Enum
      enums do
        # Determine order of items by reading from the legacy `priority` column, and only write that column also
        Legacy = new

        # Determine order of items by reading from the legacy `priority` column, but write to both that column and
        # the new `priority_numerator`/`priority_denominator` columns from `GitHub::Prioritizable::SBT`
        Dual = new

        # Determine order of items by reading from new `priority_numerator`/`priority_denominator` columns from
        # `GitHub::Prioritizable::SBT`, and only write to those columns also
        Current = new
      end

      sig { returns(T::Boolean) }
      def write_to_legacy_column?
        case self
        when Legacy, Dual
          true
        else
          false
        end
      end

      sig { returns(T::Boolean) }
      def write_to_current_columns?
        case self
        when Dual, Current
          true
        else
          false
        end
      end
    end

    # Public: Have this context's contents been properly prioritized?
    #
    # If this returns false, it's because there's some bad priority data in
    # this context, and we should avoid further prioritizations so we don't
    # exacerbate the issue.
    #
    # Returns a boolean.
    sig { params(association: T.nilable(Symbol)).returns(T::Boolean) }
    def prioritized?(association: nil)
      key = build_key_from_association(association)

      return true unless priority_counter_cache_for_association(key: key)

      # Ensure we're using the freshest cached value
      reload if persisted?

      # There are no items to prioritize
      return true if priority_count(key: key) == 0

      # Check for associated items that haven't been prioritized
      if priority_assoc(key: key).size == read_attribute(priority_counter_cache_for_association(key: key))
        true
      else
        GitHub.dogstats.increment("#{stat_prefix}.bad_priority")
        Failbot.report(
          StandardError.new("GitHub::Prioritizable: bad priority for #{self.class.name}"),
          { "code.namespace" => self.class.name, "gh.context.id" => self.id }
        )
        false
      end
    end

    sig { params(association: T.nilable(Symbol)).returns(T::Boolean) }
    def prioritizable?(association: nil)
      key = build_key_from_association(association)
      priority_count(key: key) < GitHub::Prioritizable::MAXIMUM_PRIORITIZABLE_ITEM_COUNT
    end

    sig do
      type_parameters(:E)
      .params(
        dependent: T.all(T.type_parameter(:E), ApplicationRecord::Base),
        before: T.nilable(T.type_parameter(:E)),
        after: T.nilable(T.type_parameter(:E)),
        position: T.nilable(Symbol),
        dual_write: T.nilable(GitHub::Prioritizable::SBT::Context::PendingPriorityUpdate)
      )
      .returns(T.any(FalseClass, T.type_parameter(:E)))
    end
    def prioritize_dependent!(dependent, before: nil, after: nil, position: nil, dual_write: nil)
      Instrumentation.track_time(
        "#{stat_prefix}.prioritize_dependent.dist.time",
        tags: ["dual_write:#{!!dual_write}", "dependent:#{dependent.class.name&.underscore || 'unknown'}"]) do

        key = nil
        if T.unsafe(self).multiple_associations
          key = dependent.class.name
          association = prioritizes_association_for_association(key: key).to_sym
        end
        record_to_prioritize = priority_finder(dependent: dependent, key: key).first
        if !prioritizable?(association: association)
          # If this context has reached the maximum number of priorities, we only
          # want to allow moving priorities around, not adding new.
          return false unless record_to_prioritize.present?
        end
        record_to_prioritize ||= priority_assoc(key: key).new(prioritizable_for_association(key: key).to_sym => dependent)

        record_to_prioritize.reprioritize(before:, after:, position:, in_context: self, association:, dual_write:)
      end
    end

    sig { params(dependent: ApplicationRecord::Base).void }
    def deprioritize_dependent(dependent)
      key = T.unsafe(self).multiple_associations ? dependent.class.name : nil

      return unless dependent = priority_finder(dependent: dependent, key: key).first

      Instrumentation.track_time("#{stat_prefix}.deprioritize_dependent.dist.time") do
        dependent.destroy
        T.unsafe(self).notify_subscribers if respond_to?(:notify_subscribers)
      end
    end

    sig { params(association: T.nilable(Symbol), block: T.proc.void).void }
    def lock_for_rebalance(association: nil, &block)
      validate_association(association)
      key = build_key_from_association(association)
      GitHub.kv.set(locked_for_rebalance_key(key: key), true.to_s) # rubocop:todo GitHub/DoNotUseGlobalKv
      yield
    ensure
      GitHub.kv.del(locked_for_rebalance_key(key: key)) # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    sig { params(association: T.nilable(Symbol)).returns(T::Boolean) }
    def locked_for_rebalance?(association: nil)
      validate_association(association)
      key = build_key_from_association(association)
      !!GitHub.kv.get(locked_for_rebalance_key(key: key)).value { false } # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    sig { overridable.params(association: T.nilable(Symbol)).returns(RebalanceMode) }
    def rebalance_mode(association:)
      RebalanceMode::Legacy
    end

    sig { overridable.params(association: T.nilable(Symbol)).returns(T.nilable(T.class_of(ApplicationJob))) }
    def rebalance_job_class(association: nil)
      nil
    end

    sig do
      params(
        actor_id: Integer,
        association: T.nilable(Symbol)
      ).void
    end
    def rebalance(actor_id: GitHub.context[:actor_id], association: nil)
      validate_association(association)
      rebalance_job_class(association:)&.perform_later(id, actor_id)
    end

    sig { params(association: T.nilable(Symbol), mode: T.nilable(RebalanceMode)).void }
    def rebalance!(association: nil, mode: nil)
      key = build_key_from_association(association)
      mode = rebalance_mode(association:) if mode.nil?
      GitHub.dogstats.increment("#{stat_prefix}.rebalance_count", tags: rebalance_telemetry_tags(association:, mode:))

      lock_for_rebalance(association: association) do
        Instrumentation.track_time("#{stat_prefix}.rebalance_time.dist.time", tags: rebalance_telemetry_tags(association:, mode:)) do
          ordered_dependents = (
            case mode
            when RebalanceMode::Current
              # Ordinarily, we would retrieve the prioritized list of items via the `SBT::Context#prioritized_scope`
              # method. However, that method is overridable so that integrators can add additional scopes to it.
              # Those scopes might filter out some items from the collection, but here we need to guarantee that
              # we rebalance all items in the collection. As a result, we access the association directly rather than
              # via `prioritized_scope`.
              public_send(T.must(association)).order(virtual_priority: :asc).to_a # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
            else
              T.unsafe(priority_assoc(key: key)).by_priority.reverse
            end
          )

          # Calculate the size that the gap between each dependent's priority
          # should be.
          #
          # We should have one more gap than we have dependents, so we can have
          # a gap before the lowest priority and another after the highest
          # priority.
          #
          # We also want each gap to be as large as possible, so we have as
          # much room between it and the next dependent as possible.
          gap_size = (GitHub::Prioritizable::MAX_PRIORITY_VALUE / (ordered_dependents.size + 1)).floor

          transaction do
            # Get the dependents out of each others' ways.
            priority_reset_updates = { priority: nil }
            if mode.write_to_current_columns?
              priority_reset_updates.merge!(priority_numerator: nil, priority_denominator: nil)
            end
            priority_assoc(key:).update_all(priority_reset_updates)

            ordered_dependents.each_with_index do |dependent, i|
              prioritization_updates = {}

              if mode.write_to_legacy_column?
                prioritization_updates.merge!({ priority: gap_size * (i + 1) })
              end

              if mode.write_to_current_columns?
                # Assign new priorities according to the sequence 1/2, 3/2, 5/2, etc.
                # Adapted from https://wiki.postgresql.org/wiki/User-specified_ordering_with_fractions
                new_rational_priority = Rational(2 * i + 1, 2)

                prioritization_updates.merge!(
                  priority_numerator: new_rational_priority.numerator,
                  priority_denominator: new_rational_priority.denominator,
                )
              end

              dependent.throttle { dependent.update_columns(prioritization_updates) }
            end

            instrument_context_rebalanced if mode.write_to_current_columns?
          end
        end
      end
    end

    # This method needs to be public in order for instrumentation to be able to access it
    sig do
      type_parameters(:E)
      .params(
        args: T.all(T.type_parameter(:E), ApplicationRecord::Base),
        kwargs: T.nilable(
            T.any(
            T.type_parameter(:E),
            Symbol,
            GitHub::Prioritizable::SBT::Context::PendingPriorityUpdate
          )
        )
      ).returns(T::Hash[String, T.untyped])
    end
    def trace_tags(*args, **kwargs)
      dual_write = T.cast(kwargs[:dual_write], T.nilable(GitHub::Prioritizable::SBT::Context::PendingPriorityUpdate))

      {
        "context_id" => self.id,
        "context_type" => self.class.name,
        "dependent_id" => args.first&.id,
        "dual_write" => dual_write.present?,
      }.compact
    end

    private

    IGNORED_CALLERS = T.let(
      [
        "active_record",
        "active_support",
        "opentelemetry",
        "lib/github/tracing",
      ].freeze,
      T::Array[String]
    )

    sig { params(stack: T::Array[String]).returns(T::Array[String]) }
    private def filter_call_stack(stack)
      stack.reject { |c| IGNORED_CALLERS.any? { |u| c.include?(u) } }
    end

    sig { void }
    def instrument_context_rebalanced
      GlobalInstrumenter.instrument "prioritizable.context_rebalanced", {
        actor_id: GitHub.context[:actor_id],
        context_id: self.id,
        context_type: self.class.name,
        performed_at: Time.now,
      }
    end

    sig { params(key: T.nilable(String)).returns(Integer) }
    def priority_count(key: nil)
      if priority_counter_cache_for_association(key: key) # e.g. Milestone#open_issue_count
        read_attribute(priority_counter_cache_for_association(key: key))
      else
        priority_assoc(key: key).where.not(priority: nil).size
      end
    end

    sig { params(key: T.nilable(String)).returns(ActiveRecord::Relation) }
    def priority_assoc(key:)
      association(prioritizes_with_for_association(key: key)).scope
    end

    sig { params(key: T.nilable(String)).returns(T.nilable(T.any(String, Symbol))) }
    def priority_counter_cache_for_association(key: nil)
      return T.unsafe(self).priority_counter_cache unless key != nil

      validate_key(key)
      send("priority_counter_cache#{key}")
    end

    sig { params(key: T.nilable(String)).returns(T.any(String, Symbol)) }
    def prioritizes_with_for_association(key: nil)
      return T.unsafe(self).prioritizes_with unless key != nil

      validate_key(key)
      send("prioritizes_with#{key}")
    end

    sig { params(key: T.nilable(String)).returns(T.any(String, Symbol)) }
    def prioritizable_for_association(key: nil)
      return T.unsafe(self).prioritizable unless key != nil

      validate_key(key)
      send("prioritizable#{key}")
    end

    sig { params(key: T.nilable(String)).returns(T.any(String, Symbol)) }
    def prioritizes_association_for_association(key: nil)
      return T.unsafe(self).prioritizes_association unless key != nil
      validate_key(key)
      send("prioritizes_association#{key}")
    end

    sig { params(key: T.nilable(String)).void }
    def validate_key(key)
      valid_keys = (supported_associations || []).map do |item|
        T.unsafe(self.class).reflect_on_association(item).klass.name
      end

      if !valid_keys.include?(key)
        raise InvalidAssociation
      end
    end

    sig { params(association: T.nilable(Symbol)).void }
    def validate_association(association)
      raise InvalidAssociation unless association.nil? || supported_associations&.include?(association)
    end

    sig { returns(T.nilable(T::Array[Symbol])) }
    def supported_associations
      self.class.class_variable_get(:@@prioritized_associations)
    end

    sig { params(association: T.nilable(Symbol)).returns(T.nilable(String)) }
    def build_key_from_association(association)
      T.unsafe(self).multiple_associations && association != nil ? T.unsafe(self.class).reflect_on_association(association).klass.name : nil
    end

    sig do
      params(dependent: ApplicationRecord::Base, key: T.nilable(String))
      .returns(T.any(T::Array[ApplicationRecord::Base], ActiveRecord::Relation))
    end
    def priority_finder(dependent:, key: nil)
      prioritizer_klass = association(prioritizes_with_for_association(key: key)).klass

      if dependent.kind_of?(prioritizer_klass)
        return Array.wrap(dependent)
      end

      reflection = prioritizer_klass.reflect_on_association(prioritizable_for_association(key: key).to_sym)

      foreign_key = reflection.foreign_key

      options = { foreign_key => dependent.id }

      if reflection.options[:polymorphic]
        foreign_key_type = foreign_key.gsub(/_id\Z/, "_type")
        options[foreign_key_type] = dependent.class.name
      end

      priority_assoc(key: key).where(options)
    end

    sig { params(key: T.nilable(String)).returns(String) }
    def locked_for_rebalance_key(key: nil)
      if key != nil
        return "#{stat_prefix}:#{key}:locked_for_rebalance:#{id}"
      end
      "#{stat_prefix}:locked_for_rebalance:#{id}"
    end

    sig { returns(String) }
    def stat_prefix
      self.class.name&.underscore || "unidentified_prioritizable_context"
    end

    sig do
      params(
        association: T.nilable(Symbol),
        mode: RebalanceMode,
      ).returns(T::Array[String])
    end
    def rebalance_telemetry_tags(association:, mode:)
      {
        context: self.class.name,
        association:,
        mode: mode.serialize,
      }.compact.map { |key_and_value|  key_and_value.join(":") }
    end

    module ClassMethods
      extend T::Helpers

      requires_ancestor { Kernel }

      # By default the context supports a single prioritized association. To use multiple prioritized associations within the same context,
      # please ensure the following:
      #
      # 1. Pass `multiple_associations: true` in `prioritizes` for every prioritized association in the context
      #    Example: (in `memex_project`)
      #             prioritizes :memex_project_items, with: :memex_project_items, multiple_associations: true
      #             prioritizes :memex_project_views, with: :memex_project_views, multiple_associations: true
      # 2. Access the following public methods by passing in the symbol for the association:
      #    a. prioritized?(association: null)
      #       Example: memex_project.prioritized(association: :memex_project_items)
      #    b. prioritizable?(association: nil)
      #    c. locked_for_rebalance?(association: nil)
      #    d. rebalance!(association: nil)
      #
      # 3. When implementing `rebalance_job_class(association: nil)` use the association to determine which job class to return
      #
      # 4. To enable validation, define the class variable `prioritized_associations` in the prioritized context.
      #    Example: `@@prioritized_associations ||= [:memex_project_items, :memex_project_views]` in `memex_project`
      #
      sig do
        params(
          dependents: Symbol,
          with: Symbol,
          counter_cache: T.nilable(Symbol),
          inverse_of: T.nilable(Symbol),
          conditions: T.nilable(String),
          multiple_associations: T::Boolean,
          source: T.nilable(Symbol)
        ).void
      end
      def prioritizes(dependents, with:, counter_cache: nil, inverse_of: nil, conditions: nil, multiple_associations: false, source: nil)
        key = nil

        # If we are supporting multiple associations, suffix each method with a `key`
        # The `key` is built from the association using `build_key_from_association`
        # Ex: For :memex_project_items, the `key` will be `MemexProjectItem`
        # Helper methods are defined to access the right method in the case of multiple associations
        # 1. priority_count(key: nil)
        # 2. priority_counter_cache_for_association(key: nil)
        # 3. prioritizes_with_for_association(key: nil)
        # 4. prioritizes_association_for_association(key: nil)
        # 5. priority_assoc(key:)
        # All existing references in code to the single association method use the helper methods now

        if multiple_associations
          key = T.unsafe(self).reflect_on_association(dependents).klass.name
          define_singleton_method(:multiple_associations)                 { true }
          define_singleton_method("prioritizable#{key}".to_sym)           { dependents.to_s.singularize }
          define_singleton_method("prioritizes_association#{key}".to_sym) { dependents }
          define_singleton_method("prioritizes_with#{key}".to_sym)        { with }
          define_singleton_method("priority_counter_cache#{key}".to_sym)  { counter_cache }

          T.unsafe(self).define_method(:multiple_associations)                 { true }
          T.unsafe(self).define_method("prioritizable#{key}".to_sym)           { dependents.to_s.singularize }
          T.unsafe(self).define_method("prioritizes_association#{key}".to_sym) { dependents }
          T.unsafe(self).define_method("prioritizes_with#{key}".to_sym)        { with }
          T.unsafe(self).define_method("priority_counter_cache#{key}".to_sym)  { counter_cache }
        else
          define_singleton_method(:multiple_associations)   { false }
          define_singleton_method(:prioritizable)           { dependents.to_s.singularize }
          define_singleton_method(:prioritizes_association) { dependents }
          define_singleton_method(:prioritizes_with)        { with }
          define_singleton_method(:priority_counter_cache)  { counter_cache }

          T.unsafe(self).define_method(:multiple_associations)   { false }
          T.unsafe(self).define_method(:prioritizable)           { dependents.to_s.singularize }
          T.unsafe(self).define_method(:prioritizes_association) { dependents }
          T.unsafe(self).define_method(:prioritizes_with)        { with }
          T.unsafe(self).define_method(:priority_counter_cache)  { counter_cache }
        end

        if T.unsafe(self).reflect_on_association(dependents)
          prioritization_class = T.unsafe(self).reflect_on_association(with).klass
          association_class    = T.unsafe(self).reflect_on_association(dependents).klass
          association_params   = if dependents == with
            dependents = dependents.to_s
            { foreign_key: T.unsafe(self).reflections[dependents].foreign_key.to_sym }
          else
            { through: with.to_sym }
          end

          # :source is not valid with Rails 6.1 unless a :through option
          # is specified.
          association_params[:source] = source || dependents.to_s.singularize.to_sym if association_params[:through]
          association_params[:inverse_of] = inverse_of.to_sym if inverse_of

          association_params[:class_name] = association_class.name
          query_modifier = if conditions.present?
            -> { T.unsafe(self).where(conditions).order("#{prioritization_class.table_name}.priority DESC") }
          else
            -> { T.unsafe(self).order("#{prioritization_class.table_name}.priority DESC") }
          end

          T.unsafe(self).has_many :"prioritized_#{dependents}", query_modifier, **association_params
        end
      end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
