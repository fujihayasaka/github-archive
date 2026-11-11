# typed: strict
# frozen_string_literal: true

module GH
  class DualWriter
    # Base class for dual-write operation handlers. Subclasses implement
    # `perform_secondary_write` for the specific operation (create, update, etc.).
    #
    # Handlers are instantiated with a secondary class and stage, then invoked
    # via `#call`.
    class Handler
      extend T::Helpers
      abstract!

      autoload :Create, "gh/dual_writer/handler/create"

      sig { returns(T.class_of(ActiveRecord::Base)) }
      attr_reader :secondary_class

      sig { returns(Symbol) }
      attr_reader :stage

      sig { params(secondary_class: T.class_of(ActiveRecord::Base), stage: Symbol).void }
      def initialize(secondary_class:, stage:)
        @secondary_class = secondary_class
        @stage = stage
      end

      sig do
        type_parameters(:T)
          .params(subject: ActiveRecord::Base, block: T.proc.returns(T.type_parameter(:T)))
          .returns(T.type_parameter(:T))
      end
      def call(subject, &block)
        case @stage
        when WriteStages::TRACK
          primary_write(&block)
        when WriteStages::BEST_EFFORT
          result = primary_write(&block)
          secondary_write(subject)
          result
        else
          raise ArgumentError, "Unknown dual write stage: #{@stage}"
        end
      end

      private

      sig { returns(T::Array[String]) }
      def base_tags
        @base_tags ||= T.let([
          "model:#{@secondary_class.name}",
          "stage:#{@stage}",
          "operation:#{self.class.name&.demodulize&.downcase}"
        ], T.nilable(T::Array[String]))
      end

      sig do
        type_parameters(:T)
          .params(block: T.proc.returns(T.type_parameter(:T)))
          .returns(T.type_parameter(:T))
      end
      def primary_write(&block)
        result = block.call
        GitHub.dogstats.increment("gh.dual_writer.primary_write", tags: base_tags)
        result
      end

      sig { params(subject: ActiveRecord::Base).void }
      def secondary_write(subject)
        GitHub.dogstats.distribution_time("gh.dual_writer.secondary_write.duration", tags: base_tags) do
          perform_secondary_write(subject)
        end
        GitHub.dogstats.increment("gh.dual_writer.secondary_write", tags: base_tags + ["success:true"])
      rescue => error
        GitHub.dogstats.increment("gh.dual_writer.secondary_write", tags: base_tags + ["success:false", "error_class:#{error.class.name}"])
      end

      sig { abstract.params(subject: ActiveRecord::Base).void }
      def perform_secondary_write(subject); end
    end
  end
end
