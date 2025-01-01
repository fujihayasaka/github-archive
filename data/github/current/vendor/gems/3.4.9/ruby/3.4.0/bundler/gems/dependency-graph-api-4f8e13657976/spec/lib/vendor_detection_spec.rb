require "rails_helper"

describe VendorDetection do
  describe "#unsupported_vendored_manifest?" do
    def unsupported_vendored_manifest?(path)
      path = Pathname.new(path)
      described_class.unsupported_vendored_manifest?(path.dirname.sub(/\A.\Z/, ""), path.basename, manifest_type)
    end

    def assert_vendored(path)
      expect(unsupported_vendored_manifest?(path)).to be(true), "Expected '#{path}' to be vendored"
    end

    def assert_not_vendored(path)
      expect(unsupported_vendored_manifest?(path)).to be(false), "Expected '#{path}' to not be vendored"
    end

    describe "Gemfiles" do
      let(:manifest_type) { Types::Manifest[:gemfile] }

      specify { assert_not_vendored "Gemfile" }
      specify { assert_not_vendored "/Gemfile" }
    end

    describe "gemspecs" do
      let(:manifest_type) { Types::Manifest[:gemspec] }

      specify { assert_vendored "vendor/library.gemspec" }
      specify { assert_vendored "bundle/jruby/2.3.0/gems/pundit-1.1.0/pundit.gemspec" }
      specify { assert_vendored "bundle/jruby/2.3.0/gems/pundit-1.1.0/pundit.gemspec" }
      specify { assert_vendored "bundle/jruby/2.3.0/gems/pundit-1.1.0/pundit.gemspec" }
      specify { assert_vendored ".bundle/specifications/coffee-script-source-1.10.0.gemspec" }
      specify { assert_not_vendored "lib/pundit.gemspec" }
      specify { assert_vendored ".rvm/gems/ruby-1.9.2-p290/gems/jquery-rails-1.0.14/jquery-rails.gemspec" }
      specify { assert_vendored ".rvm/gems/ruby-1.9.2-p290/gems/jquery-rails-1.0.14/jquery-rails.gemspec" }
      specify { assert_vendored ".rvm/gems/ruby-1.9.2-p290/gems/jquery-rails-1.0.14/jquery-rails.gemspec" }
      specify { assert_vendored "gems/truncate_html-0.9.2/truncate_html.gemspec" }
      specify { assert_vendored "gems/plugins/moodle_importer/moodle_importer.gemspec" }
      specify { assert_vendored "releases/20151229153432/releases/20151229152836/shared/bundle/ruby/2.1.0/specifications/best_in_place-3.0.3.gemspec" }
    end

    describe "package.json" do
      let(:manifest_type) { Types::Manifest[:package_json] }

      specify { assert_not_vendored "package.json" }
      specify { assert_not_vendored "/package.json" }
      specify { assert_vendored ".npm/har-validator/1.8.0/package/package.json" }
      specify { assert_vendored "ghost-0.7.1/content/themes/kendo/assets/js/components/ember-data/package.json" }
      specify { assert_vendored "public/tmp/custom_static_compiler-tmp_dest_dir-tFKUAhhM.tmp/ember-data/package.json" }
      specify { assert_vendored ".apm/eslint/2.9.0/package/package.json" }
      specify { assert_vendored "home/.atom/.apm/eslint/1.9.0/package/package.json" }
      specify { assert_vendored ".atom/.npm/browserify/2.26.0/package/package.json" }
    end

    describe "setup.py" do
      let(:manifest_type) { Types::Manifest[:setup_py] }

      specify { assert_not_vendored "setup.py" }
      specify { assert_not_vendored "lib/setup.py" }
      specify { assert_vendored "ENV/lib/python2.7/setup.py" }
    end

    describe "vendored javascript dependency" do
      let(:manifest_type) { Types::Manifest[:vendored_javascript_dependency] }

      specify { assert_not_vendored "jquery.js" }
      specify { assert_not_vendored "lib/jquery.js" }
    end

    describe "Actions" do
      let(:manifest_type) { Types::Manifest[:workflow_yaml] }

      specify { assert_not_vendored ".github/workflows/deploy.yml" }
      specify { assert_not_vendored "/.github/workflows/codespaces.yaml" }
      specify { assert_vendored "vendor/com.github.util/mona_factory.yml" }
    end
  end
end

describe VendorDetection::ManifestPath do
  let(:manifest_type) { Types::Manifest[:gemfile] }
  it "builds a path from a filename and path" do
    expect(described_class.new("/", "Gemfile", manifest_type).path).to eq "/Gemfile"
    expect(described_class.new("/", "foo/bar/Gemfile", manifest_type).path).to eq "/foo/bar/Gemfile"
  end
end
