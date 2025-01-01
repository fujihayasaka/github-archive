# typed: true
# frozen_string_literal: true

require "test_helper"

class Api::App::SecretScanningHelpersTest < GitHub::TestCase

  fixtures do
    @repo = create :repository
  end

  context "verify get_raw_secret_from_first_location" do
    test "returns non-empty raw token for multiline secrets when end_column matches length of last line" do
      blob_oid = SecureRandom.hex(20)
      blob_content = "# internal\n\n\ntestmepls\nmultiline\n"
      expected_token = " internaltestmeplsmultiline"
      multiline_token = GitHub::TokenScanning::FoundToken.new(
        type: "STRIPE",
        token: SecureRandom.hex(32),
        url: "",
        report_url: "",
        path: "foo.txt",
        commit: SecureRandom.hex(20),
        blob: blob_oid,
        start_line: 1,
        end_line: 6,
        start_column: 1,
        end_column: 0,
        content_type: 1
      )
      alert = TokenScanResult.create_from_found_token!(@repo, "STRIPE", multiline_token.token)
      TokenScanResultLocation.create_from_found_token!(alert, multiline_token)
      blob = {
        "type" => "blob",
        "data" => blob_content,
        "truncated" => false,
        "oid" => blob_oid,
        "encoding" => "UTF-8",
        "binary" => false
      }

      result = SecretScanning::Util::RawSecret.get_raw_secret_from_first_location alert, @repo, { blob["oid"] => blob }

      assert_equal expected_token, result
    end

    test "handles non-utf8 characters" do
      blob_oid = SecureRandom.hex(20)
      blob_content = "random_line\nこんにちは foobar\nrandom_line"
      expected_token = "foobar"
      multiline_token = GitHub::TokenScanning::FoundToken.new(
        type: "STRIPE",
        token: SecureRandom.hex(32),
        url: "",
        report_url: "",
        path: "foo.txt",
        commit: SecureRandom.hex(20),
        blob: blob_oid,
        start_line: 2,
        end_line: 2,
        start_column: 16,
        end_column: 22,
        content_type: 1
      )
      alert = TokenScanResult.create_from_found_token!(@repo, "STRIPE", multiline_token.token)
      TokenScanResultLocation.create_from_found_token!(alert, multiline_token)
      blob = {
        "type" => "blob",
        "data" => blob_content,
        "truncated" => false,
        "oid" => blob_oid,
        "encoding" => "UTF-8",
        "binary" => false
      }

      result = SecretScanning::Util::RawSecret.get_raw_secret_from_first_location alert, @repo, { blob["oid"] => blob }

      assert_equal expected_token, result
    end

    test "handles GB18030 characters" do
      blob_oid = SecureRandom.hex(20)
      blob_content = "random_line\nこんにちは foobar\nrandom_line".dup.force_encoding("GB18030")
      expected_token = "foobar"
      multiline_token = GitHub::TokenScanning::FoundToken.new(
        type: "STRIPE",
        token: SecureRandom.hex(32),
        url: "",
        report_url: "",
        path: "foo.txt",
        commit: SecureRandom.hex(20),
        blob: blob_oid,
        start_line: 2,
        end_line: 2,
        start_column: 25,
        end_column: 31,
        content_type: 1
      )
      alert = TokenScanResult.create_from_found_token!(@repo, "STRIPE", multiline_token.token)
      TokenScanResultLocation.create_from_found_token!(alert, multiline_token)
      blob = {
        "type" => "blob",
        "data" => blob_content,
        "truncated" => false,
        "oid" => blob_oid,
        "encoding" => "UTF-8",
        "binary" => false
      }

      result = SecretScanning::Util::RawSecret.get_raw_secret_from_first_location alert, @repo, { blob["oid"] => blob }

      assert_equal expected_token, result
    end
  end

  context "get first locations" do
    test "get first locations leaves out nil entries" do
      alerts = [
        GitHub::Proto::SecretScanning::Api::V2::Token.new(
          created_at: Time.parse("2022-03-25"),
          first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "path/to/file.rb"),
          id: 1,
          label: "Amazon AWS Secret Access Key",
          repository_id: @repo.id,
          number: 1
        ),
        GitHub::Proto::SecretScanning::Api::V2::Token.new(
          created_at: Time.parse("2022-03-25"),
          first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "path/to/file.rb"),
          id: 2,
          label: "Adafruit IO Key",
          repository_id: @repo.id,
          number: 2
        ),
        GitHub::Proto::SecretScanning::Api::V2::Token.new(
          created_at: Time.parse("2022-03-25"),
          first_location: nil,
          id: 3,
          label: "Amazon AWS Secret Access Key",
          repository_id: @repo.id,
          number: 3
        ),
      ]

      first_locations = Api::App::SecretScanningHelpers.get_first_locations(alerts)

      first_locations.each do |location|
        refute_nil location
      end
    end
  end
end
