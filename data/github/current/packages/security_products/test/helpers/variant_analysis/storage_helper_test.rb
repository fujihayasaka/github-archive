# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/variant_analysis/query_pack_helper"

module VariantAnalysis
  class StorageHelperTest < GitHub::TestCase
    include VariantAnalysis::QueryPackHelper

    fixtures do
      @variant_analysis = create(:codeql_variant_analysis)
      @query_pack = Base64.strict_encode64(gzip(tar("library: false\nname: codeql-remote/query\n")))
    end

    def setup
      @helper = FakeHelper.new.extend(StorageHelper)
      @azure_client = mock("Azure::Storage::Blob::BlobService")
      CodeScanningQueriesHelper.stubs(:azure_client).returns(@azure_client)
    end

    context "#upload_instructions_file" do
      test "upload instructions file uploads content and gets url" do
        content = "some-json"

        @azure_client.expects(:create_block_blob).once.with do |container, target, contents, options|
          assert_equal "variant_analyses/#{@variant_analysis.id}/instructions", target
          assert_equal GitHub.codeql_variant_analysis_azure_bucket, container
          assert_equal content, contents
          assert_equal ({ content_type: "application/json" }), options
        end

        signed_url = @helper.upload_instructions_file(@variant_analysis, content)

        refute_nil signed_url
      end
    end

    context "#upload_query_pack" do
      test "upload query pack uploads content and returns the file path" do
        content = "some-json"
        expected_path = "variant_analyses/#{@variant_analysis.id}/query_pack"

        @azure_client.expects(:create_block_blob).once.with do |container, target, contents, options|
          assert_equal expected_path, target
          assert_equal GitHub.codeql_variant_analysis_azure_bucket, container
          assert_equal content, contents
          assert_equal ({ content_type: "application/gzip" }), options
        end

        assert_equal expected_path, @helper.upload_query_pack(@variant_analysis, content)
      end
    end

    context "#process_query_pack" do
      test "decodes query pack" do
        assert_equal @helper.process_query_pack(@query_pack), Base64.strict_decode64(@query_pack)
      end

      test "raises error if query pack is not base64 encoded" do
        assert_raises(StorageHelper::InvalidBase64QueryPackError, "Could not decode query pack content. Expected Base64 encoded gzipped tarball.") do
          @helper.process_query_pack("😄")
        end
      end

      test "raises error if query pack is not gzipped" do
        assert_raises(StorageHelper::InvalidGzipQueryPackError, "Query pack is not a valid gzip file") do
          @helper.process_query_pack(Base64.strict_encode64("not a gzip"))
        end
      end
    end

    context "#is_query_pack_gzip?" do
      test "returns true for zip query pack" do
        assert @helper.is_query_pack_gzip?(gzip(""))
        assert @helper.is_query_pack_gzip?(gzip(tar("")))
        assert @helper.is_query_pack_gzip?(gzip(tar("name: codeql-remote/query\n", filename: "qlpack.yml")))
      end

      test "returns false for anything else" do
        refute @helper.is_query_pack_gzip?(Base64.strict_encode64("not a gzip"))
        refute @helper.is_query_pack_gzip?("not-a-gzip")
        refute @helper.is_query_pack_gzip?(gzip("")[1..])
        refute @helper.is_query_pack_gzip?("")
      end
    end
  end
end
