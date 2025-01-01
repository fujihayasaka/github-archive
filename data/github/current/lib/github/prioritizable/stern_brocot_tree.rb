# typed: strict
# frozen_string_literal: true

module GitHub
  module Prioritizable
    # This class represents the Stern-Brocot tree, an infinite binary search tree that contains all rational numbers:
    # https://en.wikipedia.org/wiki/Stern%E2%80%93Brocot_tree
    #
    # This tree can be used to efficiently find a rational number in between two bounds. We expose that functionality
    # via the `infer_intermediate` method, which forms the basis of the algorithm we use to allow users to define
    # the order of a set of items in a given context (e.g. the order of a set of Issues in a Project).
    #
    # This article describes why the Stern-Brocot tree is a good fit for user-defined ordering:
    # - https://begriffs.com/posts/2018-03-20-user-defined-order.html
    #
    # This video provides an excellent explanation of the math behind the Stern-Brocot tree:
    # - https://www.youtube.com/watch?v=CiO8iAYC6xI
    #
    # These two reference implementations informed this one:
    # - https://wiki.postgresql.org/wiki/User-specified_ordering_with_fractions
    # - https://github.com/begriffs/pg_rational/blob/eafcf743ba8c6a180bba9cbb1627db5dc0b88f4b/pg_rational.c#L352
    #
    # USAGE:
    #
    #   SternBrocotTree.new.infer_intermediate(lower_bound: 0.5r, upper_bound: 1r)
    class SternBrocotTree
      autoload :Traversal, "github/prioritizable/stern_brocot_tree/traversal"
      autoload :Node, "github/prioritizable/stern_brocot_tree/node"

      extend T::Sig
      include Kernel
      include GitHub::Tracing

      # The root value of the Stern-Brocot tree (i.e. 1/1).
      ROOT = T.let(1r, Rational)

      sig { void }
      def initialize
        @lower_bound_span_attribute = T.let("0", String)
        @upper_bound_span_attribute = T.let("∞", String)
        @traversal_depth = T.let(0, Integer)
        @infer_intermediate_started_at = T.let(nil, T.nilable(Numeric))
      end

      # Returns a value in between the given bounds.
      #
      # USAGE:
      #
      #   GitHub::Prioritizable::SternBrocotTree.new.infer_intermediate(lower_bound: 0.5r, upper_bound: 1r)
      #
      # @raises ArgumentError if the bounds are not specified correctly
      sig { params(lower_bound: Rational, upper_bound: T.nilable(Rational)).returns(Rational) }
      def infer_intermediate(lower_bound: 0r, upper_bound: nil)
        @infer_intermediate_started_at = GitHub::Dogstats.monotonic_time

        raise ArgumentError.new("Lower bound #{lower_bound} must be non-negative") if lower_bound < 0
        raise ArgumentError.new("Upper bound #{upper_bound} must be positive") if upper_bound && upper_bound < 0
        if upper_bound && lower_bound >= upper_bound
          raise ArgumentError.new("Lower bound #{lower_bound} must be strictly less than upper bound #{upper_bound}")
        end

        @lower_bound_span_attribute = lower_bound.to_s
        @upper_bound_span_attribute = upper_bound.to_s.presence || "∞"

        if mathematically_adjacent?(lower_bound, upper_bound)
          # This is a special case in which we know that the mediant of the two bounds is already an appropriate
          # intermediate, hence we can improve efficiency by returning immediately rather than walking the tree
          # from the root.
          return mediant(lower_bound, upper_bound, [1, 0])
        end

        # This loop traverses the Stern-Brocot tree from the root downards until it finds a node that falls strictly
        # within the required bounds.
        closest_smaller_ancestor = T.let(nil, T.nilable(Rational))
        closest_larger_ancestor = T.let(nil, T.nilable(Rational))
        current = ROOT
        loop do
          @traversal_depth += 1

          if gt?(current, lower_bound) && lt?(current, upper_bound)
            # If the current node is within the required bounds then we're done 🎉
            return current
          elsif lte?(current, lower_bound)
            # The current node is less than the lower bound,
            # so we traverse down to the right child to get a larger number.
            closest_smaller_ancestor = current
            current = larger_child(current, closest_larger_ancestor)
          elsif gte?(current, upper_bound)
            # The current node is greater than the upper bound,
            # so we traverse down to the left child to get a smaller number.
            closest_larger_ancestor = current
            current = smaller_child(current, closest_smaller_ancestor)
          else
            # This should be impossible.
            raise "Value #{current} could not be compared to interval (#{lower_bound}, #{upper_bound})"
          end
        end
      end

      # Returns the root node of a Stern Brocot tree with depth equal to `max_depth`.
      #
      # This method is not part of the public interface because we don't use it in production code. However, it is
      # useful for tests and local development, because it makes the structure of the tree observable.
      sig do
        params(
          max_depth: Integer,
          root: Rational,
          closest_smaller_ancestor: T.nilable(Rational),
          closest_larger_ancestor: T.nilable(Rational),
          depth: Integer
        )
        .returns(Node)
      end
      private def build_tree(
          max_depth:,
          root: GitHub::Prioritizable::SternBrocotTree::ROOT,
          closest_smaller_ancestor: nil,
          closest_larger_ancestor: nil,
          depth: 0)
        tree = Node.new(value: root)
        return tree if depth >= max_depth

        tree.left_child = build_tree(
          max_depth:,
          root: smaller_child(root, closest_smaller_ancestor),
          closest_smaller_ancestor:,
          closest_larger_ancestor: root,
          depth: depth + 1
        )
        tree.right_child = build_tree(
          max_depth:,
          root: larger_child(root, closest_larger_ancestor),
          closest_larger_ancestor:,
          closest_smaller_ancestor: root,
          depth: depth + 1
        )

        tree
      end

      # Return the larger (right) child of the given node.
      sig { params(node: Rational, closest_larger_ancestor: T.nilable(Rational)).returns(Rational) }
      private def larger_child(node, closest_larger_ancestor)
        mediant(node, closest_larger_ancestor, [1, 0])
      end

      # Return the smaller (left) child of the given node.
      sig { params(node: Rational, closest_smaller_ancestor: T.nilable(Rational)).returns(Rational) }
      private def smaller_child(node, closest_smaller_ancestor)
        mediant(node, closest_smaller_ancestor, [0, 1])
      end

      # Returns the mediant of a fraction a/c and another fraction b/d, which is defined as (a + b)/(c + d).
      sig { params(first: Rational, second: T.nilable(Rational), fallback: T::Array[Integer]).returns(Rational) }
      private def mediant(first, second, fallback)
        Rational(
          first.numerator + (second&.numerator || T.must(fallback[0])),
          first.denominator + (second&.denominator || T.must(fallback[1]))
        )
      end

      # Returns true if the two nodes are "adjacent" to each other, meaning that we can immediately
      # calculate an intermediate value by taking the mediant of the two nodes without walking the tree.
      #
      # Two fractions a/b and c/d, that are both in reduced form, are adjacent when ad - bc = +/- 1.
      #
      # If ad - bc is strictly -1, and ad is the lesser of the two fractions, then the mediant of the two
      # fractions is the value that we would find by walking the tree from the root.
      #
      # For a deeper explanation of adjacency, please see:
      # https://youtu.be/CiO8iAYC6xI?t=1011&feature=shared
      sig { params(r1: Rational, r2: T.nilable(Rational)).returns(T::Boolean) }
      private def mathematically_adjacent?(r1, r2)
        a = r1.numerator
        b = r1.denominator
        c = r2&.numerator || 1
        d = r2&.denominator || 0

        ad = a * d
        bc = b * c

        ad - bc == -1
      end

      # This allows us to do a comparison between two rational numbers, where if the second number is omitted it is
      # replaced by the sentinel (1/0), which represents infinity.
      #
      # Ordinarily this would be implemented as an extension to the Rational class, but defining it here is expedient.
      #
      # Adapted from:
      # https://github.com/begriffs/pg_rational/blob/eafcf743ba8c6a180bba9cbb1627db5dc0b88f4b/pg_rational.c#L558-L569
      sig { params(r1: Rational, r2: T.nilable(Rational)).returns(Integer) }
      private def compare(r1, r2)
        a = r1.numerator
        b = r1.denominator
        c = r2&.numerator || 1
        d = r2&.denominator || 0

        ad = a * d
        cb = c * b

        (ad > cb ? 1 : 0) - (ad < cb ? 1 : 0)
      end

      sig { params(a: Rational, b: T.nilable(Rational)).returns(T::Boolean) }
      private def gt?(a, b)
        compare(a, b) > 0
      end

      sig { params(a: Rational, b: T.nilable(Rational)).returns(T::Boolean) }
      private def lt?(a, b)
        compare(a, b) < 0
      end

      sig { params(a: Rational, b: T.nilable(Rational)).returns(T::Boolean) }
      private def eq?(a, b)
        compare(a, b) == 0
      end

      sig { params(a: Rational, b: T.nilable(Rational)).returns(T::Boolean) }
      private def gte?(a, b)
        gt?(a, b) || eq?(a, b)
      end

      sig { params(a: Rational, b: T.nilable(Rational)).returns(T::Boolean) }
      private def lte?(a, b)
        lt?(a, b) || eq?(a, b)
      end

      # Rough size categories for the number of steps required to find an intermediate value.
      TRAVERSAL_DEPTH_BUCKETS = T.let(
        [
          [10.0, "xs"],
          [100.0, "s"],
          [1000.0, "m"],
          [10000.0, "l"],
          [Float::INFINITY, "xl"],
        ],
        T::Array[T::Array[T.any(Float, String)]]
      )

      # This method is conceptually private, but cannot actually be marked as private due to its use in the
      # `trace_method` macro below.
      sig { params(span: OpenTelemetry::Trace::Span, result: Rational).void }
      def instrument_infer_intermediate(span, result)
        unless @infer_intermediate_started_at.nil?
          traversal_depth_bucket =
            T.must(
              TRAVERSAL_DEPTH_BUCKETS.find { |(upper_bound, _)| @traversal_depth <= T.cast(upper_bound, Float) }
            ).second

          GitHub.dogstats.distribution(
            "github.prioritizable.stern_brocot_tree.infer_intermediate",
            GitHub::Dogstats.duration(@infer_intermediate_started_at),
            tags: [
              "used_default_lower_bound:#{@lower_bound_span_attribute == '0/1'}",
              "used_default_upper_bound:#{@upper_bound_span_attribute == '∞'}",
              "traversal_depth_bucket:#{traversal_depth_bucket}",
            ]
          )
        end

        span.add_attributes({
          "lower_bound" => @lower_bound_span_attribute,
          "upper_bound" => @upper_bound_span_attribute,
          "result" => result.to_s,
          "traversal_depth" => @traversal_depth,
        })
      end

      trace_method(
        :infer_intermediate,
        span_annotator: -> (tree, span, _context, result) { tree.instrument_infer_intermediate(span, result) }
      )
    end
  end
end
