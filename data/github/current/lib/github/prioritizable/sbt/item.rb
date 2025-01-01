# typed: strict
# frozen_string_literal: true

module GitHub
  module Prioritizable
    module SBT
      # This defines an interface that be included in an `ActiveRecord` model that represents an item that can be kept
      # in a user-defined order within a particular `GitHub::Prioritizable::SBT::Context` container.
      #
      # This module assumes the `ActiveRecord` model that includes it has an associated database table with the
      # following columns and index:
      #
      #   `priority_numerator` int DEFAULT NULL
      #   `priority_denominator` int DEFAULT NULL
      #   `virtual_priority` decimal(24,16) GENERATED ALWAYS AS ((cast(`priority_numerator` as decimal(24,16)) / `priority_denominator`)) VIRTUAL
      #
      # The names of each column must be exactly those written above.
      #
      # The precision and scale of the `virtual_priority` column can be configured to suit your needs, so long as you
      # override the `virtual_priority_precision` class method. We recommend the above configuration as a suitable
      # default for a container that holds up to 100,000 items.
      #
      # Additionally, the database should have a unique index on the container ID column and the `virtual_priority`
      # column. For an example, please see:
      #   https://github.com/github/github/blob/0be172981ea003521f6e75910acb327f33fc2b75/db/memex-structure.sql#L101
      #
      # For example usage, please see `GitHub::Prioritizable::SBT::Context`.
      module Item
        extend T::Sig
        extend T::Helpers
        include Kernel

        requires_ancestor { ApplicationRecord::Base }

        DEFAULT_VIRTUAL_PRIORITY_MAX_DIGITS_BEFORE_DECIMAL_POINT = 8

        # Returns the priority value for this item.
        #
        # This method should be avoided; it is only provided for backwards compatibility. Instead, callers should
        # retrieve sorted lists via `Prioritizable::SBT::Context.prioritized_scope`, and should otherwise consider the
        # specific priority value on an Item as private and opaque.
        sig { overridable.returns(T.nilable(Numeric)) }
        def priority_value
          T.unsafe(self).virtual_priority
        end

        # Returns the priority value of the this item.
        sig { returns(T.nilable(Rational)) }
        def rational_priority
          numerator = T.unsafe(self).priority_numerator
          denominator = T.unsafe(self).priority_denominator
          Rational(numerator, denominator) if numerator && denominator
        end

        # Sets the priority value of the this item without persisting that new value to the database.
        sig { params(value: T.nilable(Rational)).void }
        def rational_priority=(value)
          T.unsafe(self).priority_numerator = value&.numerator
          T.unsafe(self).priority_denominator = value&.denominator
        end

        # Persists a new priority value for this item to the database.
        sig { params(value: T.nilable(Rational)).void }
        def update_rational_priority(value)
          update_columns(
            priority_numerator: value&.numerator,
            priority_denominator: value&.denominator,
          )
        end

        # Returns a String repesentation of this item's priority.
        #
        # This is useful for storing the priority in a system that supports strings but does not support arbitrary
        # precision decimal numbers (e.g. Elasticsearch).
        sig { returns(T.nilable(String)) }
        def stringified_virtual_priority
          return unless decimal_priority = T.let(T.unsafe(self).virtual_priority, T.nilable(BigDecimal))

          # BigDecimal#to_s, which we use below, converts a number with no integer part (e.g. .25) into a string with
          # a leading zero (i.e. "0.25"). To account for that, we take the max of the number of non-zero digits
          # ahead of the decimal point and 1.
          digits_before_decimal_point = [decimal_priority.precision - decimal_priority.scale, 1].max

          # This pads each number with just enough zeros to line up the decimal points. That means that the more
          # digits the number has before the decimal point, the fewer zeros we need to add to the front of it. All of
          # the digits after the decimal point are preserved.
          #
          # EXAMPLES:
          #
          #   0.25 => "000.25"
          #   2.5  => "002.5"
          #   10.5 => "010.5"
          required_padding = self.class.virtual_priority_max_digits_before_decimal_point - digits_before_decimal_point
          ("0" * required_padding) + decimal_priority.to_s
        end

        module ClassMethods
          extend T::Sig

          # Returns the maximum number of digits allowed before the decimal point in the `virtual_priority` column of
          # the database.
          #
          # This method should be overridden to return whatever this value is for the particular  database table that
          # backs the model that includes this interface.
          #
          # EXAMPLE:
          #
          #   Given this definition for a decimal virtual priority column:
          #
          #     `virtual_priority` decimal(24,16) GENERATED ALWAYS AS ((cast(`priority_numerator` as decimal(24,16)) / `priority_denominator`)) VIRTUAL,
          #
          #   This method should return 8 (because 24 - 16 = 8).
          #
          sig { overridable.returns(Integer) }
          def virtual_priority_max_digits_before_decimal_point
            DEFAULT_VIRTUAL_PRIORITY_MAX_DIGITS_BEFORE_DECIMAL_POINT
          end
        end

        mixes_in_class_methods(ClassMethods)
      end
    end
  end
end
