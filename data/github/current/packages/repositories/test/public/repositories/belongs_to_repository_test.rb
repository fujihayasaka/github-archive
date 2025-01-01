# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::BelongsToRepositoryTest < GitHub::TestCase
  class ::RepositorySequence
    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain optional: true, feature_flag: "belongs_to_repo_test"
  end

  class ModelBelongsToRepositoryNoFF < RepositorySequence
    include ::Repositories::BelongsToRepository
    self.table_name = "repository_sequences"

    belongs_to_repository_via_domain
  end

  setup do
    @repo = create(:repository)
    @model = RepositorySequence.find_by(repository_id: @repo.id)
  end

  context "feature flag checks" do
    context "when enabled by feature_flag option" do
      test "toggle lookups between AR and domain" do
        if GitHub.flipper["belongs_to_repository_#{@model.class.name&.downcase}"].enabled?
          Repositories::Domain.any_instance.expects(:by_id).returns(@repo)
          assert_equal @model.repository, @repo
        else
          Repositories::Domain.any_instance.expects(:by_id).never
          assert_equal @model.repository, @repo
        end
      end
    end

    context "when not enabled by feature_flag option" do
      test "utilizes domain lookup by default" do
        no_ff_model = ModelBelongsToRepositoryNoFF.new(repository_id: @repo.id)
        Repositories::Domain.any_instance.expects(:by_id).returns(@repo)
        assert_equal no_ff_model.repository, @repo
      end
    end

    context "preloading multiple instances" do
      test "performs batch load" do
        repo2 = create(:repository)

        no_ff_models = Prelude.wrap([
          ModelBelongsToRepositoryNoFF.new(repository_id: @repo.id),
          ModelBelongsToRepositoryNoFF.new(repository_id: repo2.id)
        ])

        Repositories::Domain.any_instance.expects(:by_ids).returns([@repo, repo2])
        assert_equal no_ff_models.map(&:repository), [@repo, repo2]
      end
    end
  end

  context "when repository association was already loaded" do
    context "via preloading" do
      test "does not refetch the record" do
        GitHub::PrefillAssociations.prefill_associations(@model, :repository)
        assert_query_count(0, ignore_feature_flags: true) do
          @model.repository
        end
      end
    end

    context "via previous domain lookup" do
      test "does not refetch the record" do
        assert_query_count(1, ignore_feature_flags: true) do
          assert_equal @model.repository, @repo
        end

        assert_query_count(0, ignore_feature_flags: true) do
          assert_equal @model.repository, @repo
        end
      end
    end
  end

  context "when loaded through domain" do
    test "inverse relation is set" do
      enable_feature_flag("belongs_to_repo_test")
      model = RepositorySequence.last
      assert_query_count(1, ignore_feature_flags: true) do
        T.must(model).repository
      end
      assert_query_count(0, ignore_feature_flags: true) do
        assert_equal T.cast(model&.repository, Repository).repository_sequence, model # rubocop:todo GitHub/AvoidCast
      end
    end
  end

  context "when the repository_id is nil" do
    test "#repository returns nil with no sql query" do
      @model.repository_id = nil
      assert_query_count(0, ignore_feature_flags: true) do
        assert_nil @model.repository
      end
    end
  end
end
