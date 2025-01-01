# typed: true
# frozen_string_literal: true

require "test_helper"

class TokenScanningConfigurationFileTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @config_repo = create(:repository, owner: @user, name: @user.config_repo_name)
  end

  context "#initialize" do
    test "noop's if file is too large" do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => "some/file.txt", "size" => 1048577) # size is 1mb + 1b
      token_scanning_config = TokenScanningConfigurationFile.new(blob)

      assert_nil token_scanning_config.name
    end
  end

  context "#name" do
    test "returns name of blob" do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => "some/file.txt")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)

      assert_equal "file.txt", token_scanning_config.name
    end
  end

  context "#ignore_path?" do
    test "true when file path has absolute match in config." do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "paths-ignore:\n  - \"app/test.rb\"")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)

      assert token_scanning_config.ignore_path?("app/test.rb")
    end

    test "true when config has a wildcard on parent path." do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "paths-ignore:\n  - \"app/*\"")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)
      assert token_scanning_config.ignore_path?("app/test.rb")
    end

    test "true when config has a wildcard with specific extension." do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "paths-ignore:\n  - \"app/*.rb\"")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)

      assert token_scanning_config.ignore_path?("app/test.rb")
    end

    test "false when config has a wildcard with specific extension that doesnt match." do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "paths-ignore:\n  - \"app/*.rb\"")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)

      assert !token_scanning_config.ignore_path?("app/test.md")
    end

    test "false when config has a wildcard parent directory that does not contain test path." do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "paths-ignore:\n  - \"config/*\"")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)

      assert !token_scanning_config.ignore_path?("app/test.md")
    end

    test "true when config has a recursive wildcard with a specific extension." do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "paths-ignore:\n  - \"**/*.rb\"")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)

      assert token_scanning_config.ignore_path?("app/test.rb")
      assert token_scanning_config.ignore_path?("app/foo/test.rb")
      assert token_scanning_config.ignore_path?("app/foo/bar/baz/ruby.rb")

      # false when extension is different
      assert !token_scanning_config.ignore_path?("config/testing/integrations/fake_directory/test.json")
    end

    test "true when config has a recursive parent wildcard with a specific end path." do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "paths-ignore:\n\  - \"**/contributions/*.json\"")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)

      assert token_scanning_config.ignore_path?("foo/app/contributions/routes.json")
      assert token_scanning_config.ignore_path?("bar/testing/contributions/test_fixtures.json")
      assert token_scanning_config.ignore_path?("/contributions/app.json")

      # false when file isnt under contributions
      assert !token_scanning_config.ignore_path?("test.json")
    end


    test "true when config has multiple paths that match." do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "paths-ignore:\n  - \"app/*\"\n  - \"test/*\"")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)

      assert token_scanning_config.ignore_path?("app/test.rb")
      assert token_scanning_config.ignore_path?("test/test.rb")
      assert token_scanning_config.ignore_path?("app/test/file.rb")

      # false when extension is different
      assert !token_scanning_config.ignore_path?("config/testing/integrations/fake_directory/test.json")
    end

    test "true case-insensitive" do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "paths-ignore:\n  - \"app/configuration/test.rb\"")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)
      assert token_scanning_config.ignore_path?("aPp/CoNfIgUrAtIoN/tEsT.rB")
    end
  end

  context "bad config file" do
    test "false if config does not contain paths-ignore" do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "bad-config:\n  - \"app/test.rb\"")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)
      assert !token_scanning_config.ignore_path?("app/test.rb")
    end

    test "false if config does not have colon after paths-ignore" do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "paths-ignore\n  - \"app/test.rb\"")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)
      assert !token_scanning_config.ignore_path?("app/test.rb")
    end

    test "false if paths are on same line" do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "paths-ignore:  - \"bin/test.rb\" - \"app/test.rb\"")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)
      assert !token_scanning_config.ignore_path?("app/test.rb")
    end

    test "false if paths are not separated by dashes" do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "paths-ignore:\n \"bin/test.rb\"\n \"app/test.rb\"")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)
      assert !token_scanning_config.ignore_path?("app/test.rb")
    end

    test "true even if paths are not in quotes" do
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => "paths-ignore:\n  - app/test.rb")
      token_scanning_config = TokenScanningConfigurationFile.new(blob)
      assert token_scanning_config.ignore_path?("app/test.rb")
    end

    test "only reads first 1000 patterns" do
      file_data = ["paths-ignore:"]
      [*0..1000].each do
        file_data << "\n  - app/#{SecureRandom.hex(8)}.rb"
      end
      file_data << "\n  - app/test.rb" # should be ignored since its the 1001st entry
      blob = TreeEntry.new(@config_repo, "type" => "blob", "oid" => "a" * 40,
                           "path" => TokenScanningConfigurationFile::DEFAULT_NAME,
                           "data" => file_data.join(""))
      token_scanning_config = TokenScanningConfigurationFile.new(blob)
      assert !token_scanning_config.ignore_path?("app/test.rb")
    end
  end
end
