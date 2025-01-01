require "rails_helper"
require "manifest_adapters"
require_relative "../../../app/manifest_adapters/manifest_adapters/pip/parsers/pyproject_toml"

describe "pyproject.toml parsing" do
  let(:pyproject_native_toml) do
    <<~TOML
      [project]
      homepage = 'https://pypi.python.org/simple'
      # Name and version as per https://peps.python.org/pep-0621/
      name = 'pypi'
      python = '2.7'

      [dependencies]
      requests = { extras = ['socks'] }
      records = '  >0.5.0  '
      things = '1.2.*  '
      exact-thing = '==3.2.1  '
      not-things = '!=1.2.5'
      alpha-thing = '==1.1a1'
      with-prerelease = '==1.2.3-4e5'
      many-digited = '==123456789.987654321.1357986420'
      crazy-characters = '==1.-_.*+!.3'
      complicated-whitespace = ' ( <= 9.9.9, >= 1.1.1 ) '
      django = { git = 'https://github.com/django/django.git', ref = '1.11.4', editable = true }
      "e682b37" = {file = "https://github.com/divio/django-cms/archive/release/3.4.x.zip"}
      "e1839a8" = {path = ".", editable = true}
      pywinusb = { version = "*", os_name = "=='nt'", index="pypi"}

      [dev-dependencies]
      nose = '*'
      unittest2 = {version = ">= 1.0  ,  <3.0  ", markers="python_version < '2.7.9' or (python_version >= '3.0' and python_version < '3.4')"}
    TOML
  end

  let(:pyproject_project_toml) do
    <<~TOML
    [project]
    homepage = 'https://pypi.python.org/simple'
    # Name and version as per https://peps.python.org/pep-0621/
    name = 'pypi'
    python = '2.7'
    dependencies = [
      "spatialdata @ git+https://github.com/scverse/spatialdata.git@main",
      "requests>=5.2.2; python_version < '3.9'",
      "things>=0.4.1,<1",
      "exact-thing==3.2.1  ",
      "not-things!=1.2.5",
      "alpha-thing==1.1a1",
      "with-prerelease==1.2.3-4e5",
      "many-digited==123456789.987654321.1357986420",
      "crazy-characters==1.-_.*+!.3",
    ]
  TOML
  end

  let(:poetry_toml) do
    <<~TOML
      [tool.poetry]
      name = "blog"
      version = "0.1.0"
      description = ""
      authors = ["Mona"]

      [tool.poetry.dependencies]
      python = "^3.10"
      requests = { extras = ['socks'] }
      records = '  >0.5.0  '
      things = '1.2.*  '
      exact-thing= '3.2.1  '
      other-things = '1.*'
      foobar = '^1.2.3'
      tilde-foobar = '~4.5.6'
      with-prerelease = '1.2.3-4e5'
      many-digited = '123456789.987654321.1357986420'
      crazy-characters = '1.2.3-_*+!'
      complicated-whitespace = ' ( <= 9.9.9, >= 1.1.1 ) '
      django = { git = 'https://github.com/django/django.git', ref = '1.11.4', editable = true }
      "e682b37" = {file = "https://github.com/divio/django-cms/archive/release/3.4.x.zip"}
      "e1839a8" = {path = ".", editable = true}
      multiversion-inline = ['1.2.3, 4.5.6'] # not valid, will be excluded from parsed results

      [tool.poetry.dependencies.pywinusb]
      version = "*"
      os_name = "=='nt'"
      index="pypia"

      [tool.poetry.dependencies.multiversion]
      version = ["0.1.2","1.2.3"] # not valid, will be excluded from parsed results
      os_name = "=='nt'"
      index="pypia"

      [tool.poetry.dev-dependencies]
      nose = '*'
      unittest2 = {version = ">= 1.0  ,  <3.0  ", markers="python_version < '2.7.9' or (python_version >= '3.0' and python_version < '3.4')"}

      [build-system]
      requires = ["poetry-core>=1.0.0"]
      build-backend = "poetry.core.masonry.api"
    TOML
  end

  def manifest(file, attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: "pyproject.toml",
      path: "",
      content: file,
      pushed_at: Time.new(2017, 1, 1),
      fork: false,
      visibility_private: false,
    }.merge(attributes))
  end

  def dependency(args)
    ManifestAdapters::Manifest::Dependency.new(**args)
  end

  specify { expect(manifest(pyproject_native_toml).package_manager).to eq Types::PackageManager[:pip] }
  specify { expect(manifest(pyproject_native_toml).manifest_type).to eq Types::Manifest[:pyproject_toml] }
  specify { expect(manifest(pyproject_native_toml).dependent_name).to eq "pypi" }
  specify { expect(manifest(pyproject_native_toml).dependent_version).to be_nil }
  specify { expect(manifest(pyproject_native_toml).filename).to eq "pyproject.toml" }
  specify { expect(manifest(pyproject_native_toml).path).to eq "" }
  specify { expect(manifest(pyproject_native_toml).git_ref).to eq "78716382bd3de2dbf141643bbe40f93185b5d4c6" }
  specify { expect(manifest(pyproject_native_toml).pushed_at).to eq Time.new(2017, 1, 1) }
  specify { expect(manifest(pyproject_native_toml).github_repository_id).to eq 55 }
  specify { expect(manifest(pyproject_native_toml)).to_not be_fork }
  specify { expect(manifest(pyproject_native_toml)).to_not be_malformed }

  it "parses pyproject_native_toml dependencies" do
    expect(manifest(pyproject_native_toml).dependencies).to match_array [
      dependency(package_name: "requests", scope: :runtime, requirements: "", raw_requirements:  nil),
      dependency(package_name: "records", scope: :runtime, requirements: "> 0.5.0", raw_requirements: "  >0.5.0  "),
      dependency(package_name: "things", scope: :runtime, requirements: "", raw_requirements: "1.2.*  "),
      dependency(package_name: "not-things", scope: :runtime, requirements: "> 1.2.5 || < 1.2.5", raw_requirements: "!=1.2.5"),
      dependency(package_name: "exact-thing", scope: :runtime, requirements: "= 3.2.1", raw_requirements: "==3.2.1  "),
      dependency(package_name: "many-digited", scope: :runtime, requirements: "= 123456789.987654321.1357986420", raw_requirements: "==123456789.987654321.1357986420"),
      dependency(package_name: "crazy-characters", scope: :runtime, requirements: "= 1.-_.*+!.3", raw_requirements: "==1.-_.*+!.3"),
      dependency(package_name: "complicated-whitespace", scope: :runtime, requirements: "<= 9.9.9,>= 1.1.1", raw_requirements: " ( <= 9.9.9, >= 1.1.1 ) "),
      dependency(package_name: "with-prerelease", scope: :runtime, requirements: "= 1.2.3-4e5", raw_requirements: "==1.2.3-4e5"),
      dependency(package_name: "alpha-thing", scope: :runtime, requirements: "= 1.1a1", raw_requirements: "==1.1a1"),
      dependency(package_name: "django", scope: :runtime, requirements: "", raw_requirements:  nil),
      dependency(package_name: "pywinusb", scope: :runtime, requirements: "", raw_requirements: "*"),
      dependency(package_name: "nose", scope: :development, requirements: "", raw_requirements: "*"),
      dependency(package_name: "unittest2", scope: :development, requirements: ">= 1.0,< 3.0", raw_requirements: ">= 1.0  ,  <3.0  "),
    ]
  end

  it "parses pyproject_project_toml dependencies" do
    expect(manifest(pyproject_project_toml).dependencies).to match_array [
      dependency(package_name: "spatialdata", scope: :runtime, requirements: "", raw_requirements:  " @ git+https://github.com/scverse/spatialdata.git@main"),
      dependency(package_name: "requests", scope: :runtime, requirements: ">= 5.2.2", raw_requirements:  ">=5.2.2"),
      dependency(package_name: "things", scope: :runtime, requirements: ">= 0.4.1,< 1", raw_requirements: ">=0.4.1,<1"),
      dependency(package_name: "exact-thing", scope: :runtime, requirements: "= 3.2.1", raw_requirements: "==3.2.1  "),
      dependency(package_name: "not-things", scope: :runtime, requirements: "> 1.2.5 || < 1.2.5", raw_requirements: "!=1.2.5"),
      dependency(package_name: "alpha-thing", scope: :runtime, requirements: "= 1.1a1", raw_requirements: "==1.1a1"),
      dependency(package_name: "with-prerelease", scope: :runtime, requirements: "= 1.2.3-4e5", raw_requirements: "==1.2.3-4e5"),
      dependency(package_name: "many-digited", scope: :runtime, requirements: "= 123456789.987654321.1357986420", raw_requirements: "==123456789.987654321.1357986420"),
      dependency(package_name: "crazy-characters", scope: :runtime, requirements: "= 1.-_.*+!.3", raw_requirements: "==1.-_.*+!.3"),
    ]
  end

  specify { expect(manifest(poetry_toml).package_manager).to eq Types::PackageManager[:pip] }
  specify { expect(manifest(poetry_toml).manifest_type).to eq Types::Manifest[:pyproject_toml] }
  specify { expect(manifest(poetry_toml).dependent_name).to eq "blog" }
  specify { expect(manifest(poetry_toml).dependent_version).to be_nil }
  specify { expect(manifest(poetry_toml).filename).to eq "pyproject.toml" }
  specify { expect(manifest(poetry_toml).path).to eq "" }
  specify { expect(manifest(poetry_toml).git_ref).to eq "78716382bd3de2dbf141643bbe40f93185b5d4c6" }
  specify { expect(manifest(poetry_toml).pushed_at).to eq Time.new(2017, 1, 1) }
  specify { expect(manifest(poetry_toml).github_repository_id).to eq 55 }
  specify { expect(manifest(poetry_toml)).to_not be_fork }
  specify { expect(manifest(poetry_toml)).to_not be_malformed }

  it "parses dependencies in poetry_toml" do
    expect(manifest(poetry_toml).dependencies).to match_array [
      dependency(package_name: "requests", scope: :runtime, requirements: "", raw_requirements:  nil),
      dependency(package_name: "records", scope: :runtime, requirements: "> 0.5.0", raw_requirements: "  >0.5.0  "),
      dependency(package_name: "things", scope: :runtime, requirements: ">= 1.2.0,< 1.3.0", raw_requirements: "1.2.*  "),
      dependency(package_name: "other-things", scope: :runtime, requirements: ">= 1.0,< 2.0", raw_requirements: "1.*"),
      dependency(package_name: "exact-thing", scope: :runtime, requirements: "= 3.2.1", raw_requirements: "3.2.1  "),
      dependency(package_name: "many-digited", scope: :runtime, requirements: "= 123456789.987654321.1357986420", raw_requirements: "123456789.987654321.1357986420"),
      # crazy characters is special in poetry because semver alignment is claimed, so we only support weird stuff in a prerelease
      dependency(package_name: "crazy-characters", scope: :runtime, requirements: "= 1.2.3-_*+!", raw_requirements: "1.2.3-_*+!"),
      dependency(package_name: "complicated-whitespace", scope: :runtime, requirements: "<= 9.9.9,>= 1.1.1", raw_requirements: " ( <= 9.9.9, >= 1.1.1 ) "),
      dependency(package_name: "with-prerelease", scope: :runtime, requirements: "= 1.2.3-4e5", raw_requirements: "1.2.3-4e5"),
      dependency(package_name: "foobar", scope: :runtime, requirements: "^ 1.2.3", raw_requirements: "^1.2.3"),
      dependency(package_name: "tilde-foobar", scope: :runtime, requirements: "~ 4.5.6", raw_requirements: "~4.5.6"),
      dependency(package_name: "django", scope: :runtime, requirements: "", raw_requirements:  nil),
      dependency(package_name: "pywinusb", scope: :runtime, requirements: "", raw_requirements: "*"),
      dependency(package_name: "nose", scope: :development, requirements: "", raw_requirements: "*"),
      dependency(package_name: "unittest2", scope: :development, requirements: ">= 1.0,< 3.0", raw_requirements: ">= 1.0  ,  <3.0  "),
    ]
  end

  it "handles invalid TOML" do
    manifest = manifest("{")
    expect(manifest).to be_malformed
  end

  it "handles invalid requirements" do
    content = <<~TOML
      [project]
      url = 'https://pypi.python.org/simple'
      python = '2.7'

      [dependencies]
      records = 'GARBAGE'
    TOML

    result = manifest(content)
    expect(result.malformed?).to be_falsey

    # stuff from here on down feels wrong - shouldn't "GARBAGE" be a malformed dependency version?
    expect(result.dependencies.length).to eq(1)

    records_dep = result.dependencies.first
    expect(records_dep.raw_requirements).to eq("GARBAGE")
    expect(records_dep.requirements).to be_empty
    expect(records_dep.malformed?).to be_falsey # ouch!
  end
end
