require "rails_helper"
require "manifest_adapters"

describe "requirements.txt parsing" do
  let(:file) do
     <<~TXT
      #
      ####### example-requirements.txt #######
      #
      ###### Requirements without Version Specifiers ######
      nose
      nose-cov
      beautifulsoup4
      #
      ###### Requirements with Version Specifiers ######
      #   See https://www.python.org/dev/peps/pep-0440/#version-specifiers
      docopt == 0.6.1             # Version Matching. Must be version 0.6.1
      keyring>=4.1.1            # Minimum version 4.1.1
      #
      ###### Refer to other requirements files ######
      -r other-requirements.txt
      #
      #
      ###### A particular file ######
      ./downloads/numpy-1.9.2-cp34-none-win32.whl
      http://wxpython.org/Phoenix/snapshot-builds/wxPython_Phoenix-3.0.3.dev1820+49a8884-cp34-none-win_amd64.whl
      #
      ###### Additional Requirements without Version Specifiers ######
      #   Same as 1st section, just here to show that you can put things in any order.
      rejected[extras]
      foo___bar
      jupyter_client
      oslo.cache

      ###### Requirements with Version Specifiers and extras ######
      apache-airflow[celery,snowflake,google_auth,aws,statsd, postgres]==2.2.3 -c airflow-constraints.txt
      requests[security, ssl]

      -e git+git@github.com:github/python-proj.git@b1ad2913dde4a1e059c0fe935#egg=proj
    TXT
  end

  def manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: "requirements.txt",
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
  specify { expect(manifest.manifest_type).to eq Types::Manifest[:requirements_txt] }
  specify { expect(manifest.dependent_name).to be_nil }
  specify { expect(manifest.dependent_version).to be_nil }
  specify { expect(manifest.filename).to eq "requirements.txt" }
  specify { expect(manifest.path).to eq "" }
  specify { expect(manifest.git_ref).to eq "78716382bd3de2dbf141643bbe40f93185b5d4c6" }
  specify { expect(manifest.pushed_at).to eq Time.new(2017, 1, 1) }
  specify { expect(manifest.github_repository_id).to eq 55 }
  specify { expect(manifest).to_not be_fork }
  specify { expect(manifest).to_not be_malformed }

  context "dependencies" do
    subject(:dependencies) { manifest.dependencies }
    it "should retrieve the package name, scope and requirements" do
      should include(dependency(package_name: "foo___bar", scope: :runtime, requirements: "", raw_requirements: ""))
      should include(dependency(package_name: "jupyter_client", scope: :runtime, requirements: "", raw_requirements: ""))
      should include(dependency(package_name: "oslo.cache", scope: :runtime, requirements: "", raw_requirements: ""))
      should include(dependency(package_name: "nose", scope: :runtime, requirements: "", raw_requirements: ""))
      should include(dependency(package_name: "nose-cov", scope: :runtime, requirements: "", raw_requirements: ""))
      should include(dependency(package_name: "beautifulsoup4", scope: :runtime, requirements:  "", raw_requirements: ""))
      should include(dependency(package_name: "docopt", scope: :runtime, requirements:  "= 0.6.1", raw_requirements: "= 0.6.1"))
      should include(dependency(package_name: "keyring", scope: :runtime, requirements:  ">= 4.1.1", raw_requirements: ">= 4.1.1"))
      should include(dependency(package_name: "rejected", scope: :runtime, requirements:  "", raw_requirements: ""))
    end

    it "includes dependencies with multiple extras" do
      should include(dependency(package_name: "apache-airflow", scope: :runtime, requirements:  "= 2.2.3", raw_requirements: "= 2.2.3"))
      should include(dependency(package_name: "requests", scope: :runtime, requirements:  "", raw_requirements: ""))
    end

    it "includes normalized version" do
      should include(dependency(package_name: "rejected", scope: :runtime, requirements:  "", raw_requirements: ""))
    end
  end

  context "files with 'dev' or 'test' in the name" do
    it "sets the dependency scope to :development" do
      manifest = manifest(filename: "requirements/test.txt")
      expect(manifest.dependencies.map(&:scope).uniq)
        .to eq [Types::Scope[:development]]

      manifest = manifest(filename: "requirements/dev.txt")
      expect(manifest.dependencies.map(&:scope).uniq)
        .to eq [Types::Scope[:development]]

      manifest = manifest(filename: "requirements/development.txt")
      expect(manifest.dependencies.map(&:scope).uniq)
        .to eq [Types::Scope[:development]]
    end
  end

  it "accepts any .txt file with 'require' in the path" do
    expect(manifest(filename: "requirements.txt")).to be_present
    expect(manifest(filename: "requirements/production.txt")).to be_present
    expect(manifest(filename: "require/production.txt")).to be_present

    expect {
      manifest(filename: "recipes.txt")
    }.to raise_error(ManifestAdapters::NotRecognizedError)

    expect {
      manifest(filename: "docs/notes.txt")
    }.to raise_error(ManifestAdapters::NotRecognizedError)
  end

  # we decided to not apply this to requirements.txt,
  # see ManifestAdapters::Pip::Parsers::RequirementsTxt
  # it "is malformed if any line is unparseable" do
  #   manifest = manifest({
  #     content: <<~FILE
  #       ## Chapter one
  #
  #       This is a document
  #       =====
  #     FILE
  #   })
  #   expect(manifest).to be_malformed
  # end

  it "is not malformed if a comment has a comma" do
    comma_file =
      <<~TXT
    amqp==1.4.9               # via kombu, librabbitmq
    TXT

    comma_manifest = manifest({ content: comma_file })
    # refute comma_manifest.malformed?
    assert_equal ["amqp"], comma_manifest.dependencies.map(&:package_name)
  end

  it "handles versions with ascii in them" do
    ascii_file =
      <<~TXT
    foo==1.0.post456.dev34
    TXT

    ascii_file_manifest = manifest({ content: ascii_file })
    refute ascii_file_manifest.malformed?
    assert_equal ["= 1.0.post456.dev34"], ascii_file_manifest.dependencies.map(&:requirements)
  end

  it "should still work even if a given line is malformed" do
    weird_file =
      <<~TXT
    amqp==1.4.9               # via kombu, librabbitmq
    djangorestframework-jwt-refresh-token==dd-0.1.3
    TXT

    weird_manifest = manifest({ content: weird_file })
    # assert weird_manifest.malformed?
    assert_equal ["amqp"], weird_manifest.dependencies.map(&:package_name)
  end

  context "when file has a ';'" do
    it "parses the dependencies" do
      manifest = manifest({
        content: <<~FILE
          libsass==0.12.3
          lxml==3.7.1 ; sys_platform != 'win32' and python_version < '3.7'
          lxml==4.2.3 ; sys_platform != 'win32' and python_version >= '3.7'
          lxml ; sys_platform == 'win32'
        FILE
      })

      expect(manifest).to_not be_malformed
      expect(manifest.dependencies.map(&:package_name))
        .to eq %w(libsass lxml lxml lxml)
    end
  end
end
