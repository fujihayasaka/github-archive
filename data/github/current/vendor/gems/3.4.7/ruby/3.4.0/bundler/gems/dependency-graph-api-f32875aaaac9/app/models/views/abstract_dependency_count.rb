require "sliced_range"
require "table_swap"

module Views
  module AbstractDependencyCount
    def for(package)
      ActiveRecord::Base.connected_to(role: :reading) {
        where({
          package_name:    package.name,
          package_manager: package.package_manager
        }).first&.dependent_count.to_i
      }
    end

    def rebuild
      TableSwap.new(table_name).with_swap do |tmp_table_name|
        view_manager(insert_into: tmp_table_name).run(full_rebuild: true)
      end
    end

    def update
      view_manager.run
    end

    def view_manager(insert_into: table_name)
      raise NotImplementedError
    end

    class ViewManager
      def initialize(extract_from:, insert_into:, checkpoint_name:)
        @extract_from    = extract_from
        @insert_into     = insert_into
        @checkpoint_name = checkpoint_name
      end

      def run(full_rebuild: false)
        connection.execute("SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED")

        reset if full_rebuild

        if updatable?
          update_in_batches
        else
          DependencyGraph.logger.info("Nothing to update")
        end
      end

      def reset
        checkpoint.reset!
      end

      private

      attr_accessor :insert_into, :extract_from, :checkpoint_name, :extract_from_sql, :table_name

      def update_in_batches
        range = Range.new(checkpoint.get + 1, latest_record_id)

        DependencyGraph.logger.info("Updating counts",
          "gh.dependency_graph.abstract_dependency_count.latest_record_id" => extract_from,
          "gh.dependency_graph.abstract_dependency_count.range" => range,
        )

        SlicedRange.new(
          min:  range.first,
          max:  range.last,
          size: 100_000,
                        ).each do |range|
          select_sql = extract_from.where(id: range.first..range.last).select(:package_name, :package_manager, Arel.sql("count(1)")).group(:package_name, :package_manager).to_sql
          insert_sql = <<~SQL
          INSERT INTO #{insert_into} (
            package_name,
            package_manager,
            dependent_count
          ) #{select_sql}
          ON DUPLICATE KEY UPDATE
            dependent_count = dependent_count + VALUES(dependent_count)
          SQL
          connection.execute(insert_sql)
          checkpoint.set!(range.last)
        end
      end

      def connection
        ActiveRecord::Base.connection
      end

      def latest_record_id
        extract_from.unscoped.maximum(:id)
      end

      def updatable?
        checkpoint.get < latest_record_id
      end

      def checkpoint
        @checkpoint ||= Checkpoint
          .with_name(checkpoint_name)
          .first_or_create!
      end
    end
  end
end
