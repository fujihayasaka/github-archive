# frozen_string_literal: true

require "rails_helper"

describe ManifestAdapters::Nuget::Adapter do
  it "identifies malformed nuspec manifests" do
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
                                                      github_repository_id: 55,
                                                      filename: ".nuspec",
                                                      path: "",
                                                      content: "",
                                                      pushed_at: Time.new(2017, 1, 1),
                                                      fork: false,
                                                      visibility_private: false)

    json = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                               github_repository_id: 55,
                               filename: "json.nuspec",
                               path: "",
                               content: file_fixture("json.nuspec").read,
                               pushed_at: Time.new(2017, 1, 1),
                               fork: false,
                               visibility_private: false)
    expect(json.parse).to be_malformed

    half_a_nuspec = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                        github_repository_id: 55,
                                        filename: "half.nuspec",
                                        path: "",
                                        content: file_fixture("half.nuspec").read,
                                        pushed_at: Time.new(2017, 1, 1),
                                        fork: false,
                                        visibility_private: false)
    expect(half_a_nuspec.parse).to be_malformed

    wrong_xml = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                    github_repository_id: 55,
                                    filename: "wrong.nuspec",
                                    path: "",
                                    content: file_fixture("wrong.nuspec").read,
                                    pushed_at: Time.new(2017, 1, 1),
                                    fork: false,
                                    visibility_private: false)
    expect(wrong_xml.parse).to be_malformed

    malformed_dependency = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                               github_repository_id: 55,
                                               filename: ".nuspec",
                                               path: "",
                                               content: file_fixture("malformed_dependency.nuspec").read,
                                               pushed_at: Time.new(2017, 1, 1),
                                               fork: false,
                                               visibility_private: false)
    # testing that malformed dependencies don't invalidate the entire
    # manifest and that the dependencies that are valid still parse
    expect(malformed_dependency.parse).to_not be_malformed
    expect(malformed_dependency.parse.dependencies).to_not be_nil
    expect(malformed_dependency.parse.dependencies.length).to eq(5)
  end

  it "identifies malformed csproj manifests" do
    specifically_blank_manifest = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                                      github_repository_id: 55,
                                                      filename: "octokit.csproj",
                                                      path: "",
                                                      content: "",
                                                      pushed_at: Time.new(2017, 1, 1),
                                                      fork: false,
                                                      visibility_private: false)

    json = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                               github_repository_id: 55,
                               filename: "json.csproj",
                               path: "",
                               content: file_fixture("json.nuspec").read,
                               pushed_at: Time.new(2017, 1, 1),
                               fork: false,
                               visibility_private: false)
    expect(json.parse).to be_malformed

    malformed_xml = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                        github_repository_id: 55,
                                        filename: "malformed_xml.csproj",
                                        path: "",
                                        content: file_fixture("malformed_xml.csproj").read,
                                        pushed_at: Time.new(2017, 1, 1),
                                        fork: false,
                                        visibility_private: false)
    expect(malformed_xml.parse).to be_malformed

    no_package_attributes = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                                github_repository_id: 55,
                                                filename: ".nuspec",
                                                path: "",
                                                content: file_fixture("no_packages.csproj").read,
                                                pushed_at: Time.new(2017, 1, 1),
                                                fork: false,
                                                visibility_private: false)
    expect(no_package_attributes.parse).to be_malformed

    has_dependencies = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                           github_repository_id: 55,
                                           filename: "has_dependencies.csproj",
                                           path: "",
                                           content: file_fixture("has_dependencies.csproj").read,
                                           pushed_at: Time.new(2017, 1, 1),
                                           fork: false,
                                           visibility_private: false)

    expect(has_dependencies.parse).to_not be_malformed
    expect(has_dependencies.parse.dependencies).to_not be_nil
    expect(has_dependencies.parse.dependencies.count).to eq(5)

    has_malformed_dependencies = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                           github_repository_id: 55,
                                           filename: "has_malformed_dependencies.csproj",
                                           path: "",
                                           content: file_fixture("has_malformed_dependencies.csproj").read,
                                           pushed_at: Time.new(2017, 1, 1),
                                           fork: false,
                                           visibility_private: false)

    expect(has_malformed_dependencies.parse).to_not be_malformed
    expect(has_malformed_dependencies.parse.dependencies).to_not be_nil
    # testing that malformed dependencies don't invalidate the entire
    # manifest and that the dependencies that are valid still parse
    # Despite invalid versions, we expect 7 dependents because we default to setting requirements >= 0
    expect(has_malformed_dependencies.parse.dependencies.count).to eq(7)

    has_package = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                           github_repository_id: 55,
                                           filename: "has_package.csproj",
                                           path: "",
                                           content: file_fixture("has_package.csproj").read,
                                           pushed_at: Time.new(2017, 1, 1),
                                           fork: false,
                                           visibility_private: false)

    expect(has_package.parse).to_not be_malformed
    expect(has_package.parse.dependent_name).to eq("newtonsoft.json")
    expect(has_package.parse.dependent_version).to eq("1.2.0")

    has_package_default_version = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                           github_repository_id: 55,
                                           filename: "has_package_default_version.csproj",
                                           path: "",
                                           content: file_fixture("has_package_default_version.csproj").read,
                                           pushed_at: Time.new(2017, 1, 1),
                                           fork: false,
                                           visibility_private: false)

    expect(has_package_default_version.parse).to_not be_malformed
    expect(has_package_default_version.parse.dependent_name).to eq("newtonsoft.json")
    expect(has_package_default_version.parse.dependent_version).to eq("1.2.0")
  end

  it "Identifies valid packages.config file" do
    has_dependencies = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                           github_repository_id: 55,
                                           filename: "packages.config",
                                           path: "",
                                           content: file_fixture("valid_packages.config").read,
                                           pushed_at: Time.new(2017, 1, 1),
                                           fork: false,
                                           visibility_private: false)

    expect(has_dependencies.parse).to_not be_malformed
    expect(has_dependencies.parse.dependencies).to_not be_nil
    expect(has_dependencies.parse.dependencies.length).to eq(2)
  end

  it "Identifies valid csproj file when missing project_id" do
    missing_project_id = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                             github_repository_id: 55,
                                             filename: "missing_project_id.csproj",
                                             path: "",
                                             content: file_fixture("half.nuspec").read,
                                             pushed_at: Time.new(2017, 1, 1),
                                             fork: false,
                                             visibility_private: false)
    expect(missing_project_id.parse).to_not be_malformed
  end

  it "Identifies valid vcxproj file" do
    has_dependencies = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: "sample.vcxproj",
      path: "",
      content: file_fixture("sample.vcxproj").read,
      pushed_at: Time.new(2017, 1, 1),
      fork: false,
      visibility_private: false)

      expect(has_dependencies.parse).to_not be_malformed
      expect(has_dependencies.parse.dependencies).to_not be_nil
      expect(has_dependencies.parse.dependencies.length).to eq(5)
  end

  it "Identifies valid fsproj file" do
    has_dependencies = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: "sample.fsproj",
      path: "",
      content: file_fixture("sample.fsproj").read,
      pushed_at: Time.new(2017, 1, 1),
      fork: false,
      visibility_private: false)

      expect(has_dependencies.parse).to_not be_malformed
      expect(has_dependencies.parse.dependencies).to_not be_nil
      expect(has_dependencies.parse.dependencies.length).to eq(52)
  end

  it "Handles malformed packages.config file" do
    has_dependencies = described_class.new(git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
                                           github_repository_id: 55,
                                           filename: "packages.config",
                                           path: "",
                                           content: file_fixture("malformed_packages.config").read,
                                           pushed_at: Time.new(2017, 1, 1),
                                           fork: false,
                                           visibility_private: false)

    expect(has_dependencies.parse).to_not be_malformed
    expect(has_dependencies.parse.dependencies).to_not be_nil
    expect(has_dependencies.parse.dependencies.length).to eq(2)
  end

  describe ".test" do
    def test(filename, path)
      described_class.test(filename: filename, path: path)
    end

    it "recognizes nuspecs" do
      expect(test(".nuspec", nil)).to be_truthy
      expect(test(".nuspec", "/")).to be_truthy
      expect(test("proj.nuspec", "/")).to be_truthy
      expect(test("wrong", "/")).to be_falsey
    end

    it "recognizes csproj" do
      expect(test("myname.csproj", nil)).to be_truthy
      expect(test(".csproj", "/")).to be_truthy
    end

    it "recognizes vbproj" do
      expect(test("myname.vbproj", nil)).to be_truthy
      expect(test(".vbproj", "/")).to be_truthy
    end

    it "recognizes vcxproj" do
      expect(test("myname.vcxproj", nil)).to be_truthy
      expect(test(".vcxproj", "/")).to be_truthy
    end

    it "recognizes fsproj" do
      expect(test("myname.fsproj", nil)).to be_truthy
      expect(test(".fsproj", "/")).to be_truthy
    end

    it "recognizes packages.config" do
      expect(test("packages.config", nil)).to be_truthy
    end
  end
end
