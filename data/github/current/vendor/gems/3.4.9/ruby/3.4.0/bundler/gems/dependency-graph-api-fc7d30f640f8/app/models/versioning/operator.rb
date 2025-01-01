module Versioning
  class Operator
    @@registered_operators = {}

    class << self
      attr_accessor :op

      def register(op)
        @op = op
        # this keeps a hash of the operator to the class that represents it
        @@registered_operators[op] = self
      end

      def parse(operator)
        op = operator.to_s.strip.freeze
        klass = @@registered_operators[op] || ::Versioning::Operator::Null
        klass.new
      end
    end

    def to_s
      self.class.op
    end

    def ==(other)
      self.class == other.class
    end

    # Implemented in the subclasses
    def inclusive?
      false
    end

    def exact?
      false
    end

    def lower_bound?
      false
    end

    def upper_bound?
      false
    end

    def vary?(component, most_specified)
      false
    end

    def present?
      true
    end

    def blank?
      !present?
    end

    class Null < Operator
      def present?
        false
      end
    end

    class Equal < Operator
      register "="

      def inclusive?
        true
      end

      def exact?
        true
      end

      def lower_bound?
        true
      end

      def upper_bound?
        true
      end
    end

    class Greater < Operator
      register ">"

      def lower_bound?
        true
      end
    end

    class GreaterEquals < Operator
      register ">="

      def inclusive?
        true
      end

      def lower_bound?
        true
      end
    end

    class Less < Operator
      register "<"

      def upper_bound?
        true
      end
    end

    class LessEquals < Operator
      register "<="

      def inclusive?
        true
      end

      def upper_bound?
        true
      end
    end

    class Tilde < Operator
      register "~"

      def inclusive?
        true
      end

      def lower_bound?
        true
      end

      def upper_bound?
        true
      end

      def vary?(component, most_specified)
        # According to NPM: "Allows patch-level changes if a minor version is specified
        # on the comparator. Allows minor-level changes if not."
        if most_specified == :major
          [:minor, :patch].include? component
        else
          component == :patch
        end
      end
    end

    class Caret < Operator
      register "^"

      def inclusive?
        true
      end

      def lower_bound?
        true
      end

      def upper_bound?
        true
      end

      def vary?(component, most_specified)
        # caret means vary minor and patch. It's an NPM thing
        [:minor, :patch].include? component
      end
    end

    class TildeWakka < Operator # spell?
      register "~>"

      def inclusive?
        true
      end

      def lower_bound?
        true
      end

      def upper_bound?
        true
      end

      def vary?(component, most_specified)
        # Vary the most specified component and any unspecified ones
        case component
        when :minor
          [:major, :minor].include? most_specified
        when :patch
          [:major, :minor, :patch].include? most_specified
        when :additional_fields
          # additional fields are special and we only vary them when they are included
          most_specified == :additional_fields
        end
      end
    end
  end
end
