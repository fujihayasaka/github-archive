# typed: true
# frozen_string_literal: true

require "fileutils"
require "test_helper"
require "tmpdir"
require "zip"
require "azure/core/http/http_error"
require "azure/core/http/http_response"

class CodeqlDatabase::ZipValidationTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner)
    @database = CodeqlDatabase.create!(
      repository: @repo, uploader: @owner, state: :uploaded, size: 1234,
      name: "database.zip", content_type: "application/zip", language: "python"
    )
  end

  setup do
    @azure_client = mock("Azure::Storage::Blob::BlobService")
    CodeScanningQueriesHelper.stubs(:azure_client).returns(@azure_client)

    @tmp_dir = File.expand_path("#{Dir.tmpdir}/CodeqlDatabaseTest_#{Time.now.to_i}/")
    FileUtils.mkdir_p(@tmp_dir)
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir) if @tmp_dir && File.exist?(@tmp_dir)
  end

  class MockedAzureHttpResponse
    attr_reader :uri, :status_code, :body

    def initialize
      @uri = "http://example.com/"
      @status_code = 404
      @body = "Not found"
    end
  end

  context "#validate_database_contents" do
    test "Database contents not found" do
      @azure_client.stubs(:get_blob).raises(::Azure::Core::Http::HTTPError.new(MockedAzureHttpResponse.new))

      assert_equal "Could not read database contents", @database.validate_database_contents
    end

    test "Database contents is not a valid zip file" do
      @azure_client.expects(:get_blob).returns([nil, "some garbage"]).once

      assert_equal "Upload does not appear to be a valid CodeQL database", @database.validate_database_contents
    end

    test "Database contents is a zip file but does not contain codeql-database.yml" do
      zip_filename = "#{@tmp_dir}/database.zip"
      Zip::File.open(zip_filename, create: true) do |zipfile|
        zipfile.get_output_stream("foo.txt") { |f| f.write "Some file contents" }
      end

      zip_file_contents = File.read(zip_filename, encoding: "ASCII-8BIT")
      @azure_client.expects(:get_blob).returns([nil, zip_file_contents]).once

      assert_equal "Upload does not appear to be a valid CodeQL database", @database.validate_database_contents
    end

    test "Database contains valid codeql-database.yml file" do
      zip_filename = "#{@tmp_dir}/database.zip"
      Zip::File.open(zip_filename, create: true) do |zipfile|
        zipfile.get_output_stream("python/codeql-database.yml") do |f|
          f.write "something" # The contents currently don't matter
        end
      end

      zip_file_contents = File.read(zip_filename, encoding: "ASCII-8BIT")
      @azure_client.expects(:get_blob).returns([nil, zip_file_contents]).once

      assert_nil @database.validate_database_contents
    end
  end
end
