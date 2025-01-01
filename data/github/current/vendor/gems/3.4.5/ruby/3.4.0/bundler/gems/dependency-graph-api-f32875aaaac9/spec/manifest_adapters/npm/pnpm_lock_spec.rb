require "rails_helper"
require "manifest_adapters"

describe "pnpm-lock.yaml parsing" do
  def manifest(content:)
    ::ManifestAdapters.parse(**{
      git_ref: "6499ba0675d713a9fd4d7a0dcd99efab6b53f64a",
      github_repository_id: 100,
      filename: "pnpm-lock.yaml",
      path: "",
      content: content,
      pushed_at: Time.new(2023, 7, 1),
      fork: false,
      visibility_private: false,
    })
  end

  it "gracefully handles malformed manifests" do
    manifest = manifest(content: "invalid content as string")
    expect(manifest.malformed?).to be_truthy
  end

  it "parses lockfileVersion:9.* manifests" do
    manifest = manifest(content: file_fixture("pnpm_lock_v9.yaml").read)
    expect(manifest.dependent_name).to be_nil
    expect(manifest.dependent_version).to be_nil
    expect(manifest.malformed?).to be_falsey
    expect(manifest.dependencies).not_to be_empty

    expect(manifest.dependencies.length).to be(683)

    # dependency path with namespace should be captured
    expect(manifest.dependencies).to include(
      an_object_having_attributes(
        package_name: "@babel/plugin-syntax-jsx",
        requirements: "= 7.24.7",
        scope: Types::Scope[:runtime],
      )
    )
    targets = manifest.dependencies.select {
      |d| d.package_name == "@babel/plugin-syntax-jsx" && d.requirements == "= 7.24.7"
    }
    expect(targets.length).to equal(1)
    expect(targets.first.malformed?).to be_falsey

    # dependency path w/o namespace elements should be captured
    expect(manifest.dependencies).to include(
      an_object_having_attributes(
        package_name: "argparse",
        requirements: "= 1.0.10",
        scope: Types::Scope[:runtime],
      )
    )
    targets = manifest.dependencies.select {
      |d| d.package_name == "argparse" && d.requirements == "= 1.0.10"
    }
    expect(targets.length).to equal(1)
    expect(targets.first.malformed?).to be_falsey

    # '@angular-devkit/core@17.3.8(chokidar@3.6.0)' should strip identifier suffix
    expect(manifest.dependencies).to include(
      an_object_having_attributes(
        package_name: "@angular-devkit/core",
        requirements: "= 17.3.8",
        scope: Types::Scope[:runtime],
      )
    )
    targets = manifest.dependencies.select {
      |d| d.package_name == "@angular-devkit/core" && d.requirements == "= 17.3.8"
    }
    expect(targets.length).to equal(1)
    expect(targets.first.malformed?).to be_falsey

   # '@babel/compat-data@7.25.4' should be dev scoped
    expect(manifest.dependencies).to include(
       an_object_having_attributes(
         package_name: "@babel/compat-data",
         requirements: "= 7.25.4",
         scope: Types::Scope[:development],
       )
     )
    targets = manifest.dependencies.select {
      |d| d.package_name == "@babel/compat-data" && d.requirements == "= 7.25.4"
    }
    expect(targets.length).to equal(1)
    expect(targets.first.malformed?).to be_falsey
  end

  it "parses lockfileVersion:6.* manifests" do
    manifest = manifest(content: file_fixture("pnpm_lock_v6.yaml").read)
    expect(manifest.dependent_name).to be_nil
    expect(manifest.dependent_version).to be_nil
    expect(manifest.malformed?).to be_falsey
    expect(manifest.dependencies).not_to be_empty

    expect(manifest.dependencies.length).to be(21)

    #scoped package
    expect(manifest.dependencies).to include(
      an_object_having_attributes(
        package_name: "@babel/code-frame",
        requirements: "= 7.22.5"
      )
    )

    #scoped package with peer dependency
    expect(manifest.dependencies).to include(
      an_object_having_attributes(
        package_name: "@pnpm/build-modules",
        requirements: "= 10.1.9"
      )
    )

    # unscoped package with peer dependency
    expect(manifest.dependencies).to include(
      an_object_having_attributes(
        package_name: "babel-jest",
        requirements: "= 29.5.0"
      )
    )

    #dependency excluded because package has id attribute
    expect(manifest.dependencies).not_to include(
      an_object_having_attributes(
        package_name: "@pnpm/constants"
      )
    )
    # dependency with multiple versions
    expect(manifest.dependencies).to include(
      an_object_having_attributes(
        package_name: "ajv",
        requirements: "= 6.12.6"
      )
    )

    expect(manifest.dependencies).to include(
      an_object_having_attributes(
        package_name: "ajv",
        requirements: "= 8.12.0"
      )
    )
  end

  it "parses lockfileVersion:5.* manifests" do
    manifest = manifest(content: file_fixture("pnpm_lock_v5.yaml").read)
    expect(manifest.dependent_name).to be_nil
    expect(manifest.dependent_version).to be_nil
    expect(manifest.malformed?).to be_falsey
    expect(manifest.dependencies).not_to be_empty

    #scoped package
    expect(manifest.dependencies).to include(
      an_object_having_attributes(
        package_name: "@eslint-community/regexpp",
        requirements: "= 4.4.1"
      )
    )

    #scoped package with peer dependency
    expect(manifest.dependencies).to include(
      an_object_having_attributes(
        package_name: "@eslint-community/eslint-utils",
        requirements: "= 4.4.0"
      )
    )

    # unscoped package with peer dependency
    expect(manifest.dependencies).to include(
      an_object_having_attributes(
        package_name: "update-browserslist-db",
        requirements: "= 1.0.10"
      )
    )

    #dependency excluded because package has id attribute
    expect(manifest.dependencies).not_to include(
      an_object_having_attributes(
        package_name: "acorn"
      )
    )

    expect(manifest.dependencies.length).to be(11)
  end
end
