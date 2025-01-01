# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class PorterSerializersTest < Api::SerializerTestCase
  fixtures do
    @user = create :user, login: "spraints"
    @repo = create :repository, owner: @user, name: "bokbok"
  end

  setup do
    GitHub.porter_url_template = "http://porter/{owner}/{repository}/etc"
  end

  # Serialize `data_from_porter` and compare the result with the
  # `expected_data`. URLs are not included in the comparison.
  def assert_porter_serialization(data_from_porter:, expected:)
    # URLs should always be present.
    expected.update \
      "repository_url" => %r{/repos/spraints/bokbok\z},
      "url"            => %r{/repos/spraints/bokbok/import\z},
      "authors_url"    => %r{/repos/spraints/bokbok/import/authors\z},
      "html_url"       => %r{://#{GitHub.host_name}/spraints/bokbok/import\z}

    # Run the serializer.
    hash = Api::Serializer.serialize(:porter_import_hash, data_from_porter, Api::SerializerOptions.fill(repo: @repo))
    actual = GitHub::JSON.parse(GitHub::JSON.encode(hash))

    assert_equal2 expected, actual
  end

  # Help me figure out what parts of the hash are different.
  def assert_equal2(exp, act)
    assert_equal(exp.keys.sort, act.keys.sort)
    exp.each_key do |k|
      case exp[k]
      when Regexp
        assert_match exp[k], act[k], "data[#{k.inspect}]"
      when NilClass
        assert_nil act[k], "data[#{k.inspect}]"
      else
        assert_equal exp[k], act[k], "data[#{k.inspect}]"
      end
    end
  end

  context "#porter_import_hash" do
    # These tests show data when someone has provided a URL in the UI,
    # but porter hasn't yet figured out what type of source control is there.
    #
    # See also the following files in github/porter:
    # * app/api/import_api/repository_info_builder.rb
    # * app/models/inferred_detection.rb

    test "detecting" do
      assert_porter_serialization(expected: {
        "vcs" => nil,
        "vcs_url" => "https://example.com/unknown/vcs",
        "status" => "detecting",
      }, data_from_porter: {
        "vcs_url" => "https://example.com/unknown/vcs",
        "status" => "detecting",
      })
    end

    test "detection needs authentication" do
      assert_porter_serialization(expected: {
        "vcs" => nil,
        "vcs_url" => "https://example.com/unknown/vcs",
        "status" => "detection_needs_auth",
        "message" => "Authorization for https://example.com/unknown/vcs is required. Please refer to the documentation for instruction on how to provide your credentials.",
      }, data_from_porter: {
        "vcs_url" => "https://example.com/unknown/vcs",
        "status" => "auth",
      })
    end

    test "detection found no repositories" do
      assert_porter_serialization(expected: {
        "vcs" => nil,
        "vcs_url" => "https://example.com/unknown/vcs",
        "status" => "detection_found_nothing",
        "message" => "No projects were found at the given url.",
      }, data_from_porter: {
        "vcs_url" => "https://example.com/unknown/vcs",
        "status" => "none",
      })
    end

    test "detection found more than one repository" do
      assert_porter_serialization(expected: {
        "vcs" => nil,
        "vcs_url" => "https://example.com/unknown/vcs",
        "status" => "detection_found_multiple",
        "message" => "Multiple projects were found at the given url. Please refer to the documentation for instruction on how to provide your project choice.",
      }, data_from_porter: {
        "vcs_url" => "https://example.com/unknown/vcs",
        "status" => "choose",
      })
    end

    # These tests include examples of data from porter when detection is
    # finished, or when the import has been started via the API.
    #
    # See also the following files in github/porter:
    # * app/api/import_api/repository_info_builder.rb
    # * app/models/found_repository_status.rb

    # The normal progression is linear, through the following steps:
    test "queued for import" do
      assert_porter_serialization(expected: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",

        "status" => "importing",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_count" => 0,

        "import_percent" => nil,
        "commit_count" => nil,
      }, data_from_porter: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        # When "vcs" is not nil, these attributes are always present in porter's response:
        "status" => "setup",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_found" => 0,
        # These attributes are sometimes present, depending on the value of "vcs":
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",
        # These attributes are present, based on the current "status":
        # n/a for "setup"

        # These attributes are present if lfs is enabled for the user:
        "has_large_files" => false,
        "large_files_size" => 0,
      })
    end

    test "importing, empty progress" do
      assert_porter_serialization(expected: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",

        "status" => "importing",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_count" => 0,

        "import_percent" => nil,
        "commit_count" => nil,
      }, data_from_porter: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        # When "vcs" is not nil, these attributes are always present in porter's response:
        "status" => "importing",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_found" => 0,
        # These attributes are sometimes present, depending on the value of "vcs":
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",
        # These attributes are present, based on the current "status":
        "percent" => nil,
        "commit_count" => nil,
        # These attributes are present in porter's response if lfs is enabled for the user
        # porter_dependency will remove them if status is not "complete", "waiting_to_push", or "pushing"
        "has_large_files" => false,
        "large_files_size" => 0,
      })
    end

    test "importing, with progress" do
      assert_porter_serialization(expected: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",

        "status" => "importing",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_count" => 4,

        "import_percent" => 12,
        "commit_count" => 3456,
      }, data_from_porter: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        # When "vcs" is not nil, these attributes are always present in porter's response:
        "status" => "importing",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_found" => 4,
        # These attributes are sometimes present, depending on the value of "vcs":
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",
        # These attributes are present, based on the current "status":
        "percent" => 12,
        "commit_count" => 3456,
        # These attributes are present if lfs is enabled for the user:
        "has_large_files" => false,
        "large_files_size" => 0,
      })
    end

    test "mapping" do
      assert_porter_serialization(expected: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",

        "status" => "mapping",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_count" => 78,
      }, data_from_porter: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        # When "vcs" is not nil, these attributes are always present in porter's response:
        "status" => "mapping",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_found" => 78,
        # These attributes are sometimes present, depending on the value of "vcs":
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",
        # These attributes are present, based on the current "status":
        # n/a for "mapping"

        # These attributes are present if lfs is enabled for the user:
        "has_large_files" => false,
        "large_files_size" => 0,
      })
    end

    test "pushing, empty progress" do
      assert_porter_serialization(expected: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",

        "status" => "pushing",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_count" => 78,

        "push_percent" => nil,

        "has_large_files" => false,
        "large_files_size" => 0,
      }, data_from_porter: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        # When "vcs" is not nil, these attributes are always present in porter's response:
        "status" => "pushing",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_found" => 78,
        # These attributes are sometimes present, depending on the value of "vcs":
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",
        # These attributes are present, based on the current "status":
        "push_percent" => nil,
        # These attributes are present if lfs is enabled for the user:
        "has_large_files" => false,
        "large_files_size" => 0,
      })
    end

    test "pushing, with progress" do
      assert_porter_serialization(expected: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",

        "status" => "pushing",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_count" => 78,

        "push_percent" => 33,

        "has_large_files" => false,
        "large_files_size" => 0,
      }, data_from_porter: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        # When "vcs" is not nil, these attributes are always present in porter's response:
        "status" => "pushing",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_found" => 78,
        # These attributes are sometimes present, depending on the value of "vcs":
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",
        # These attributes are present, based on the current "status":
        "push_percent" => 33,
        # These attributes are present if lfs is enabled for the user:
        "has_large_files" => false,
        "large_files_size" => 0,
      })
    end

    test "waiting to push" do
      # This state shouldn't happen anymore, but there's a code path to it.
      assert_porter_serialization(expected: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",

        "status" => "waiting_to_push",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_count" => 78,

        "has_large_files" => false,
        "large_files_size" => 0,
      }, data_from_porter: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        # When "vcs" is not nil, these attributes are always present in porter's response:
        "status" => "waiting_to_push",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_found" => 78,
        # These attributes are sometimes present, depending on the value of "vcs":
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",
        # These attributes are present, based on the current "status":
        # n/a for "waiting_to_push"

        # These attributes are present if lfs is enabled for the user:
        "has_large_files" => false,
        "large_files_size" => 0,
      })
    end

    test "done" do
      assert_porter_serialization(expected: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",

        "status" => "complete",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_count" => 78,

        "has_large_files" => false,
        "large_files_size" => 0,
      }, data_from_porter: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        # When "vcs" is not nil, these attributes are always present in porter's response:
        "status" => "complete",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_found" => 78,
        # These attributes are sometimes present, depending on the value of "vcs":
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",
        # These attributes are present, based on the current "status":
        "url" => "http://github.com/owner/repository",
        # These attributes are present if lfs is enabled for the user:
        "has_large_files" => false,
        "large_files_size" => 0,
      })
    end

    # Some error cases:
    test "authentication failed during import" do
      assert_porter_serialization(expected: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",

        "status" => "auth_failed",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_count" => 78,

        "message" => "Authorization for https://example.com/code failed. Please refer to the documentation for instruction on how to provide your credentials.",
      }, data_from_porter: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        # When "vcs" is not nil, these attributes are always present in porter's response:
        "status" => "auth_failed",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_found" => 78,
        # These attributes are sometimes present, depending on the value of "vcs":
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",
        # These attributes are present, based on the current "status":
        # n/a for "auth_failed"
      })
    end

    test "error, with a message" do
      assert_porter_serialization(expected: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",

        "status" => "error",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_count" => 78,

        "failed_step" => "importing",
        "message" => "Some error message from porter",
      }, data_from_porter: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        # When "vcs" is not nil, these attributes are always present in porter's response:
        "status" => "error",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_found" => 78,
        # These attributes are sometimes present, depending on the value of "vcs":
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",
        # These attributes are present, based on the current "status":
        "failed_step" => "importing",
        "error_message" => "Some error message from porter",
      })
    end

    test "error, without a message" do
      assert_porter_serialization(expected: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",

        "status" => "error",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_count" => 78,

        "failed_step" => "importing",
        "message" => "There was an error importing commits.",
      }, data_from_porter: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        # When "vcs" is not nil, these attributes are always present in porter's response:
        "status" => "error",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_found" => 78,
        # These attributes are sometimes present, depending on the value of "vcs":
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",
        # These attributes are present, based on the current "status":
        "failed_step" => "importing",
        "error_message" => "There was an error importing commits.",
      })
    end

    # This one should never happen, but there's a code path to it.
    test "unknown" do
      assert_porter_serialization(expected: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",

        "status" => "unknown",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_count" => 78,
      }, data_from_porter: {
        "vcs" => "anything",
        "vcs_url" => "https://example.com/code",
        # When "vcs" is not nil, these attributes are always present in porter's response:
        "status" => "unknown",
        "status_text" => TEXT_VERSION_OF_STATUS,
        "authors_found" => 78,
        # These attributes are sometimes present, depending on the value of "vcs":
        "tfvc_project" => "anything",
        "svn_root" => "http://anything",
        # These attributes are present, based on the current "status":
        # n/a for "unknown"
      })
    end
  end

  # Porter includes an humanized version of the status string (sometimes).
  # GitHub shouldn't try to interpret this string at all.
  TEXT_VERSION_OF_STATUS = "Text version of 'status'".freeze
end
