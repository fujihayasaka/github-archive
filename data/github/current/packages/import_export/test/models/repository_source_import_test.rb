# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositorySourceImportTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: user)
  end

  setup do
    @porter_client = mock
    @repository_import = RepositorySourceImport.new(
      user: user,
      repository: repo,
    )
    repository_import.porter_client = porter_client
  end

  attr_reader :user, :repo, :repository_import, :porter_client

  test "#porter_client builds a porter client" do
    repository_import.porter_client = nil

    assert repository_import.porter_client.is_a?(Porter::ApiClient)
  end

  test "#provide_auth calls porter_client.update_import with auth info and sets import_status_hash" do
    import_status_hash = { test_name: __method__ }
    porter_client.expects(:update_import).with({
      vcs_username: "jonmagic",
      vcs_password: "password",
    }).returns(import_status_hash)

    repository_import.provide_auth(
      vcs_username: "jonmagic",
      vcs_password: "password",
    )

    assert_equal import_status_hash, repository_import.import_status_hash
  end

  test "#choose_project calls porter_client.update_import with project choice and sets import_status_hash" do
    # Set up the initial import status hash.
    repository_import.import_status_hash = {
      "project_choices" => [
        { "favorite" => "breakfast cereal", "name" => "golden grahams" },
        { "porter" => "can set these to whatever it wants" },
      ],
    }

    # Prepare the fake porter client to update the import status hash
    import_status_hash = { test_name: __method__ }
    porter_client.expects(:update_import).with({
      "porter" => "can set these to whatever it wants",
    }).returns(import_status_hash)

    # you pays your money and you takes you choice
    repository_import.choose_project(repository_import.projects.last)

    # porter says "sounds good boss"
    assert_equal import_status_hash, repository_import.import_status_hash
  end

  test "#start_import calls porter_client.start_import with vcs_url, sets import_status_hash, and calls repository.importing_started!" do
    import_status_hash = { test_name: __method__ }
    porter_client.expects(:start_import).with(equals({
      vcs_url: "https://subversion.foo.bar/p1",
    })).returns(import_status_hash)
    repo.expects(:importing_started!)

    repository_import.start_import(vcs_url: "https://subversion.foo.bar/p1")

    assert_equal import_status_hash, repository_import.import_status_hash
  end

  test "#start_import records stats to datadog" do
    import_status_hash = { test_name: __method__ }
    porter_client.stubs(:start_import).with(equals({
      vcs_url: "https://subversion.foo.bar/p1",
    })).returns(import_status_hash)
    repo.stubs(:importing_started!)

    repository_import.start_import(vcs_url: "https://subversion.foo.bar/p1")
    assert_dogstats_increment(1, "repository.import", tags: ["status:started"])
  end

  test "#start_import disables actions on the repository" do
    assert @repo.actions_enabled?

    import_status_hash = { test_name: __method__ }
    porter_client.stubs(:start_import).with(equals({
      vcs_url: "https://subversion.foo.bar/p1",
    })).returns(import_status_hash)
    repo.stubs(:importing_started!)

    repository_import.start_import(vcs_url: "https://subversion.foo.bar/p1")
    @repo.reload

    assert @repo.actions_disabled?
  end

  test "#stop_import calls porter_client.stop_import" do
    porter_client.expects(:stop_import)

    repository_import.stop_import
  end

  test "#stop_import records stats to datadog" do
    porter_client.stubs(:stop_import)

    repository_import.stop_import
    assert_dogstats_increment(1, "repository.import", tags: ["status:stopped"])
  end

  test "#restart_import calls porter_client.update_import and sets import_status_hash" do
    import_status_hash = { test_name: __method__ }
    porter_client.expects(:update_import).returns(import_status_hash)

    repository_import.restart_import

    assert_equal import_status_hash, repository_import.import_status_hash
  end

  test "#restart_import records stats to datadog" do
    import_status_hash = { test_name: __method__ }
    porter_client.stubs(:update_import).returns(import_status_hash)

    repository_import.restart_import

    assert_dogstats_increment(1, "repository.import", tags: ["status:restarted"])
  end

  test "#lfs_opt_in calls porter_client.opt_in_to_lfs with data" do
    data = { data: __method__ }
    porter_client.expects(:set_lfs_preference).with(data.merge("use_lfs" => "opt_in"))

    repository_import.lfs_opt_in(data)
  end

  test "#lfs_opt_out calls porter_client.opt_out" do
    data = { data: __method__ }
    porter_client.expects(:set_lfs_preference).with(data.merge("use_lfs" => "opt_out"))

    repository_import.lfs_opt_out(data)
  end

  test "#status? returns false if the current status is nil" do
    repository_import.import_status_hash = { "otherfield" => nil }
    refute repository_import.status?(:auth)
  end

  test "#status? returns true if the current status is in list of statuses" do
    set_status("detecting")
    refute repository_import.status?(:auth), "status is not auth"

    set_status("auth")
    assert repository_import.status?(:auth, :auth_failed), "status should be auth or auth failed"
    set_status("auth_failed")
    assert repository_import.status?(:auth, :auth_failed), "status should be auth or auth failed"

    set_status("detecting")
    assert repository_import.status?(:detecting), "status should be detecting"
  end

  test "#status returns symbol of value from status key in import_status_hash" do
    repository_import.import_status_hash = { "status" => "swimming" }

    assert_equal :swimming, repository_import.status
  end

  def set_status(status)
    repository_import.stubs(import_status_hash: { "status" => status })
  end

  test "#authors calls porter_client.authors if authors_found is present in import_status_hash" do
    porter_client.expects(:authors).with(since: 0).returns([
      {
        "id" => 1,
        "remote_id" => "hoyt@foo-1234",
        "remote_name" => "JonMagic",
        "email" => nil,
        "name" => nil,
        "github_user" => nil,
      },
    ])
    repository_import.import_status_hash = { "authors_found" => 1 }

    author = repository_import.authors.first

    assert_equal 1, author.id
    assert_equal "hoyt@foo-1234", author.remote_id
    assert_equal "JonMagic", author.remote_name
    assert_nil author.email
    assert_nil author.name
    assert_nil author.login
  end

  test "#authors returns empty array if authors_found is not present" do
    porter_client.expects(:authors).never
    repository_import.import_status_hash = {}

    assert_predicate repository_import.authors, :empty?
  end

  test "#update_author calls porter_Client.update_author with id and details hash and returns Author" do
    author_details = {
      "id" => 1,
      "remote_id" => "hoyt@foo-1234",
      "remote_name" => "JonMagic",
      "email" => "jonmagic@gmail.com",
      "name" => "Jonathan Hoyt",
      "github_user" => "jonmagic",
    }
    porter_client.expects(:update_author).with(1,
      author_details.slice("email", "name", "github_user").symbolize_keys,
    ).returns(author_details)

    author_updates = {
      author_id: 1,
      email: "jonmagic@gmail.com",
      name: "Jonathan Hoyt",
      login: "jonmagic",
    }
    author = repository_import.update_author(**author_updates)

    assert_equal "JonMagic", author.remote_name
    assert_equal "jonmagic@gmail.com", author.email
    assert_equal "Jonathan Hoyt", author.name
    assert_equal "jonmagic", author.login
  end

  test "#projects returns projects built from project_choices in the import_status_hash" do
    repository_import.import_status_hash = {
      "project_choices" => [
        { "this" => "does not matter", "this also" => "does not matter", "human_name" => "My Project" },
      ],
    }

    project = repository_import.projects.first

    assert_equal 1, repository_import.projects.size, "number of projects"
    assert_equal "49b44bcf65bd9d7e8b450d6a5385207d79e88a4222368b4fd00e907db0000d77", project.to_param, "Project's param form is a SHA256 hash of the options"
    assert_equal "My Project", project.name, "Project's name"
    assert_equal "My Project", project.to_s, "Project's string form"
    assert_equal({ "this" => "does not matter", "this also" => "does not matter", "human_name" => "My Project" }, project.for_update, "data to use in PATCH request")
  end

  test "#has_large_files? is true if the value for has_large_files in import_status_hash is true" do
    repository_import.import_status_hash = { "has_large_files" => true }

    assert_predicate repository_import, :has_large_files?
  end

  test "#has_large_files? is false if the value for has_large_files in import_status_hash is false" do
    repository_import.import_status_hash = { "has_large_files" => false }

    refute_predicate repository_import, :has_large_files?
  end

  test "#has_large_files? is false there is no has_large_files key in import_status_hash" do
    repository_import.import_status_hash = {}

    refute_predicate repository_import, :has_large_files?
  end

  test "#large_file_details calls porter_client.large_files and returns LargeFileDetails instance" do
    pagination = { page: 1 }
    porter_client.expects(:large_files).with(pagination).returns({
      "total_count" => 1,
      "total_size" => 1234,
      "entries" => [
        "foo",
      ],
    })

    large_file_details = repository_import.large_file_details(pagination)

    assert_equal 1, large_file_details.large_files_count
    assert_equal 1234, large_file_details.large_files_size
    assert_equal ["foo"], large_file_details.files
  end

  test "#error_message returns error_message from import_status_hash" do
    repository_import.import_status_hash = { "error_message" => "everything is terrible" }

    assert_equal "everything is terrible", repository_import.error_message
  end

  test "#push_percent returns 0 if push_percent key is not in import_status_hash" do
    repository_import.import_status_hash = {}

    assert_equal 0, repository_import.push_percent
  end

  test "#push_percent returns value of push_percent in import_status_hash" do
    repository_import.import_status_hash = { "push_percent" => 7 }

    assert_equal 7, repository_import.push_percent
  end

  test "#import_percent returns 0 if percent key is not in import_status_hash" do
    repository_import.import_status_hash = {}

    assert_equal 0, repository_import.import_percent
  end

  test "#import_percent returns value of percent in import_status_hash" do
    repository_import.import_status_hash = { "percent" => 42 }

    assert_equal 42, repository_import.import_percent
  end

  test "#lfs_opt_needed? returns false status in not complete" do
    repository_import.import_status_hash = {
      "status" => "detecting",
      "has_large_files" => true,
      "use_lfs" => "undecided",
    }

    refute_predicate repository_import, :lfs_opt_needed?
  end

  test "#lfs_opt_needed? returns false if status is complete but has_large_files is false" do
    repository_import.import_status_hash = {
      "status" => "complete",
      "has_large_files" => false,
      "use_lfs" => "undecided",
    }

    refute_predicate repository_import, :lfs_opt_needed?
  end

  test "#lfs_opt_needed? returns false if status is complete, has_large_files is true, and use_lfs is 'opt_in'" do
    repository_import.import_status_hash = {
      "status" => "complete",
      "has_large_files" => true,
      "use_lfs" => "opt_in",
    }

    refute_predicate repository_import, :lfs_opt_needed?
  end

  test "#lfs_opt_needed? returns false if status is complete, has_large_files is true, and use_lfs is 'opt_out'" do
    repository_import.import_status_hash = {
      "status" => "complete",
      "has_large_files" => true,
      "use_lfs" => "opt_out",
    }

    refute_predicate repository_import, :lfs_opt_needed?
  end

  test "#lfs_opt_needed? returns true if status is complete, has_large_files is true, and use_lfs is 'undecided'" do
    repository_import.import_status_hash = {
      "status" => "complete",
      "has_large_files" => true,
      "use_lfs" => "undecided",
    }

    assert_predicate repository_import, :lfs_opt_needed?
  end

  test "#no_importer? returns false if porter.import_status doesn't raise error" do
    porter_client.expects(:import_status).returns({})

    refute_predicate repository_import, :no_importer?
  end

  test "#no_importer? returns true if porter.import_status raises Porter::ApiClient::Error with status 404" do
    porter_client.expects(:import_status).raises(Porter::ApiClient::Error.new({ status: 404 }))

    assert_predicate repository_import, :no_importer?
  end

  test "#no_importer? re-raises Porter::ApiClient::Error if status is not a 404" do
    porter_client.expects(:import_status).raises(Porter::ApiClient::Error.new({ status: 500 }))

    assert_raises(Porter::ApiClient::Error) do
      repository_import.no_importer?
    end
  end

  test "#authors_count returns value if present or 0" do
    repository_import.import_status_hash = { "authors_found" => 42 }
    assert_equal 42, repository_import.authors_count

    repository_import.import_status_hash = {}
    assert_equal 0, repository_import.authors_count
  end

  test "#import_status_hash calls porter_client.import_status" do
    import_status_hash = { test_name: __method__ }
    porter_client.expects(:import_status).returns(import_status_hash)

    assert_equal import_status_hash, repository_import.import_status_hash
  end

  test "#porter_client returns a new instance of Porter::ApiClient" do
    repository_import.porter_client = nil
    Porter::ApiClient.expects(:new).with(equals({
      current_user: user,
      current_repository: repo,
      timeout: 1,
      set_import_started: false,
      send_import_status: true,
    }))
    repository_import.porter_client
  end

  test "#url_params returns hash with repository and user_id keys based on repository and repository owner" do
    expected_result = {
      repository: repo,
      user_id: repo.owner.login,
    }

    assert_equal expected_result, repository_import.url_params
  end
end
