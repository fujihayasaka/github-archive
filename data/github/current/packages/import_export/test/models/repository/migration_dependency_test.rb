# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryMigrationDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repository = create(:repository, owner: @user)
  end

  context "is_importing?" do
    test "returns true if the repository is importing" do
      @repository.importing_started!
      assert @repository.is_importing?
    end

    test "returns false if the repository isn't importing" do
      @repository.importing_stopped!

      refute @repository.is_importing?
    end

    test "returns false if the repository is old with skip_model_importing_check_on_old_repositories enabled, regardless of the current status" do
      enable_feature_flag(:skip_model_importing_check_on_old_repositories, @repository)

      @repository.stubs(:created_at).returns(1.year.ago)
      @repository.importing_started!

      GitHub.job_coordination_redis.expects(:exists).never

      refute @repository.is_importing?
    end

    test "returns true if the repository is old with skip_model_importing_check_on_old_repositories disabled" do
      disable_feature_flag(:skip_model_importing_check_on_old_repositories, @repository)

      @repository.stubs(:created_at).returns(1.year.ago)
      @repository.importing_started!

      assert @repository.is_importing?
    end
  end
end
