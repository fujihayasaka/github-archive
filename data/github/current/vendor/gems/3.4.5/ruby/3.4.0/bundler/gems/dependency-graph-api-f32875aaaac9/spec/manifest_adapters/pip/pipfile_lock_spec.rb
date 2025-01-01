require "rails_helper"
require "manifest_adapters"

describe "Pipfile.lock parsing" do
  let(:file) do
     <<~PipfileLock
      {
          "_meta": {
              "hash": {
                  "sha256": "09da36fcc93fa9b94fbea5282d8206a9d2e13fcec27229ec62c16c134e3e760a"
              },
              "host-environment-markers": {},
              "pipfile-spec": 6,
              "requires": {
                  "python_version": "2.7"
              },
              "sources": [
                  {
                      "name": "pypi",
                      "url": "https://pypi.python.org/simple",
                      "verify_ssl": true
                  }
              ]
          },
          "default": {
              "certifi": {
                  "hashes": [
                      "sha256:54a07c09c586b0e4c619f02a5e94e36619da8e2b053e20f594348c0611803704"
                  ],
                  "version": "==2017.7.27.1"
              },
              "chardet": {
                  "hashes": [
                      "sha256:fc323ffcaeaed0e0a02bf4d117757b98aed530d9ed4531e3e15460124c106691"
                  ],
                  "version": "==3.0.4"
              },
              "django": {
                  "editable": true,
                  "git": "https://github.com/django/django.git",
                  "ref": "1.11.4"
              },
              "docopt": {
                  "hashes": [
                      "sha256:49b3a825280bd66b3aa83585ef59c4a8c82f2c8a522dbe754a8bc8d08c85c491"
                  ],
                  "version": "==0.6.2"
              },
              "e1839a8": {
                  "editable": true,
                  "path": "."
              },
              "e682b37": {
                  "file": "https://github.com/divio/django-cms/archive/release/3.4.x.zip"
              },
              "xlwt": {
                  "hashes": [
                      "sha256:c59912717a9b28f1a3c2a98fd60741014b06b043936dcecbc113eaaada156c88"
                  ],
                  "version": "==1.3.0"
              }
          },
          "develop": {
              "argparse": {
                  "hashes": [
                      "sha256:c31647edb69fd3d465a847ea3157d37bed1f95f19760b11a47aa91c04b666314"
                  ],
                  "version": "==1.4.0"
              },
              "linecache2": {
                  "hashes": [
                      "sha256:e78be9c0a0dfcbac712fe04fbf92b96cddae80b1b842f24248214c8496f006ef"
                  ],
                  "version": "==1.0.0"
              }
          }
      }
    PipfileLock
  end

  def manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: "Pipfile.lock",
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
  specify { expect(manifest.manifest_type).to eq Types::Manifest[:pipfile_lock] }
  specify { expect(manifest.dependent_name).to be_nil }
  specify { expect(manifest.dependent_version).to be_nil }
  specify { expect(manifest.filename).to eq "Pipfile.lock" }
  specify { expect(manifest.path).to eq "" }
  specify { expect(manifest.git_ref).to eq "78716382bd3de2dbf141643bbe40f93185b5d4c6" }
  specify { expect(manifest.pushed_at).to eq Time.new(2017, 1, 1) }
  specify { expect(manifest.github_repository_id).to eq 55 }
  specify { expect(manifest).to_not be_fork }
  specify { expect(manifest).to_not be_malformed }

  it "parses dependencies" do
    expect(manifest.dependencies).to match_array [
      dependency(package_name: "certifi", scope: :runtime, requirements:  "= 2017.7.27.1", raw_requirements:  "==2017.7.27.1"),
      dependency(package_name: "chardet", scope: :runtime, requirements:  "= 3.0.4", raw_requirements:  "==3.0.4"),
      dependency(package_name: "django", scope: :runtime, requirements:  "", raw_requirements:  ""),
      dependency(package_name: "docopt", scope: :runtime, requirements:  "= 0.6.2", raw_requirements:  "==0.6.2"),
      dependency(package_name: "xlwt", scope: :runtime, requirements:  "= 1.3.0", raw_requirements:  "==1.3.0"),
      dependency(package_name: "argparse", scope: :development, requirements:  "= 1.4.0", raw_requirements:  "==1.4.0"),
      dependency(package_name: "linecache2", scope: :development, requirements:  "= 1.0.0", raw_requirements:  "==1.0.0")
    ]
  end

  it "handles invalid JSON" do
    manifest = manifest(content: "{")
    expect(manifest).to be_malformed
  end

  it "handles invalid requirements" do
    content = <<~Pipfile
      {
          "_meta": {
              "hash": {
                  "sha256": "09da36fcc93fa9b94fbea5282d8206a9d2e13fcec27229ec62c16c134e3e760a"
              },
              "host-environment-markers": {},
              "pipfile-spec": 6,
              "requires": {
                  "python_version": "2.7"
              },
              "sources": [
                  {
                      "name": "pypi",
                      "url": "https://pypi.python.org/simple",
                      "verify_ssl": true
                  }
              ]
          },
          "default": {
              "certifi": {
                  "hashes": [
                      "sha256:54a07c09c586b0e4c619f02a5e94e36619da8e2b053e20f594348c0611803704"
                  ],
                  "version": "GARBAGE"
              }
          }
      }
    Pipfile

    expect(manifest(content: content)).to be_malformed
  end
end
