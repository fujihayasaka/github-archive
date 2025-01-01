require "rails_helper"
require "manifest_adapters"

describe "Pipfile parsing" do
  let(:file) do
     <<~Pipfile
      [source]
      url = 'https://pypi.python.org/simple'
      verify_ssl = true
      name = 'pypi'

      [requires]
      python_version = '2.7'

      [packages]
      requests = { extras = ['socks'] }
      records = '>0.5.0'
      django = { git = 'https://github.com/django/django.git', ref = '1.11.4', editable = true }
      "e682b37" = {file = "https://github.com/divio/django-cms/archive/release/3.4.x.zip"}
      "e1839a8" = {path = ".", editable = true}
      pywinusb = { version = "*", os_name = "=='nt'", index="pypi"}

      [dev-packages]
      nose = '*'
      unittest2 = {version = ">=1.0,<3.0", markers="python_version < '2.7.9' or (python_version >= '3.0' and python_version < '3.4')"}
    Pipfile
  end

  def manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: "Pipfile",
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

  specify { expect(manifest.package_manager).to eq Types::PackageManager[:pip] }
  specify { expect(manifest.manifest_type).to eq Types::Manifest[:pipfile] }
  specify { expect(manifest.dependent_name).to be_nil }
  specify { expect(manifest.dependent_version).to be_nil }
  specify { expect(manifest.filename).to eq "Pipfile" }
  specify { expect(manifest.path).to eq "" }
  specify { expect(manifest.git_ref).to eq "78716382bd3de2dbf141643bbe40f93185b5d4c6" }
  specify { expect(manifest.pushed_at).to eq Time.new(2017, 1, 1) }
  specify { expect(manifest.github_repository_id).to eq 55 }
  specify { expect(manifest).to_not be_fork }
  specify { expect(manifest).to_not be_malformed }

  it "parses dependencies" do
    expect(manifest.dependencies).to match_array [
      dependency(package_name: "requests", scope: :runtime, requirements: "", raw_requirements:  nil),
      dependency(package_name: "records", scope: :runtime, requirements: "> 0.5.0", raw_requirements: ">0.5.0"),
      dependency(package_name: "django", scope: :runtime, requirements: "", raw_requirements:  nil),
      dependency(package_name: "pywinusb", scope: :runtime, requirements: "", raw_requirements: "*"),
      dependency(package_name: "nose", scope: :development, requirements: "", raw_requirements: "*"),
      dependency(package_name: "unittest2", scope: :development, requirements: ">= 1.0,< 3.0", raw_requirements: ">=1.0,<3.0"),
    ]
  end

  it "handles invalid TOML" do
    manifest = manifest(content: "{")
    expect(manifest).to be_malformed
  end

  it "handles invalid requirements" do
    content = <<~Pipfile
      [source]
      url = 'https://pypi.python.org/simple'

      [requires]
      python_version = '2.7'

      [packages]
      records = 'GARBAGE'
    Pipfile

    expect(manifest(content: content)).to be_malformed
  end
end
