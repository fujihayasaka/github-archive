# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Prevents usage of `change_table` with the `bulk: true` option.
      # This has a bug when used with table name prefixes, such as dependabot-api
      # uses in enterprise mode.
      # See https://github.com/rails/rails/issues/56573 for more details.
      #
      # @example
      #   # bad
      #   def change
      #     change_table :users, bulk: true do |t|
      #       t.string :name, null: false
      #       t.string :nickname
      #     end
      #   end
      #
      #   # good
      #   def change
      #     change_table :users, bulk: false do |t|
      #       t.string :name, null: false
      #       t.string :nickname
      #     end
      #   end
      #
      #   # good
      #   def change
      #     change_table :users do |t|
      #       t.string :name, null: false
      #       t.string :nickname
      #     end
      #   end
      #
      #   # good
      #   def change
      #     add_column :users, :name, :string, null: false
      #     add_column :users, :nickname, :string
      #
      #     # ALTER TABLE `users` ADD `name` varchar(255) NOT NULL
      #     # ALTER TABLE `users` ADD `nickname` varchar(255)
      #   end
      class NoBulkChangeTable < Base
        MSG = <<~MSG.chomp
          change_table(..., bulk: true) does not work with our table_prefix_name in enterprise mode.
          Please use bulk: false or remove the bulk option.
          See https://github.com/rails/rails/issues/56573 for more details.
        MSG

        def_node_matcher :bulk_change_table?, <<~PATTERN
          (send nil? :change_table _ (hash (pair (sym :bulk) true) ...))
        PATTERN

        def on_send(node)
          return unless bulk_change_table?(node)

          add_offense(node, message: MSG)
        end
      end
    end
  end
end
