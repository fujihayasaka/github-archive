# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeqlVariantAnalysisRepoTaskTest < GitHub::TestCase
  include UploadableTestHelpers

  self.strict_fixtures = true
  fixtures do
    @owner = create(:paid_user)
    @staff = create(:user, :staff)

    @variant_analysis_org = create(:organization, admins: [@owner, @staff])
    @controller_repo = create(:private_repository, owner: @variant_analysis_org)

    @variant_analysis = create(:codeql_variant_analysis, controller_repo: @controller_repo)
    @variant_analysis_repo_task = create(:codeql_variant_analysis_repo_task, codeql_variant_analysis: @variant_analysis)
    @variant_analysis_repo = @variant_analysis_repo_task.repository

    make_trusted_oauth_apps_owner
    @code_scanning_app = create(:code_scanning_integration)
  end

  context "initialisation" do
    context "when an uploader is present" do
      test "it sets the uploader correctly" do
        subject = CodeqlVariantAnalysisRepoTask.create(
          repository_id: 1,
          status: "pending",
          codeql_variant_analysis_id: 2,
          uploader: @owner
        )

        refute_nil subject.artifact_actor_id
        refute_nil subject.uploader_id
      end
    end

    context "when an uploader is not present" do
      test "uploader should be nil" do
        assert_nil @variant_analysis_repo_task.uploader
      end
    end

    test "sets a guid" do
      assert_equal @variant_analysis_repo_task, CodeqlVariantAnalysisRepoTask.find_by(guid: @variant_analysis_repo_task.guid)
    end

    test "it sets the size to nil" do
      assert_nil @variant_analysis_repo_task.size
    end
  end

  context "deletion" do
    context "#storage_delete_object_if_exists" do
      test "called when object destroyed" do
        @variant_analysis_repo_task.expects(:storage_delete_object_if_exists)
        @variant_analysis_repo_task.destroy
      end
    end

    context "when asset is not found (status 404)" do
      test "it will not raise an error" do
        path = "/#{GitHub.codeql_variant_analysis_memory_alpha_bucket}/#{@variant_analysis_repo_task.storage_s3_key(nil)}"

        assert_nothing_raised do
          assert_storage_policy_delete(@variant_analysis_repo_task, path, delete_status: 404) do
            @variant_analysis_repo_task.storage_delete_object_if_exists
          end
        end
      end
    end
  end

  context "when an artifact is uploaded" do
    test "updates the state of the repo task" do
      assert_nil @variant_analysis_repo_task.state

      @variant_analysis_repo_task.track_uploaded

      assert_equal "uploaded", @variant_analysis_repo_task.state
    end
  end

  test "#storage_s3_key" do
    s3_key = "codeql-variant-analysis-repo-tasks/#{@variant_analysis.id}/#{@variant_analysis_repo.id}/#{@variant_analysis_repo_task.guid}"
    assert_equal s3_key, @variant_analysis_repo_task.storage_s3_key(nil)
  end

  test "#storage_policy_api_url" do
    storage_url = "/repositories/#{@controller_repo.id}/code-scanning/codeql/variant-analyses/#{@variant_analysis.id}/repositories/#{@variant_analysis_repo.id}"
    assert_equal storage_url, @variant_analysis_repo_task.storage_policy_api_url
  end

  context "storage policy" do
    test "doesn't use fastly bucket for generating uploadable base urls" do
      storage_policy = @variant_analysis_repo_task.storage_policy(actor: @owner, repository: @variant_analysis_repo)

      assert_nil @variant_analysis_repo_task.memory_alpha_fastly_acceleration_bucket(@owner, @variant_analysis_repo)
    end
  end
end
