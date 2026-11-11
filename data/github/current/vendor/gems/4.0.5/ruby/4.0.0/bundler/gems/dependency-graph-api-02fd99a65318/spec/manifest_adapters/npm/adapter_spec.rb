require "rails_helper"

describe ManifestAdapters::Npm::Adapter do
  let(:file) do
    {
      name: "my-lib",
      version: "1.1.0",
      description: "A useful library",
      main: "index.js",
      keywords: [],
      author: "mona",
      license: "UNLICENSED",
      scripts: {},
      dependencies: {
        express: "4.15.3",
        socket_io: "2.0.3"
      },
      devDependencies: {
        gulp: "^ 3.9.1"
      }
    }.to_json
  end

  def build_manifest(attributes = {})
    ManifestAdapters.parse(**{
      git_ref: "7871638",
      github_repository_id: 55,
      filename: "package.json",
      content: file,
      path: nil,
      pushed_at: Time.now,
      fork: false,
      visibility_private: false
    }.merge(attributes))
  end

  def dependency(args)
    ManifestAdapters::Manifest::Dependency.new(**args)
  end

  describe ".test" do
    def test(filename, path)
      described_class.test(filename: filename, path: path)
    end

    it "recognizes package.json files at the root" do
      expect(test("package.json", "")).to be_truthy
      expect(test("package.json", "/")).to be_truthy
      expect(test("package.json", nil)).to be_truthy
    end

    it "recognizes package-lock.json files at the root" do
      expect(test("package-lock.json", "")).to be_truthy
      expect(test("package-lock.json", "/")).to be_truthy
      expect(test("package-lock.json", nil)).to be_truthy
    end

    it "recognizes package(-lock).json files in non-vendor subdirectories" do
      expect(test("package.json", "lib")).to be_truthy
      expect(test("package-lock.json", "lib")).to be_truthy
    end

    it "doesn't recognize other files" do
      expect(test("whatever.json", "")).to be_falsey
      expect(test("Gemfile", "")).to be_falsey
      expect(test("SECRETS.md", "")).to be_falsey
    end
  end

  describe "package.json parsing" do
    let(:manifest) { build_manifest }

    specify { expect(manifest).to_not be_malformed }
    specify { expect(manifest.dependent_name).to eq "my-lib" }
    specify { expect(manifest.dependent_version).to eq "1.1.0" }
    specify { expect(manifest.git_ref).to eq "7871638" }
    specify { expect(manifest.github_repository_id).to eq 55 }
    specify { expect(manifest.filename).to eq "package.json" }
    specify { expect(build_manifest(path: nil).path).to eq "" }
    specify { expect(build_manifest(path: "").path).to eq "" }

    describe "#dependencies" do
      it "parses dependencies" do
        expect(manifest.dependencies).to match_array [
          dependency(package_name: "express", scope: Types::Scope[:runtime], requirements: "= 4.15.3", raw_requirements: "4.15.3"),
          dependency(package_name: "socket_io", scope: Types::Scope[:runtime], requirements: "= 2.0.3", raw_requirements: "2.0.3"),
          dependency(package_name: "gulp", scope: Types::Scope[:development], requirements: "^ 3.9.1", raw_requirements: "^ 3.9.1"),
        ]
      end
    end

    describe "normalizing requirements" do
      specify { expect(normalized("> 4.1.5")).to eq "> 4.1.5" }
      specify { expect(normalized("4.1.5")).to eq "= 4.1.5" }
      specify { expect(normalized("4.1.x")).to eq "~> 4.1.0" }
      specify { expect(normalized("4.x.x")).to eq "~> 4.0.0" }
      specify { expect(normalized("4.x")).to eq "~> 4.0" }
      specify { expect(normalized("*")).to eq "" }
      specify { expect(normalized("latest")).to eq "" }
      specify { expect(normalized("beta")).to eq "" }
      specify { expect(normalized("v4.1.1")).to eq "= 4.1.1" }
      specify { expect(normalized("> 2.3.0  < 2.4.0")).to eq "> 2.3.0,< 2.4.0" }
      specify { expect(normalized("2.3.0 - 2.4.0")).to eq ">= 2.3.0,<= 2.4.0" }
      specify { expect(normalized("0.19.3-beta")).to eq "= 0.19.3-beta" }
    end

    describe "malformed JSON" do
      it "doesn't throw errors" do
        manifest = build_manifest({
          content: <<~PACKAGE_JSON
            {
              "name": "my-lib",
              "version": "1.1.0",
              "description": "A useful library",
              "main": "index.js",
              <<<<<<<<<
              "keywords": [],
              "author": "mona",
              >>>>>>>>>
              "license": "UNLICENSED"
              "scripts": {},
              "dependencies": {
                true,
                "express": "4.15.3",
                "socket_io": "2.0.3"
              },
              "devDependencies": {
                "gulp": "^ 3.9.1"
              }
            }
          PACKAGE_JSON
        })

        expect(manifest).to be_malformed
      end

      it "considers an empty, parseable string malformed" do
        manifest = build_manifest({
          content: <<~PACKAGE_JSON
            [10]
          PACKAGE_JSON
        })

        expect(manifest).to be_malformed
      end

      it "doesn't include malformed dependencies" do
        manifest = build_manifest({
          content: <<~PACKAGE_JSON
            {
              "name": "my-lib",
              "version": "1.1.0",
              "dependencies": [
                {"react": "1.0.0"}
              ]
            }
          PACKAGE_JSON
        })

        expect(manifest.dependencies).to be_empty

        manifest = build_manifest({
          content: <<~PACKAGE_JSON
            {
              "name": "my-lib",
              "version": "1.1.0",
              "dependencies": [
                {"": "1.0.0"},
                { true: "0.0.0" },
                { "my-package": 12345 },
                { "my-package": {"name": "value"} },
                { "pHaNiRaJ": "1.0.0" },
                { "          ": "1.0.0" },
                {"pHaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaNiRaJ": "1.0.0"},

              ]
            }
          PACKAGE_JSON
        })

        expect(manifest.dependencies).to be_empty
      end
    end

    it "sets manifest_type to unknown for unity manifests " do
      expect(build_manifest(content: '{ "unity": "2018.3.0f2"}').send(:manifest_type)).to eq Types::Manifest[:unknown]
      expect(build_manifest(content: '{ "unityRelease": "0b5", "dependencies": { "some-package": "3.5.0" } }').send(:manifest_type)).to eq Types::Manifest[:unknown]
      expect(build_manifest(content: '{ "dependencies": { "some-package": "1.0.0", "com.unity.some-package": "3.5.0" } }').send(:manifest_type)).to eq Types::Manifest[:unknown]
    end

    def normalized(requirements)
      ManifestAdapters::Npm::Requirements.new(requirements).normalize
    end
  end

  describe "package-lock.json parsing" do
    let(:file) do
      {
        name: "my-lib",
        version: "1.1.0",
        dependencies: {
          express: {
            version: "4.15.3",
            dev: false,
          },
          boolean_dependency: true,
          socket_io: {
            version: "2.0.3",
            dev: false,
          },
          gulp: {
            version: "3.9.1",
            dev: true,
          }
        },
      }.to_json
    end

    let(:manifest) { build_manifest(filename: "package-lock.json") }
    specify { expect(manifest).to_not be_malformed }
    specify { expect(manifest.dependent_name).to eq "my-lib" }
    specify { expect(manifest.dependent_version).to eq "1.1.0" }
    specify { expect(manifest.git_ref).to eq "7871638" }
    specify { expect(manifest.github_repository_id).to eq 55 }
    specify { expect(manifest.filename).to eq "package-lock.json" }
    specify { expect(build_manifest(path: nil).path).to eq "" }

    describe "#dependencies" do
      it "parses dependencies" do
        expect(manifest.dependencies).to match_array [
          dependency(package_name: "express", scope: Types::Scope[:runtime], requirements: "= 4.15.3", raw_requirements: "4.15.3"),
          dependency(package_name: "socket_io", scope: Types::Scope[:runtime], requirements: "= 2.0.3", raw_requirements: "2.0.3"),
          dependency(package_name: "gulp", scope: Types::Scope[:development], requirements: "= 3.9.1", raw_requirements: "3.9.1"),
        ]
      end
    end

    describe "package-lock with multiple versions of same dependency" do
      # inspired by github/dg-npm-multiple-dependencies
      let (:file) do
        {
          "name": "dg-npm-multiple-dependencies",
          "version": "1.0.0",
          "lockfileVersion": 2,
          "packages": {
            "": {
              "name": "dg-npm-multiple-dependencies",
              "version": "1.0.0",
              "dependencies": {
                "foo-shares-package-yargs-parser": "^1.0.0",
                "bar-shares-package-yargs-parser": "^1.0.0"
              }
            },
          },
          "dependencies": {
            "foo-shares-package-yargs-parser": {
              "version": "1.0.0",
            },
            "bar-shares-package-yargs-parser": {
              "version": "1.0.0",
              "dependencies": {
                "yargs-parser": {
                  "version": "18.1.3",
                  "dependencies": {
                    "decamelize": {
                      "version": "2.4.5"
                    }
                  }
                }
              }
            },
            "decamelize": {
              "version": "1.2.0",
            },
            "yargs-parser": {
              "version": "2.4.1",
            }
          }
        }.to_json
      end

      let(:manifest) { build_manifest(filename: "package-lock.json") }
      specify { expect(manifest).to_not be_malformed }
      specify { expect(manifest.dependent_name).to eq "dg-npm-multiple-dependencies" }
      specify { expect(manifest.dependent_version).to eq "1.0.0" }

      describe "#dependencies" do
        it "parses dependencies" do
          expect(manifest.dependencies.map { |d| [d.package_name, d.requirements] }.sort).to match_array [
            ["bar-shares-package-yargs-parser", "= 1.0.0"],
            ["foo-shares-package-yargs-parser", "= 1.0.0"],
            ["decamelize", "= 1.2.0"],
            ["decamelize", "= 2.4.5"],
            ["yargs-parser", "= 18.1.3"],
            ["yargs-parser", "= 2.4.1"]
          ]
        end
      end
    end
  end

  describe "package-lock.json v3 parsing" do
    describe "with multiple versions of same dependency" do
      # inspired by github/dg-npm-multiple-dependencies
      let (:file) do
        <<-JSON
        {
          "name": "dg-npm-multiple-dependencies",
          "version": "1.0.0",
          "lockfileVersion": 2,
          "requires": true,
          "packages": {
            "": {
              "name": "dg-npm-multiple-dependencies",
              "version": "1.0.0",
              "license": "ISC",
              "dependencies": {
                "@reiddraper/npm-yargs-test-a": "^1.0.0",
                "@reiddraper/npm-yargs-test-b": "^1.0.0"
              }
            },
            "node_modules/@reiddraper/npm-yargs-test-a": {
              "version": "1.0.0",
              "resolved": "https://registry.npmjs.org/@reiddraper/npm-yargs-test-a/-/npm-yargs-test-a-1.0.0.tgz",
              "integrity": "sha512-LRAqzXhewK/uienvz6B3I7CAwkTyKZe5TjGQqD/6EOe1vBbnyInTHZRgsbha42ms9aiE7Oypn7KceFms7qQrBQ==",
              "dependencies": {
                "yargs-parser": "2.4.1"
              }
            },
            "node_modules/@reiddraper/npm-yargs-test-b": {
              "version": "1.0.0",
              "resolved": "https://registry.npmjs.org/@reiddraper/npm-yargs-test-b/-/npm-yargs-test-b-1.0.0.tgz",
              "integrity": "sha512-oZa4J/4/kzHG7ovdMat0eeZAnSIrmoy7YDsThpXqlYM0TxgUUce40aM/YlNPg9aw0Kbes+gJll2zK/oqiSJr2w==",
              "dependencies": {
                "yargs-parser": "18.1.3"
              }
            },
            "node_modules/@reiddraper/npm-yargs-test-b/node_modules/camelcase": {
              "version": "5.3.1",
              "resolved": "https://registry.npmjs.org/camelcase/-/camelcase-5.3.1.tgz",
              "integrity": "sha512-L28STB170nwWS63UjtlEOE3dldQApaJXZkOI1uMFfzf3rRuPegHaHesyee+YxQ+W6SvRDQV6UrdOdRiR153wJg==",
              "engines": {
                "node": ">=6"
              }
            },
            "node_modules/@reiddraper/npm-yargs-test-b/node_modules/yargs-parser": {
              "version": "18.1.3",
              "resolved": "https://registry.npmjs.org/yargs-parser/-/yargs-parser-18.1.3.tgz",
              "integrity": "sha512-o50j0JeToy/4K6OZcaQmW6lyXXKhq7csREXcDwk2omFPJEwUNOVtJKvmDr9EI1fAJZUyZcRF7kxGBWmRXudrCQ==",
              "dependencies": {
                "camelcase": "^5.0.0",
                "decamelize": "^1.2.0"
              },
              "engines": {
                "node": ">=6"
              }
            },
            "node_modules/camelcase": {
              "version": "3.0.0",
              "resolved": "https://registry.npmjs.org/camelcase/-/camelcase-3.0.0.tgz",
              "integrity": "sha1-MvxLn82vhF/N9+c7uXysImHwqwo=",
              "engines": {
                "node": ">=0.10.0"
              }
            },
            "node_modules/decamelize": {
              "version": "1.2.0",
              "resolved": "https://registry.npmjs.org/decamelize/-/decamelize-1.2.0.tgz",
              "integrity": "sha1-9lNNFRSCabIDUue+4m9QH5oZEpA=",
              "engines": {
                "node": ">=0.10.0"
              }
            },
            "node_modules/lodash.assign": {
              "version": "4.2.0",
              "resolved": "https://registry.npmjs.org/lodash.assign/-/lodash.assign-4.2.0.tgz",
              "integrity": "sha1-DZnzzNem0mHRm9rrkkUAXShYCOc="
            },
            "node_modules/yargs-parser": {
              "version": "2.4.1",
              "resolved": "https://registry.npmjs.org/yargs-parser/-/yargs-parser-2.4.1.tgz",
              "integrity": "sha1-hVaN488VD/SfpRgl8DqMiA3cxcQ=",
              "dependencies": {
                "camelcase": "^3.0.0",
                "lodash.assign": "^4.0.6"
              }
            }
          },
          "dependencies": {
            "@reiddraper/npm-yargs-test-a": {
              "version": "1.0.0",
              "resolved": "https://registry.npmjs.org/@reiddraper/npm-yargs-test-a/-/npm-yargs-test-a-1.0.0.tgz",
              "integrity": "sha512-LRAqzXhewK/uienvz6B3I7CAwkTyKZe5TjGQqD/6EOe1vBbnyInTHZRgsbha42ms9aiE7Oypn7KceFms7qQrBQ==",
              "requires": {
                "yargs-parser": "2.4.1"
              }
            },
            "@reiddraper/npm-yargs-test-b": {
              "version": "1.0.0",
              "resolved": "https://registry.npmjs.org/@reiddraper/npm-yargs-test-b/-/npm-yargs-test-b-1.0.0.tgz",
              "integrity": "sha512-oZa4J/4/kzHG7ovdMat0eeZAnSIrmoy7YDsThpXqlYM0TxgUUce40aM/YlNPg9aw0Kbes+gJll2zK/oqiSJr2w==",
              "requires": {
                "yargs-parser": "18.1.3"
              },
              "dependencies": {
                "camelcase": {
                  "version": "5.3.1",
                  "resolved": "https://registry.npmjs.org/camelcase/-/camelcase-5.3.1.tgz",
                  "integrity": "sha512-L28STB170nwWS63UjtlEOE3dldQApaJXZkOI1uMFfzf3rRuPegHaHesyee+YxQ+W6SvRDQV6UrdOdRiR153wJg=="
                },
                "yargs-parser": {
                  "version": "18.1.3",
                  "resolved": "https://registry.npmjs.org/yargs-parser/-/yargs-parser-18.1.3.tgz",
                  "integrity": "sha512-o50j0JeToy/4K6OZcaQmW6lyXXKhq7csREXcDwk2omFPJEwUNOVtJKvmDr9EI1fAJZUyZcRF7kxGBWmRXudrCQ==",
                  "requires": {
                    "camelcase": "^5.0.0",
                    "decamelize": "^1.2.0"
                  }
                }
              }
            },
            "camelcase": {
              "version": "3.0.0",
              "resolved": "https://registry.npmjs.org/camelcase/-/camelcase-3.0.0.tgz",
              "integrity": "sha1-MvxLn82vhF/N9+c7uXysImHwqwo="
            },
            "decamelize": {
              "version": "1.2.0",
              "resolved": "https://registry.npmjs.org/decamelize/-/decamelize-1.2.0.tgz",
              "integrity": "sha1-9lNNFRSCabIDUue+4m9QH5oZEpA="
            },
            "lodash.assign": {
              "version": "4.2.0",
              "resolved": "https://registry.npmjs.org/lodash.assign/-/lodash.assign-4.2.0.tgz",
              "integrity": "sha1-DZnzzNem0mHRm9rrkkUAXShYCOc="
            },
            "yargs-parser": {
              "version": "2.4.1",
              "resolved": "https://registry.npmjs.org/yargs-parser/-/yargs-parser-2.4.1.tgz",
              "integrity": "sha1-hVaN488VD/SfpRgl8DqMiA3cxcQ=",
              "requires": {
                "camelcase": "^3.0.0",
                "lodash.assign": "^4.0.6"
              }
            }
          }
        }
        JSON
      end

      let(:manifest_as_v2) {
        build_manifest(
          filename: "package-lock.json",
          content: JSON.parse(file).merge(lockfileVersion: 2).to_json,
        )
      }

      let(:manifest_as_v3) {
        build_manifest(
          filename: "package-lock.json",
          content: JSON.parse(file).merge(lockfileVersion: 3).except("dependencies").to_json,
        )
      }

      it "parses dependencies in same way for v2 and v3" do
        v2_dependencies = manifest_as_v2.dependencies.map { |d| [d.package_name, d.requirements] }.sort
        v3_dependencies = manifest_as_v3.dependencies.map { |d| [d.package_name, d.requirements] }.sort
        expect(v2_dependencies).to eq(v3_dependencies)
      end
    end

    describe "behaves sensibly with workspaces" do
      # Based on https://github.com/dsp-testing/hm-npm-workspaces
      # Also see https://github.com/github/dependency-graph-api/pull/3274#issuecomment-1451878399.
      let (:file) do
        <<-JSON
        {
          "name": "npm-workspaces",
          "lockfileVersion": 3,
          "packages": {
            "node_modules/react": {
              "version": "15.0.0"
            },
            "project-1": {
              "dependencies": {
                  "react": "15.0.0"
              }
            },
            "project-2/node_modules/react": {
              "version": "16.0.0"
            },
            "node_modules/project-1": {
              "resolved": "project-1",
              "link": true
            }
          }
        }
        JSON
      end

      let(:manifest) {
        build_manifest(filename: "package-lock.json")
      }

      it "ignores internal workspace dependencies" do
        dependencies = manifest.dependencies.map { |d| [d.package_name, d.requirements] }.sort
        expect(dependencies).to eq([
          ["react", "= 15.0.0"],
          ["react", "= 16.0.0"]
        ])
      end
    end
  end
end
