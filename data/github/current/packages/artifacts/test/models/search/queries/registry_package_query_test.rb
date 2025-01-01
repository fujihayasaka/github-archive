# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesRegistryPackageQueryTest < GitHub::TestCase

  ModelMock = Struct.new(
    :_model,
    :_index,
    :_type,
    :id,
    :_id,
    :_source
  )
  SourceMock = Struct.new(
    :name,
    :namespace,
    :created_at,
    :updated_at
  )
  fixtures do
    setup_search

    @user  = create(:user, login: "user", plan: "medium")
    @user2 = create(:user, login: "user2", plan: "medium")

    @user_repo = create(:repository, owner: @user, from_example: :repository_test_simple)

    @user_private_repo = create(:private_repository, owner: @user, from_example: :repository_test_simple)
    topic = create(:topic, name: "ruby")
    topic.repository_topics.create!(repository: @user_private_repo, state: :created, user: @user)

    @user2_repo = create(:repository, owner: @user2, from_example: :repository_test_simple)

    @user2_private_repo = create(:private_repository, owner: @user2, from_example: :repository_test_simple)

    @widget = make_package(@user_repo, "acme-widget")
    @cog = make_package(@user_private_repo, "acme-cog", type: "maven")
    @rocket = make_package(@user2_repo, "acme-rocket", summary: "Be as fast as the roadrunner", readme: "The quick brown fox")
    @secret = make_package(@user2_private_repo, "acme-secret")
    @another_private_package = make_package(@user_private_repo, "foo-bar-private", type: "docker")
  end

  setup do
    reset_cache

    act_as(@user)
    @unscoped_query = Search::Queries::RegistryPackageQuery.new(current_user: @user, aggregations: true)
    @repo_scoped_query = Search::Queries::RegistryPackageQuery.new(current_user: @user, repo_id: @user_repo.id)
    @owner_scoped_query = Search::Queries::RegistryPackageQuery.new(current_user: @user, owner: @user)
    @package_type_scoped_query = Search::Queries::RegistryPackageQuery.new(current_user: @user, package_type: "maven")
    @anonymous_query = Search::Queries::RegistryPackageQuery.new(current_user: nil, aggregations: true)

    [@widget, @cog, @rocket, @secret, @another_private_package].each do |package|
      make_searchable(package, type: "registry_package")
    end

    GitHub.stubs(:registry_v2_enabled_for_enterprise?).returns(true) if GitHub.enterprise?
  end

  teardown_once do
    teardown_search
  end

  def make_package(repo, name, type: "nuget", summary: nil, readme: nil)
    version = Time.now.usec
    release = create :release, repository: repo, tag_name: "v#{version}", author: repo.owner,
      state: :published, created_at: 1.month.ago, body: "*version #{version}*"

    package = Registry::Package.new name: name,
      repository_id: repo.id, registry_package_type: type, package_type: type
    version = package.package_versions.build version: "v#{version}", release: release, author: repo.owner
    version.files.build size: 1

    summary ||= "This is a summary for #{version.version}"
    version.metadata.build(name: Registry::Metadatum::KEYS[:SUMMARY], value: summary)

    readme ||= "lorem ipsum"
    version.metadata.build(name: Registry::Metadatum::KEYS[:README], value: readme)

    version.manifest = "{\"dependencies\": {\"async\":\"~1.0.0\"}}"
    package.save!

    package
  end

  context "#query_params" do
    test "queries the packages alias" do
      assert_equal("packages#{Elastomer::Environment.postfix}", Search::Queries::RegistryPackageQuery.new(current_user: @user).query_params[:index])
    end
  end

  context "#prune_results" do
    test "does not prune rms packages while container ui flag enabled" do
      model = ModelMock.new(
        _index: "rms-packages-2",
        _type: "registry_package",
        id: 16,
        _id: "rms-16",
        _source: SourceMock.new(
          name: "peachy",
          namespace: "monalisa",
          created_at: "2020-04-30T23:46:05.549317Z",
          updated_at: "2020-04-30T23:46:05.549317Z",
        ),
      )

      results = {
        hits: {
          total: 1,
          hits: [
            model
          ]
        }
      }.deep_stringify_keys

      # Stub call to RMS client
      PackageRegistry::Twirp::MetadataClient.any_instance.expects(:get_packages_metadata).with(actor: @user, package_ids: [model.id], include_deleted: false, exclude_latest_versions: true).returns([model])

      result = @unscoped_query.prune_results(Search::Results.new(results, page: 1, per_page: 10).results)
      assert_equal model, result[0]["_model"]
    end

    test "prune rms packages returns expected packages when current_user is nil (anonymous access)" do
      act_as(nil)
      model = ModelMock.new(
        _index: "rms-packages-2",
        _type: "registry_package",
        id: 16,
        _id: "rms-16",
        _source: SourceMock.new(
            name: "peachy",
            namespace: "monalisa",
            created_at: "2020-04-30T23:46:05.549317Z",
            updated_at: "2020-04-30T23:46:05.549317Z",
            ),
        )

      results = {
        hits: {
            total: 1,
            hits: [
              model
            ]
        }
      }.deep_stringify_keys

      # Stub call to RMS client
      PackageRegistry::Twirp::MetadataClient.any_instance.expects(:get_packages_metadata).with(actor: nil, package_ids: [model.id], include_deleted: false, exclude_latest_versions: true).returns([model])

      result = @anonymous_query.prune_results(Search::Results.new(results, page: 1, per_page: 10).results)
      assert_equal model, result[0]["_model"]
    end

    test "prune rms packages does not fail while container ui flag disabled" do

      model = ModelMock.new(
        _index: "rms-packages-2",
        _type: "registry_package",
        id: 16,
        _id: "rms-16",
        _source: SourceMock.new(
          name: "peachy",
          namespace: "monalisa",
          created_at: "2020-04-30T23:46:05.549317Z",
          updated_at: "2020-04-30T23:46:05.549317Z",
        ),
      )

      results = {
        hits: {
          total: 1,
          hits: [
            model
          ]
        }
      }.deep_stringify_keys

      result = @unscoped_query.prune_results(Search::Results.new(results, page: 1, per_page: 10).results)
      assert_nil result[0]["_model"]
    end
  end # Prune resutls

  context "unscoped queries" do
    test "it will only query registry packages" do
      assert_equal("registry_package", @unscoped_query.query_params[:type])
    end

    test "searches by full name" do
      @unscoped_query.phrase = "acme-widget"
      assert_equal [@widget], @unscoped_query.execute.results.map { |result| result["_model"] }
    end

    test "searches by partial name" do
      @unscoped_query.phrase = "widget"
      assert_equal [@widget], @unscoped_query.execute.results.map { |result| result["_model"] }
    end

    test "doesn't return packages the user isn't authorized to see" do
      @unscoped_query.phrase = "acme"

      results = @unscoped_query.execute.results.map { |result| result["_model"] }
      refute_includes results, @secret
      assert_same_elements [@widget, @cog, @rocket], results
    end

    test "security_validation returns false if a private result is inadvertently returned to an anoynmous user" do
      secret_query = Search::Queries::RegistryPackageQuery.new(current_user: @user2_private_repo.owner)
      private_result = secret_query.execute.results.detect { |r| !r.dig("_source", "public") } # finds @secret
      act_as(nil)
      anon_query = Search::Queries::RegistryPackageQuery.new(current_user: nil)
      refute anon_query.security_validation(private_result)
    end

    test "allows searching for other user's public packages" do
      @unscoped_query.phrase = "rocket"

      assert_equal [@rocket], @unscoped_query.execute.results.map { |result| result["_model"] }
    end

    test "allows specifying the package's owner" do
      @unscoped_query.phrase = "acme user:user2"
      assert_equal [@rocket], @unscoped_query.execute.results.map { |result| result["_model"] }
    end

    test "allows specifying the package's owner with org:" do
      @unscoped_query.phrase = "acme org:user2"
      assert_equal [@rocket], @unscoped_query.execute.results.map { |result| result["_model"] }
    end

    test "allows specifying the package's owner with owner:" do
      @unscoped_query.phrase = "acme owner:user2"
      assert_equal [@rocket], @unscoped_query.execute.results.map { |result| result["_model"] }
    end

    test "allows searching by package type" do
      @unscoped_query.phrase = "package_type:maven"
      assert_equal [@cog], @unscoped_query.execute.results.map { |result| result["_model"] }
    end

    test "allows search by visibility" do
      query = Search::Queries::RegistryPackageQuery.new(current_user: @user, visibility: "private")
      assert_same_elements [@cog, @another_private_package], query.execute.results.map { |result| result["_model"] }
    end

    test "allows searching by repo topic" do
      @unscoped_query.phrase = "topic:ruby"
      assert_equal [@cog, @another_private_package], @unscoped_query.execute.results.map { |result| result["_model"] }
    end

    test "allows searching by summary" do
      @unscoped_query.phrase = "roadrunner"
      assert_equal [@rocket], @unscoped_query.execute.results.map { |result| result["_model"] }
    end

    test "allows searching by body" do
      @unscoped_query.phrase = "quick"
      assert_equal [@rocket], @unscoped_query.execute.results.map { |result| result["_model"] }
    end

    test "supports package_type aggregation" do
      @unscoped_query.phrase = "acme"
      results = @unscoped_query.execute

      assert_equal 2, results.package_types.count

      nuget = results.package_types.find { |agg| agg.term == "nuget" }
      maven = results.package_types.find { |agg| agg.term == "maven" }

      assert_equal 2, nuget.count
      assert_equal 1, maven.count
    end
  end

  context "repo scoped queries" do
    test "only returns packages for the specified repo" do
      @repo_scoped_query.phrase = "acme"

      assert_equal [@widget], @repo_scoped_query.execute.results.map { |result| result["_model"] }
    end
  end

  context "owner scoped queries" do
    test "only returns packages for the specified owner" do
      @owner_scoped_query.phrase = "acme"

      assert_same_elements [@widget, @cog], @owner_scoped_query.execute.results.map { |result| result["_model"] }
    end
  end

  context "package type scoped queries" do
    test "only returns packages for the specified owner" do
      @package_type_scoped_query.phrase = "acme"

      assert_same_elements [@cog], @package_type_scoped_query.execute.results.map { |result| result["_model"] }
    end
  end

  context ".build_sort" do
    test "returns nil when the sort is empty and a query is present" do
      @unscoped_query.query = "foo"
      assert_nil @unscoped_query.build_sort
    end

    test "returns the default sort when the sort is empty" do
      assert_equal([{ "downloads" => "desc" }, "_score"], @unscoped_query.build_sort)
    end

    test "maps the sort field for created" do
      @unscoped_query.sort = %w[created asc]
      assert_equal([{ "created_at" => { "order" => "asc", "unmapped_type" => "date" } }, "_score"], @unscoped_query.build_sort)
    end
  end
end
