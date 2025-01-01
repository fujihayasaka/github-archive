# frozen_string_literal: true

require "rails_helper"

describe ManifestAdapters::Composer::Adapter do
  it "identifies malformed composer.json manifests" do
    manifest = described_class.new(github_repository_id: 1,
                                   filename: "",
                                   path: "",
                                   git_ref: "0000000000000000000000000000000000000000",
                                   pushed_at: Time.now,
                                   fork: false,
                                   visibility_private: false,
                                   content: "")
    expect(manifest.parse).to be_malformed

    specifically_blank_manifest = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                                      github_repository_id: 105,
                                                      filename: "composer.json",
                                                      path: "",
                                                      content: "",
                                                      pushed_at: Time.new(2019, 1, 1),
                                                      fork: false,
                                                      visibility_private: false)

    expect(specifically_blank_manifest.parse).to be_malformed


    not_json = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                               github_repository_id: 105,
                               filename: "composer.json",
                               path: "",
                               content: file_fixture(".nuspec").read,
                               pushed_at: Time.new(2019, 1, 1),
                               fork: false,
                               visibility_private: false)

    expect(not_json.parse).to be_malformed


    wrong_syntax = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                    github_repository_id: 105,
                                    filename: "composer.json",
                                    path: "",
                                    content: file_fixture("wrong_composer.json").read,
                                    pushed_at: Time.new(2019, 1, 1),
                                    fork: false,
                                    visibility_private: false)

    expect(wrong_syntax.parse).to be_malformed

    actually_a_lockfile = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                    github_repository_id: 105,
                                    filename: "composer.json",
                                    path: "",
                                    content: file_fixture("composer.lock").read,
                                    pushed_at: Time.new(2019, 1, 1),
                                    fork: false,
                                    visibility_private: false)

    expect(actually_a_lockfile.parse).to be_malformed

    malformed_dependency = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                               github_repository_id: 105,
                                               filename: "composer.json",
                                               path: "",
                                               content: file_fixture("malformed_dep_composer.json").read,
                                               pushed_at: Time.new(2019, 1, 1),
                                               fork: false,
                                               visibility_private: false)

    expect(malformed_dependency.parse).to_not be_malformed
    expect(malformed_dependency.parse.dependencies).to_not be_nil
    expect(malformed_dependency.parse.dependencies.length).to eq(4)
  end

  it "identifies valid composer.json file" do
    valid_manifest = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                               github_repository_id: 105,
                                               filename: "composer.json",
                                               path: "",
                                               content: file_fixture("composer.json").read,
                                               pushed_at: Time.new(2019, 1, 1),
                                               fork: false,
                                               visibility_private: false)

    expect(valid_manifest.parse).to_not be_malformed
    expect(valid_manifest.parse.dependent_name).to eq "github/github-in-php"
    expect(valid_manifest.parse.package_manager.to_s).to eq "composer"
    expect(valid_manifest.parse.dependencies).to_not be_nil
    expect(valid_manifest.parse.dependencies.length).to eq(7)
  end

  it "identifies malformed composer.lock manifests" do

    specifically_blank_manifest = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                                      github_repository_id: 105,
                                                      filename: "composer.lock",
                                                      path: "",
                                                      content: "",
                                                      pushed_at: Time.new(2019, 1, 1),
                                                      fork: false,
                                                      visibility_private: false)

    expect(specifically_blank_manifest.parse).to be_malformed


    not_json = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                               github_repository_id: 105,
                               filename: "composer.lock",
                               path: "",
                               content: file_fixture(".nuspec").read,
                               pushed_at: Time.new(2019, 1, 1),
                               fork: false,
                               visibility_private: false)

    expect(not_json.parse).to be_malformed


    wrong_syntax = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                    github_repository_id: 105,
                                    filename: "composer.lock",
                                    path: "",
                                    content: file_fixture("composer.json").read,
                                    pushed_at: Time.new(2019, 1, 1),
                                    fork: false,
                                    visibility_private: false)

    expect(wrong_syntax.parse).to be_malformed

    malformed_dependency = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                               github_repository_id: 105,
                                               filename: "composer.lock",
                                               path: "",
                                               content: file_fixture("malformed_dep_composer.lock").read,
                                               pushed_at: Time.new(2019, 1, 1),
                                               fork: false,
                                               visibility_private: false)

    expect(malformed_dependency.parse).to_not be_malformed
    expect(malformed_dependency.parse.dependencies).to_not be_nil
    expect(malformed_dependency.parse.dependencies.length).to eq(2)
  end

  it "identifies valid composer.lock file" do
    valid_manifest = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                               github_repository_id: 105,
                                               filename: "composer.lock",
                                               path: "",
                                               content: file_fixture("composer.lock").read,
                                               pushed_at: Time.new(2019, 1, 1),
                                               fork: false,
                                               visibility_private: false)

    expect(valid_manifest.parse).to_not be_malformed
    expect(valid_manifest.parse.dependent_name).to eq ""
    expect(valid_manifest.parse.dependent_version).to eq ""
    expect(valid_manifest.parse.package_manager.to_s).to eq "composer"
    expect(valid_manifest.parse.dependencies).to_not be_nil
    expect(valid_manifest.parse.dependencies.first.package_name).to eq "blah/blahblah"
    expect(valid_manifest.parse.dependencies.length).to eq(6)
  end

  it "does not break on composer.lock with empty branch aliases list" do
    # https://github.com/github/dependency-graph-api/issues/1243
    blank_branch_alias_content =  <<~MANIFEST
    {
        "packages": [
          {
              "name": "pingplusplus/pingpp-php",
              "version": "dev-master",
              "extra": {
                  "branch-alias": []
              }
          }
        ]
    }
    MANIFEST

    blank_branch_alias = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                               github_repository_id: 105,
                                               filename: "composer.lock",
                                               path: "",
                                               content: blank_branch_alias_content,
                                               pushed_at: Time.new(2019, 1, 1),
                                               fork: false,
                                               visibility_private: false)

    expect(blank_branch_alias.parse).to_not be_malformed
  end

  # Tests adressing parsing errors on manifests post-ship
  it "does not allow incorrect array usage in composer.json" do
    # https://github.com/github/dependency-graph-api/issues/1240
    malformed_array_json_content =  <<~MANIFEST
    [
        {
            "library": [
                "markitup",
                "expanding"
            ],
            "script": [
                "bbcode"
            ],
            "adapter": "EasyDiscuss"
        }
    ]
    MANIFEST

    malformed_array_json = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                               github_repository_id: 105,
                                               filename: "composer.json",
                                               path: "",
                                               content: malformed_array_json_content,
                                               pushed_at: Time.new(2019, 1, 1),
                                               fork: false,
                                               visibility_private: false)

    expect(malformed_array_json.parse).to be_malformed

    # https://github.com/github/dependency-graph-api/issues/1237
    array_requirements_json_content =  <<~MANIFEST
    {
      "name": "luettgens/cowis-import",
      "type": "Plugin",
      "license": "Copyright",
      "authors": [
        {
          "name": "Lukas Breuer",
          "email": "lukas.breuer@outlook.com"
        }
      ],
      "repositories": [
        {"type":"composer","url":"https://composer.giftgruen.com"}
      ],
      "require": [
        {"giftgruen/wp-helper": "^1.0.2"}
      ]
    }
    MANIFEST

    array_requirements_json = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                               github_repository_id: 105,
                                               filename: "composer.json",
                                               path: "",
                                               content: array_requirements_json_content,
                                               pushed_at: Time.new(2019, 1, 1),
                                               fork: false,
                                               visibility_private: false)

    expect(array_requirements_json.parse).to_not be_malformed
    expect(array_requirements_json.parse.dependencies).to be_empty
  end

  it "does not break on incorrect dependency formatting in composer.json" do
    # https://github.com/github/dependency-graph-api/issues/1230
    # test taken from #1233
    malformed_requirements_content = <<~MANIFEST
    {
      "name": "jemshid/composer-test",
      "description": "Test package",
      "type": "library",
      "license": "GPL",
      "authors": [{ "name": "jemshid123", "email": "jemshidmh@gmail.com" }],
      "minimum-stability": "dev",
      "require": {
        "psr-4": {
          "composerTest\\\\": "src"
        }
      }
    }
    MANIFEST
    malformed_requirements = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                    github_repository_id: 105,
                                    filename: "composer.json",
                                    path: "",
                                    content: malformed_requirements_content,
                                    pushed_at: Time.new(2019, 1, 1),
                                    fork: false,
                                    visibility_private: false)

    expect(malformed_requirements.parse.dependencies).to be_empty
  end

  describe ".test" do
    def test(filename, path)
      described_class.test(filename: filename, path: path)
    end

    it "recognizes composer.json" do
      expect(test("composer.json", nil)).to be_truthy
      expect(test("composer.json", "/")).to be_truthy
      expect(test("wrong", "/")).to be_falsey
      expect(test("wrong-composer.json", "/")).to be_falsey
    end

    it "recognizes composer.lock" do
      expect(test("composer.lock", nil)).to be_truthy
      expect(test("composer.lock", "/")).to be_truthy
      expect(test("wrong", "/")).to be_falsey
      expect(test("wrong-composer.lock", "/")).to be_falsey
    end
  end
end
