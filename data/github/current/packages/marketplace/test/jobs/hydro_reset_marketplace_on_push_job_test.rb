# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../app/models/marketplace/k_v"

class HydroResetMarketplaceOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include PushTestHelper
  include Marketplace::Domain::Provider

  fixtures do
    @user = create(:user)
    @repository = create(:repository, owner: @user)

    @ref = "refs/heads/master"
    @before = "c1800491d95c42b4e96fb83f31fe8d9230c62907"
    @after = "63611721afd41f58f801d66e543d8288b4c5eb44"
  end

  setup do
    example_repo :post_receive_job_test, @repository

    @message = {
      repository_id: @repository.id,
      ref_updates: [{ ref: @ref, before: @before, after: @after }],
      pusher: @user.login,
      pushed_at: 1.minute.ago,
      run_hydro_job: true,
    }
    @schema = "github.repositories.v1.Pushed"
    @queue = "hydro_reset_marketplace_on_push"
  end

  test "resets mobile status when default branch is pushed to a repo without CI" do
    Marketplace::KV.store.set(marketplace_domain.repository_settings.mobile_key(@repository.id), "1")
    Marketplace::Domain::RepositorySettings.any_instance.stubs(:has_ci?).returns(false)

    perform_hydro_message_job(@message, schema: @schema, queue: @queue)

    assert_equal "0", Marketplace::KV.store.get(marketplace_domain.repository_settings.mobile_key(@repository.id)).value { nil }
  end

  test "clears mobile status when default branch is pushed to a repo with CI" do
    Marketplace::KV.store.set(marketplace_domain.repository_settings.mobile_key(@repository.id), "1")
    Marketplace::Domain::RepositorySettings.any_instance.stubs(:has_ci?).returns(true)

    perform_hydro_message_job(@message, schema: @schema, queue: @queue)

    assert_nil Marketplace::KV.store.get(marketplace_domain.repository_settings.mobile_key(@repository.id)).value { "error" }
  end

  test "does not clear mobile status when non-default branch is pushed" do
    Marketplace::KV.store.set(marketplace_domain.repository_settings.mobile_key(@repository.id), "1")
    @message[:ref_updates] = [{ ref: "refs/tags/v1", before: GitHub::NULL_OID, after: @after }]
    Marketplace::Domain::RepositorySettings.any_instance.expects(:clear_mobile_status).never
    Marketplace::Domain::RepositorySettings.any_instance.expects(:set_mobile_status).never

    perform_hydro_message_job(@message, schema: @schema, queue: @queue)

    assert_equal "1", Marketplace::KV.store.get(marketplace_domain.repository_settings.mobile_key(@repository.id)).value { nil }
  end

  test "resets Dockerfile status when default branch is pushed to a repo without CI" do
    Marketplace::KV.store.set(marketplace_domain.repository_settings.docker_file_key(@repository.id), "1")
    Marketplace::Domain::RepositorySettings.any_instance.stubs(:has_ci?).returns(false)

    perform_hydro_message_job(@message, schema: @schema, queue: @queue)

    assert_equal "0", Marketplace::KV.store.get(marketplace_domain.repository_settings.docker_file_key(@repository.id)).value { nil }
  end

  test "clears Dockerfile status when default branch is pushed to a repo with CI" do
    Marketplace::KV.store.set(marketplace_domain.repository_settings.docker_file_key(@repository.id), "1")
    Marketplace::Domain::RepositorySettings.any_instance.stubs(:has_ci?).returns(true)

    perform_hydro_message_job(@message, schema: @schema, queue: @queue)

    assert_nil Marketplace::KV.store.get(marketplace_domain.repository_settings.docker_file_key(@repository.id)).value { "error" }
  end

  test "does not clear Dockerfile status when non-default branch is pushed" do
    Marketplace::KV.store.set(marketplace_domain.repository_settings.docker_file_key(@repository.id), "1")
    @message[:ref_updates] = [{ ref: "refs/tags/v1", before: GitHub::NULL_OID, after: @after }]
    Marketplace::Domain::RepositorySettings.any_instance.expects(:clear_docker_file_status).never
    Marketplace::Domain::RepositorySettings.any_instance.expects(:set_docker_file_status).never

    perform_hydro_message_job(@message, schema: @schema, queue: @queue)

    assert_equal "1", Marketplace::KV.store.get(marketplace_domain.repository_settings.docker_file_key(@repository.id)).value { nil }
  end
end
