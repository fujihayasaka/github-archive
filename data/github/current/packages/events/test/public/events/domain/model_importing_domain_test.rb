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
        result = @domain.model_importing?(@repo)
        assert_equal true, result
      end
    end

    test "it returns true when repository is nil" do
      GitHub.importing do
        result = @domain.model_importing?(nil)
        assert_equal true, result
      end
    end
  end

  context "when repository is importing" do
    test "it returns true" do
      Repository.any_instance.stubs(:is_importing?).returns(true)
      result = @domain.model_importing?(@repo)
      assert_equal true, result
    end
  end

  context "when repository is locked for migration" do
    test "it returns true" do
      Repository.any_instance.stubs(:locked_on_migration?).returns(true)
      result = @domain.model_importing?(@repo)
      assert_equal true, result
    end
  end

  context "when nothing is importing" do
    test "it returns false" do
      result = @domain.model_importing?(@repo)
      assert_equal false, result
    end
  end
end
