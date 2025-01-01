# typed: true
# frozen_string_literal: true

require "test_helper"

class ModelImportingDomainTest < GitHub::TestCase
  fixtures do
    @mojombo = create(:user, login: "mojombo", plan: "medium")

    @repo = create(:repository, name: "grit", owner: @mojombo)
  end

  setup do
    @domain = Events::Domain.new
  end

  context "when GitHub is importing" do
    test "it returns true" do
      GitHub.importing do
        assert @domain.model_importing?(@repo)
      end
    end

    test "it returns true when repository is nil" do
      GitHub.importing do
        assert @domain.model_importing?(nil)
      end
    end
  end

  context "when repository is importing" do
    test "it returns true" do
      Repository.any_instance.stubs(:is_importing?).returns(true)
      assert @domain.model_importing?(@repo)
    end
  end

  context "when repository is locked for migration" do
    test "it returns true on young repos" do
      Repository.any_instance.stubs(:locked_on_migration?).returns(true)
      Repository.any_instance.stubs(:feature_enabled?).with(:skip_model_importing_check_on_old_repositories).returns(false)
      assert @domain.model_importing?(@repo)
    end

    test "it returns true on young repos with feature flag" do
      Repository.any_instance.stubs(:locked_on_migration?).returns(true)
      Repository.any_instance.stubs(:feature_enabled?).with(:skip_model_importing_check_on_old_repositories).returns(true)
      assert @domain.model_importing?(@repo)
    end

    test "it returns true on old repos" do
      Repository.any_instance.stubs(:locked_on_migration?).returns(true)
      Repository.any_instance.stubs(:feature_enabled?).with(:skip_model_importing_check_on_old_repositories).returns(false)
      @repo.created_at = 4.weeks.ago
      assert @domain.model_importing?(@repo)
    end

    test "it returns false on old repos with feature flag" do
      Repository.any_instance.stubs(:locked_on_migration?).returns(true)
      Repository.any_instance.stubs(:feature_enabled?).with(:skip_model_importing_check_on_old_repositories).returns(true)
      @repo.created_at = 4.weeks.ago
      refute @domain.model_importing?(@repo)
    end
  end

  context "when nothing is importing" do
    test "it returns false" do
      refute @domain.model_importing?(@repo)
    end
  end
end
