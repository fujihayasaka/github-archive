# typed: strict
# frozen_string_literal: true

module GitHub
  module Prioritizable
    module SBT
      # This module defines a namespace for classes that are used to specify where a
      # `GitHub::Prioritizable::SBT::Item` should be placed within its `GitHub::Prioritizable::SBT::Context`.
      #
      # Together, the classes in this module define an exclusive enum, so any variable type that is declared as
      # Position can take on the value of exactly one of the classes contained in this module. For more details as to
      # how this works, see https://sorbet.org/docs/sealed.
      #
      # For usage, see `GitHub::Prioritizable::Context#prioritize!`.
      module Position
        extend T::Helpers
        sealed!

        # Instructs us to give an Item the highest priority value in the Context.
        class Top
          include Position
        end

        # Instructs us to give an Item the lowest priority value in the Context.
        class Bottom
          include Position
        end

        # Instructs us to give an Item a priority that is immediately
        # higher than the item with which this class is initialized.
        class HigherThan
          include Position

          sig { returns(Item) }
          attr_reader :item

          sig { params(item: Item).void }
          def initialize(item)
            @item = T.let(item, Item)
          end
        end

        # Instructs us to give an Item a priority that is immediately
        # lower than the item with which this class is initialized.
        class LowerThan
          include Position

          sig { returns(Item) }
          attr_reader :item

          sig { params(item: Item).void }
          def initialize(item)
            @item = T.let(item, Item)
          end
        end

        sig { params(options: T::Hash[Symbol, T.any(Item, Symbol)]).returns(Position) }
        def self.from_options(options)
          if before = options[:before]
            HigherThan.new(T.cast(before, Item))
          elsif after = options[:after]
            LowerThan.new(T.cast(after, Item))
          elsif options[:position] == :top
            Top.new
          elsif options[:position] == :bottom
            Bottom.new
          else
            GitHub.dogstats.increment("gh.prioritizable.sbt.unexpected_options")
            GitHub.logger.error(
              "message": "Unexpected position for prioritization",
              "code.namespace": self.name,
              "code.function": "from_options",
              "gh.prioritizable.sbt.unexpected_options": options.to_json,
            )
            Bottom.new
          end
        end
      end
    end
  end
end
