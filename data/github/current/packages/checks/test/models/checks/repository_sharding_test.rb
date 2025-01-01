# typed: true
# frozen_string_literal: true

require "test_helper"

module Checks
  class RepositoryShardingTest < GitHub::TestCase
    class ShardedTestModel < ApplicationRecord::Mysql1
      include Checks::RepositorySharding

      self.table_name = "sharded_table"

      configure_sharding(should_shard: -> (record, _operation) {
        # Make sure to use the correct repository id for tests that will update it
        repo_id = record.persisted? ? record.attribute_in_database(:repository_id) : record.repository_id
        repo = Repository.instantiate("id" => repo_id)

        GitHub.flipper[:sharded_test_model_enable_sharding].enabled?(repo)
      })

      # Used down in tests to validate create scoping
      after_commit :commit_hook, on: [:create]

      def commit_hook
        ShardedTestModel.count
      end
    end

    class NonShardedTestModel < ApplicationRecord::Mysql1
      self.table_name = "sharded_table"
    end

    def before_setup
      ShardedTestModel.connection.execute <<~SQL
        CREATE TEMPORARY TABLE `sharded_table` (
          `id` int(11) NOT NULL AUTO_INCREMENT,
          `name` varchar(255) NOT NULL,
          `repository_id` int(11) NOT NULL,
          `created_at` datetime NOT NULL,
          `updated_at` datetime NOT NULL,
          PRIMARY KEY (`id`),
          KEY `index_sharded_table_on_repository_id` (`repository_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8
      SQL
      super
    end

    def after_teardown
      super
      ShardedTestModel.connection.execute <<~SQL
        DROP TEMPORARY TABLE `sharded_table`
      SQL
    end

    setup do
      owner = create(:user)
      @repository = create(:repository, owner: owner)

      @another_repository_id = 9
      @sharded_model_record = ShardedTestModel.create(name: "foobar", repository_id: @repository.id)
      @non_sharded_model_record = NonShardedTestModel.create(name: "foobar", repository_id: @repository.id)
    end

    context "#with_sharding" do
      test "raises error if should_shard is not net" do
        test_model_class = Class.new(ApplicationRecord::Mysql1) do
          include Checks::RepositorySharding

          self.table_name = "sharded_table"
        end

        test_record = test_model_class.first
        assert_raises_with_message ArgumentError, /should_shard needs to be configured/ do
          test_record.reload # calls `with_sharding`
        end
      end
    end

    context ".create" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          ShardedTestModel.create(name: "foobar", repository_id: @repository.id)
        end
      end

      test "ensure queries do not contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          ShardedTestModel.create(name: "foobar", repository_id: @repository.id)
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          NonShardedTestModel.create(name: "foobar", repository_id: @repository.id)
        end
      end
    end

    context ".create!" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          ShardedTestModel.create!(name: "foobar", repository_id: @repository.id)
        end
      end

      test "ensure queries do not contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          ShardedTestModel.create!(name: "foobar", repository_id: @repository.id)
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          NonShardedTestModel.create!(name: "foobar", repository_id: @repository.id)
        end
      end
    end

    context "#reload" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.reload
        end
      end

      test "ensure queries do not contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @sharded_model_record.reload
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @non_sharded_model_record.reload
        end
      end
    end

    context "#save" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.name = "new name"
          @sharded_model_record.save
        end
      end

      test "ensure queries do not contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @sharded_model_record.name = "new name"
          @sharded_model_record.save
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @non_sharded_model_record.name = "new name"
          @non_sharded_model_record.save
        end
      end

      test "ensure queries contain the old sharding key value when it is also updated" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /\AUPDATE .+ SET .*`repository_id` = #{@another_repository_id}.* WHERE .*`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.repository_id = @another_repository_id
          @sharded_model_record.save
        end
      end
    end

    context "#update" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.update(name: "new name")
        end
      end

      test "ensure queries do not contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @sharded_model_record.update(name: "new name")
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @non_sharded_model_record.update(name: "new name")
        end
      end

      test "ensure queries contain the old sharding key value when it is also updated" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /\AUPDATE .+ SET .*`repository_id` = #{@another_repository_id}.* WHERE .*`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.update(repository_id: @another_repository_id)
        end
      end
    end

    context "#update_attribute" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.update_attribute(:name, "new name")
        end
      end

      test "ensure queries do not contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @sharded_model_record.update_attribute(:name, "new name")
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @non_sharded_model_record.update_attribute(:name, "new name")
        end
      end

      test "ensure queries contpin the old sharding key value when it is also updated" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /\AUPDATE .+ SET .*`repository_id` = #{@another_repository_id}.* WHERE .*`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.update_attribute(:repository_id, @another_repository_id)
        end
      end
    end

    context "#save!" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.name = "new name"
          @sharded_model_record.save!
        end
      end

      test "ensure queries contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @sharded_model_record.name = "new name"
          @sharded_model_record.save!
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @non_sharded_model_record.name = "new name"
          @non_sharded_model_record.save!
        end
      end

      test "ensure queries contain the old sharding key value when it is also updated" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /\AUPDATE .+ SET .*`repository_id` = #{@another_repository_id}.* WHERE .*`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.repository_id = @another_repository_id
          @sharded_model_record.save!
        end
      end
    end

    context "#update!" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.update!(name: "new name")
        end
      end

      test "ensure queries no not contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @sharded_model_record.update!(name: "new name")
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @non_sharded_model_record.update!(name: "new name")
        end
      end

      test "ensure queries contain the old sharding key value when it is also updated" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /\AUPDATE .+ SET .*`repository_id` = #{@another_repository_id}.* WHERE .*`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.update!(repository_id: @another_repository_id)
        end
      end
    end

    context "#update_columns" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.update_columns(name: "new name")
        end
      end

      test "ensure queries do not contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @sharded_model_record.update_columns(name: "new name")
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @non_sharded_model_record.update_columns(name: "new name")
        end
      end

      test "ensure queries contain the old sharding key value when it is also updated" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /\AUPDATE .+ SET .*`repository_id` = #{@another_repository_id}.* WHERE .*`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.update_columns(repository_id: @another_repository_id)
        end
      end
    end

    context "#update_column" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.update_column(:name, "new name")
        end
      end

      test "ensure queries do not contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @sharded_model_record.update_column(:name, "new name")
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @non_sharded_model_record.update_column(:name, "new name")
        end
      end

      test "ensure queries contain the old sharding key value when it is also updated" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /\AUPDATE .+ SET .*`repository_id` = #{@another_repository_id}.* WHERE .*`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.update_column(:repository_id, @another_repository_id)
        end
      end
    end

    context "#touch" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.touch(time: 2.minutes.from_now)
        end
      end

      test "ensure queries do not contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @sharded_model_record.touch(time: 2.minutes.from_now)
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @non_sharded_model_record.touch(time: 2.minutes.from_now)
        end
      end
    end

    context "#destroy" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.destroy
        end
      end

      test "ensure queries do not contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @sharded_model_record.destroy
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @non_sharded_model_record.destroy
        end
      end
    end

    context "#destroy!" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.destroy!
        end
      end

      test "ensure queries do not contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @sharded_model_record.destroy!
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @non_sharded_model_record.destroy!
        end
      end
    end

    context "#delete" do
      test "ensure queries contain the sharding key for sharded model with the feature enabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 1 do
          @sharded_model_record.delete
        end
      end

      test "ensure queries do not contain the sharding key for sharded model with the feature disabled" do
        GitHub.flipper[:sharded_test_model_enable_sharding].disable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @sharded_model_record.delete
        end
      end

      test "ensure queries do not contain the sharding key for non-sharded model" do
        GitHub.flipper[:sharded_test_model_enable_sharding].enable(@repository)

        assert_queries_matching /WHERE .+`repository_id` = #{@repository.id}/, 0 do
          @non_sharded_model_record.delete
        end
      end
    end
  end
end
