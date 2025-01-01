# typed: true
# frozen_string_literal: true

require "test_helper"

class Pushes::PushesHydroRequeuerTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :post_receive_job_test)
    @push_ref_updates = 6.times.map { [SecureRandom.hex(20), SecureRandom.hex(20), "refs/heads/foo"] }
    @csv = file_fixture("repos/pushes_hydro_requeuer_test.csv").freeze
    @failed_csv_path = "failed_pushes.csv"
  end

  setup do
    @repo.pushes.destroy_all
    @csv_data = <<-CSV
"headers","repository_id","request_context","ref_updates","pushed_at","push_options","oauth_access_id","user_programmatic_access_id","installation_id","installation_type","excluded_pull_ids","merge_method","merge_action","pusher","enabled_flags","path","total_ref_count","ref_batch_number"
"{""kafka-cluster"":""development"",""topic"":""github.repositories.v1.Pushed"",""partition"":""0"",""offset"":""8"",""hydro-encoding"":""protobuf""}","#{@repo.id}","{""request_id"":""9c5288e2-2ffa-47d8-acd2-a1d9da00ef12""}","[{""ref"":""#{Base64.strict_encode64("refs/heads/foo")}"",""before"":""#{@push_ref_updates[0]&.first}"",""after"":""#{@push_ref_updates[0]&.second}""}]","2024-03-22T17:43:54.0000000Z","[]","0","0","0","","[]","","","monalisa","[]","/workspaces/github/repositories/development/dgit1/a/nw/a8/7f/f6/4/4.git","1","1"
"{""kafka-cluster"":""development"",""topic"":""github.repositories.v1.Pushed"",""partition"":""1"",""offset"":""872939851"",""hydro-encoding"":""protobuf""}","#{@repo.id}","{""request_id"":""450f776a1288e31f6b0b0c229281d8d2"",""request_method"":""REQUEST_METHOD_UNKNOWN"",""request_url"":"""",""ip_address"":""10.125.45.232"",""ip_version"":""IPV4"",""v4_int"":175975912,""v6_int"":"""",""user_agent"":""babeld/05989c77"",""session_id"":0,""controller"":""Api::Internal::Repositories"",""controller_action"":"""",""api_route"":"""",""request_category"":""api"",""from"":""Api::Internal::Repositories#POST"",""auth"":""ANON"",""client_id"":"""",""referrer"":"""",""format"":"""",""user_session_id"":""0""}","[{""ref"":""#{Base64.strict_encode64("refs/heads/foo")}"",""before"":""#{@push_ref_updates[1]&.first}"",""after"":""#{@push_ref_updates[1]&.second}""}]","2024-03-22T17:43:57.0000000Z","[]","0","0","0","","[]","","","#{@repo.owner.login}","[]","#{@repo.shard_path}","1","1"
"{""kafka-cluster"":""development"",""topic"":""github.repositories.v1.Pushed"",""partition"":""1"",""offset"":""872939862"",""hydro-encoding"":""protobuf""}","#{@repo.id}","{""request_id"":""E5A7:9F61C:C5EC2F8:C8A14B1:65FDC35F"",""request_method"":""REQUEST_METHOD_UNKNOWN"",""request_url"":"""",""ip_address"":""10.125.66.214"",""ip_version"":""IPV4"",""v4_int"":175981270,""v6_int"":"""",""user_agent"":""babeld/05989c77"",""session_id"":0,""controller"":""Api::Internal::Repositories"",""controller_action"":"""",""api_route"":"""",""request_category"":""api"",""from"":""Api::Internal::Repositories#POST"",""auth"":""ANON"",""client_id"":"""",""referrer"":"""",""format"":"""",""user_session_id"":""0""}","[{""ref"":""#{Base64.strict_encode64("refs/heads/foo")}"",""before"":""#{@push_ref_updates[2]&.first}"",""after"":""#{@push_ref_updates[2]&.second}""}]","2024-03-22T17:43:59.0000000Z","[]","851472992","0","0","","[]","","","#{@repo.owner.login}","[]","#{@repo.shard_path}","1","1"
"{""kafka-cluster"":""development"",""topic"":""github.repositories.v1.Pushed"",""partition"":""1"",""offset"":""872939881"",""hydro-encoding"":""protobuf""}","#{@repo.id}","{""request_id"":""AA1A:712A7:6F131CB:7098E4C:65FDC360"",""request_method"":""REQUEST_METHOD_UNKNOWN"",""request_url"":"""",""ip_address"":""10.125.50.81"",""ip_version"":""IPV4"",""v4_int"":175977041,""v6_int"":"""",""user_agent"":""babeld/05989c77"",""session_id"":0,""controller"":""Api::Internal::Repositories"",""controller_action"":"""",""api_route"":"""",""request_category"":""api"",""from"":""Api::Internal::Repositories#POST"",""auth"":""ANON"",""client_id"":"""",""referrer"":"""",""format"":"""",""user_session_id"":""0""}","[{""ref"":""#{Base64.strict_encode64("refs/heads/foo")}"",""before"":""#{@push_ref_updates[3]&.first}"",""after"":""#{@push_ref_updates[3]&.second}""}]","2024-03-22T17:44:00.0000000Z","[]","542490197","0","0","","[]","","","#{@repo.owner.login}","[]","#{@repo.shard_path}","1","1"
"{""kafka-cluster"":""development"",""topic"":""github.repositories.v1.Pushed"",""partition"":""1"",""offset"":""872939906"",""hydro-encoding"":""protobuf""}","#{@repo.id}","{""request_id"":""BEDC:5BCC6:71498DC:72CF71A:65FDC363"",""request_method"":""REQUEST_METHOD_UNKNOWN"",""request_url"":"""",""ip_address"":""10.125.55.33"",""ip_version"":""IPV4"",""v4_int"":175978273,""v6_int"":"""",""user_agent"":""babeld/05989c77"",""session_id"":0,""controller"":""Api::Internal::Repositories"",""controller_action"":"""",""api_route"":"""",""request_category"":""api"",""from"":""Api::Internal::Repositories#POST"",""auth"":""ANON"",""client_id"":"""",""referrer"":"""",""format"":"""",""user_session_id"":""0""}","[{""ref"":""#{Base64.strict_encode64("refs/heads/foo")}"",""before"":""#{@push_ref_updates[4]&.first}"",""after"":""#{@push_ref_updates[4]&.second}""}]","2024-03-22T17:44:04.0000000Z","[]","1447008777","0","0","","[]","","","#{@repo.owner.login}","[]","#{@repo.shard_path}","1","1"
"{""kafka-cluster"":""development"",""topic"":""github.repositories.v1.Pushed"",""partition"":""1"",""offset"":""872939995"",""hydro-encoding"":""protobuf""}","#{@repo.id}","","[{""ref"":""#{Base64.strict_encode64("refs/heads/foo")}"",""before"":""#{@push_ref_updates[5]&.first}"",""after"":""#{@push_ref_updates[5]&.second}""}]","2024-03-22T17:44:13.0000000Z","[]","0","0","0","","[]","","","#{@repo.owner.login}","[]","#{@repo.shard_path}","1","1"
CSV

    File.open(@csv, "w") do |file|
      file.write(@csv_data)
    end
  end

  teardown do
    File.open(@csv, "w") {} # empty the file
    File.delete(@failed_csv_path) if File.exist?(@failed_csv_path)
  end

  test "it works" do
    requeuer = Pushes::PushesHydroRequeuer.new(@csv.to_s)
    assert_equal 6, requeuer.event_count

    # not in write mode, do so nothing
    assert_no_enqueued_jobs do
      requeuer.run(queue: "hydro_repositories_on_push")
    end
    assert_equal 0, @repo.pushes.count

    # process the first event
    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      requeuer.run(queue: "hydro_repositories_on_push", limit: 1, write: true)
    end
    assert_equal 1, @repo.pushes.count

    # process the rest of the events
    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      requeuer.run(queue: "hydro_repositories_on_push", skip: 1, write: true)
    end
    assert_equal 6, @repo.reload.pushes.count
    assert_same_elements @push_ref_updates, @repo.pushes.map { |push| [push.before, push.after, push.ref] }
  end

  test "captures failed rows for retry" do
    requeuer = Pushes::PushesHydroRequeuer.new(@csv.to_s)
    assert_equal 6, requeuer.event_count

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      encoder = GitHub.hydro_encoder
      GitHub.stubs(:hydro_encoder).raises("boom").then.raises("boom").then.returns(encoder)
      requeuer.run(queue: "hydro_repositories_on_push", write: true)
    end

    assert_equal 4, @repo.pushes.count
    assert_equal 2, requeuer.failed.count

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      requeuer.retry_failed(queue: "hydro_repositories_on_push")
    end

    assert_equal 6, @repo.reload.pushes.count
    assert_equal 0, requeuer.failed.count
    assert_same_elements @push_ref_updates, @repo.pushes.map { |push| [push.before, push.after, push.ref] }
  end

  test "#save_failed saves failed rows to csv" do
    requeuer = Pushes::PushesHydroRequeuer.new(@csv.to_s)
    assert_equal 6, requeuer.event_count

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      encoder = GitHub.hydro_encoder
      GitHub.stubs(:hydro_encoder).raises("boom").then.raises("boom").then.returns(encoder)
      requeuer.run(queue: "hydro_repositories_on_push", write: true)
    end
    assert_equal 4, @repo.pushes.count
    assert_equal 2, requeuer.failed.count

    # save the failures to csv
    requeuer.save_failed(path: @failed_csv_path)
    assert File.exist?(@failed_csv_path)

    # initilize a new requeuer with the csv of failures and process them
    requeuer = Pushes::PushesHydroRequeuer.new(@failed_csv_path)
    assert_equal 2, requeuer.event_count

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      requeuer.run(queue: "hydro_repositories_on_push", write: true)
    end
    assert_equal 6, @repo.reload.pushes.count
    assert_equal 0, requeuer.failed.count
    assert_same_elements @push_ref_updates, @repo.pushes.map { |push| [push.before, push.after, push.ref] }
  end
end
