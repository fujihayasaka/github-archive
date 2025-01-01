require "rails_helper"
require "manifest_adapters"

describe "package-lock.json snapshot parsing" do
  def parse_for_snapshot_submission(attributes = {})
    default_hydro_message = {
      repository_id: 123,
      repository_private: false,
      repository_fork: false,
      manifest_file: {
          filename: "package-lock.json",
          path: "",
          git_ref: "c08a08d39619e804a70ef6a1739a920ae73a402a",
          pushed_at: { seconds: 1665438024, nanos: 0 },
          blob_oid: "0272f4b19df2c52ed179a58630535c92e8c940b1",
        },
      repository_nwo: "foo/bar",
      repository_stargazer_count: 3,
      owner_id: 456,
      is_backfill: false,
      repository_max_manifests: 150,
      snapshot_metadata: {
          associated_manifest: {
             filename: "package.json",
             path: "",
             git_ref: "c08a08d39619e804a70ef6a1739a920ae73a402a",
             pushed_at: { seconds: 1665438024, nanos: 0 },
             blob_oid: "0272f4b19df2c52ed179a58630535c92e8c940b1",
          },
          ref: "refs/heads/main",
          commit_sha: "c08a08d39619e804a70ef6a1739a920ae73a402a",
          push_id: 789
      },
    }.merge(attributes[:hydro_message] || {})

    default_hydro_message[:manifest_file] = attributes[:manifest_file] if attributes[:manifest_file]
    default_hydro_message[:snapshot_metadata][:associated_manifest] = attributes[:associated_manifest] if attributes[:associated_manifest]
    default_hydro_message[:snapshot_metadata] = attributes[:snapshot_metadata] if attributes[:snapshot_metadata]

    ::ManifestAdapters::Npm::SnapshotParsers::PackageLockJson.new(
      content: attributes[:content],
      hydro_message: default_hydro_message,
        # optional; only required for legacy lockfile versions
        associated_content: attributes[:associated_content],
      ).parse
  end

  it "parses a simple, well-formed lockfileVersion 2 package-lock.json file" do
    snap_parser = parse_for_snapshot_submission({
      content: <<-PKGLOCK
{
  "name": "simple",
  "version": "1.2.3",
  "lockfileVersion": 2,
  "license": "MIT",
  "requires": true,
  "packages": {
    "": {
      "version": "1.2.3",
      "license": "MIT",
      "dependencies": {
        "accepts": "*"
      },
      "devDependencies": {}
    },
    "node_modules/accepts": {
      "version": "1.3.7",
      "license": "MIT"
    }
  }
}
      PKGLOCK
    })

    expect(snap_parser.name).to eq("simple")
    expect(snap_parser.version).to eq("1.2.3")
    expect(snap_parser.lockfile_version).to eq(2)

    snapshot = snap_parser.snapshot
    expect(snapshot[:detector][:name]).to eq(ManifestAdapters::Npm::SnapshotParsers::LOCKFILE_DETECTOR)
    expect(snapshot[:job][:correlator]).to eq("123:package-lock.json")
    expect(snapshot[:job][:id]).to eq("789")
    expect(snapshot[:internal]).to be true
    expect(snapshot[:scanned]).to eq(Time.at(1665438024).to_datetime.rfc3339)
    expect(snapshot[:sha]).to eq("c08a08d39619e804a70ef6a1739a920ae73a402a")
    expect(snapshot[:ref]).to eq("refs/heads/main")
    expect(snapshot[:manifests][:"package-lock.json"]).not_to be nil
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_name)).to eq("simple")
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_version)).to eq("1.2.3")
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :license)).to eq("MIT")

    resolved = snapshot[:manifests][:"package-lock.json"][:resolved]
    expect(resolved.length).to eq(1)
    expect(resolved.first[0]).to eq("pkg:npm/accepts@1.3.7")
    expect(resolved.first[1][:package_url]).to eq("pkg:npm/accepts@1.3.7")
    expect(resolved.first[1][:relationship]).to eq("direct")
    expect(resolved.first[1][:scope]).to eq("runtime")
    expect(resolved.first[1].dig(:metadata, :license)).to eq("MIT")
  end

  it "parses a complex lockfileVersion 2 package-lock.json file" do
    # example lockfile borrowed from here:
    # https://github.com/arangodb/arangodb/blob/devel/js/node/package-lock.json
    snap_parser = parse_for_snapshot_submission({
      content: file_fixture("snapshot_v2_package-lock.json").read,
    })

    expect(snap_parser.name).to eq("node") # example file project named for parent dir not package.json decl
    expect(snap_parser.version).to eq("") # example file doesn't set project version
    expect(snap_parser.lockfile_version).to eq(2)

    snapshot = snap_parser.snapshot
    expect(snapshot[:detector][:name]).to eq(ManifestAdapters::Npm::SnapshotParsers::LOCKFILE_DETECTOR)
    expect(snapshot[:job][:correlator]).to eq("123:package-lock.json")
    expect(snapshot[:job][:id]).to eq("789")
    expect(snapshot[:internal]).to be true
    expect(snapshot[:scanned]).to eq(Time.at(1665438024).to_datetime.rfc3339)
    expect(snapshot[:sha]).to eq("c08a08d39619e804a70ef6a1739a920ae73a402a")
    expect(snapshot[:ref]).to eq("refs/heads/main")
    expect(snapshot[:manifests][:"package-lock.json"]).not_to be nil
    expect(snapshot[:manifests][:"package-lock.json"][:resolved]).not_to be_empty
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_name)).to eq("node")
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_version)).to eq("")
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :license)).to eq("")

    resolved = snapshot[:manifests][:"package-lock.json"][:resolved]
    expect(resolved.first[0]).to eq("pkg:npm/%40xmldom/xmldom@0.8.0")
    expect(resolved.first[1][:package_url]).to eq("pkg:npm/%40xmldom/xmldom@0.8.0")
    expect(resolved.first[1][:relationship]).to eq("direct")
    expect(resolved.first[1][:scope]).to eq("development")
    expect(resolved.first[1].dig(:metadata, :license)).to eq("MIT")

    direct_deps = resolved.select { |_, v| v[:relationship] == "direct" }
    expect(direct_deps.keys.length).to eq(37)

    babel = direct_deps.find { |k, _| k == "pkg:npm/babel-code-frame@6.26.0" }[1]
    expect(babel[:package_url]).to eq("pkg:npm/babel-code-frame@6.26.0")
    expect(babel[:relationship]).to eq("direct")
    expect(babel[:scope]).to eq("runtime")
    expect(babel[:dependencies].length).to eq(3)
    expect(babel[:dependencies].first).to eq("pkg:npm/chalk@1.1.3")
    expect(babel.dig(:metadata, :license)).to eq("MIT")

    transitive_deps = resolved.select { |_, v| v[:relationship] == "transitive" }
    expect(transitive_deps.length).to eq(156)

    chalk113 = transitive_deps.find { |k, _| k == "pkg:npm/chalk@1.1.3" }[1]
    expect(chalk113[:package_url]).to eq("pkg:npm/chalk@1.1.3")
    expect(chalk113[:relationship]).to eq("transitive")
    expect(chalk113[:scope]).to eq("runtime")
    expect(chalk113[:dependencies].length).to eq(5)
    expect(chalk113[:dependencies].first).to eq("pkg:npm/ansi-styles@2.2.1")
    expect(chalk113.dig(:metadata, :license)).to eq("MIT")

    runtime_deps = resolved.select { |_, v| v[:scope] == "runtime" }
    expect(runtime_deps.keys.length).to eq(86)

    ansi = runtime_deps.find { |k, _| k == "pkg:npm/ansi-styles@2.2.1" }[1]
    expect(ansi[:package_url]).to eq("pkg:npm/ansi-styles@2.2.1")
    expect(ansi[:relationship]).to eq("transitive")
    expect(ansi[:scope]).to eq("runtime")
    expect(ansi[:dependencies].length).to eq(0)
    expect(ansi.dig(:metadata, :license)).to eq("MIT")

    development_deps = resolved.select { |_, v| v[:scope] == "development" }
    expect(development_deps.keys.length).to eq(107)

    babel_hi = development_deps.find { |k, _| k == "pkg:npm/%40babel/highlight@7.0.0" }[1]
    expect(babel_hi[:package_url]).to eq("pkg:npm/%40babel/highlight@7.0.0")
    expect(babel_hi[:relationship]).to eq("transitive")
    expect(babel_hi[:scope]).to eq("development")
    expect(babel_hi[:dependencies].length).to eq(3)
    expect(babel_hi[:dependencies].first).to eq("pkg:npm/chalk@2.4.2")
    expect(babel_hi.dig(:metadata, :license)).to eq("MIT")

    chalk242 = development_deps.find { |k, _| k == "pkg:npm/chalk@2.4.2" }[1]
    expect(chalk242[:package_url]).to eq("pkg:npm/chalk@2.4.2")
    expect(chalk242[:relationship]).to eq("transitive")
    expect(chalk242[:scope]).to eq("development")
    expect(chalk242[:dependencies].length).to eq(3)
    expect(chalk242[:dependencies].first).to eq("pkg:npm/ansi-styles@3.2.1")
    expect(chalk242.dig(:metadata, :license)).to eq("MIT")
  end

  it "parses simple lockfileVersion 1 package-lock.json without parent package.json" do
    content = <<-PKGLOCK
{
  "name": "simple",
  "version": "0.1.2",
  "lockfileVersion": 1,
  "requires": true,
  "dependencies": {}
}
      PKGLOCK

    snap_parser = parse_for_snapshot_submission({ content: content, associated_content: nil })

    expect(snap_parser.name).to eq("simple")
    expect(snap_parser.version).to eq("0.1.2")
    expect(snap_parser.lockfile_version).to eq(1)

    snapshot = snap_parser.snapshot
    expect(snapshot[:detector][:name]).to eq(ManifestAdapters::Npm::SnapshotParsers::LOCKFILE_DETECTOR)
    expect(snapshot[:job][:correlator]).to eq("123:package-lock.json")
    expect(snapshot[:job][:id]).to eq("789")
    expect(snapshot[:internal]).to be true
    expect(snapshot[:scanned]).to eq(Time.at(1665438024).to_datetime.rfc3339)
    expect(snapshot[:sha]).to eq("c08a08d39619e804a70ef6a1739a920ae73a402a")
    expect(snapshot[:ref]).to eq("refs/heads/main")
    expect(snapshot[:manifests][:"package-lock.json"]).not_to be nil
    expect(snapshot[:manifests][:"package-lock.json"][:resolved]).to be_empty
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_name)).to eq("simple")
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_version)).to eq("0.1.2")
    # project license is extracted from parent package.json file which is not present here
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :license)).to eq("")
  end

  it "parses complex lockfileVersion 1 package-lock.json, without parent package.json or 'requires' lockfile metadata" do
    # without "requires" entries on deps in the lockfile, we can't map deduplicated libs back to packages that
    # declare a dep on them, other than direct package.json decls. nested "dependencies" lists on these packages
    # only include packages that required an _override_ to satisfy the (missing) bounds for the given package.
    snap_parser = parse_for_snapshot_submission({
      content: file_fixture("snapshot_v1_package-lock.json").read,
      associated_content: nil,
    })

    expect(snap_parser.name).to eq("intern-angular")
    expect(snap_parser.version).to eq("1.0.0")
    expect(snap_parser.lockfile_version).to eq(1)

    snapshot = snap_parser.snapshot

    expect(snapshot[:detector][:name]).to eq(ManifestAdapters::Npm::SnapshotParsers::LOCKFILE_DETECTOR)
    expect(snapshot[:job][:correlator]).to eq("123:package-lock.json")
    expect(snapshot[:job][:id]).to eq("789")
    expect(snapshot[:internal]).to be true
    expect(snapshot[:scanned]).to eq(Time.at(1665438024).to_datetime.rfc3339)
    expect(snapshot[:sha]).to eq("c08a08d39619e804a70ef6a1739a920ae73a402a")
    expect(snapshot[:ref]).to eq("refs/heads/main")
    expect(snapshot[:manifests][:"package-lock.json"]).not_to be nil
    expect(snapshot[:manifests][:"package-lock.json"][:resolved]).not_to be_empty
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_name)).to eq("intern-angular")
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_version)).to eq("1.0.0")
    # project license is available on parent package.json which isn't present here
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :license)).to eq("")

    resolved = snapshot[:manifests][:"package-lock.json"][:resolved]
    expect(resolved.first[0]).to eq("pkg:npm/%40angular/animations@4.2.6")
    expect(resolved.first[1][:package_url]).to eq("pkg:npm/%40angular/animations@4.2.6")
    expect(resolved.first[1][:relationship]).to eq("") # ambiguous due to lack of metadata
    expect(resolved.first[1][:scope]).to eq("runtime")
    expect(resolved.first[1][:dependencies]).to be_empty

    # we have no heuristic to label direct deps accurately without package.json or "requires" entries
    direct_deps = resolved.select { |_, v| v[:relationship] == "direct" }
    expect(direct_deps.keys.length).to eq(0)

    unresolved_deps = resolved.select { |_, v| v[:relationship].empty? } # these are RELATIONSHIP_UNKNOWN
    expect(unresolved_deps.keys.length).to eq(398)

    router426 = unresolved_deps.find { |k, _| k == "pkg:npm/%40angular/router@4.2.6" }[1]
    expect(router426[:package_url]).to eq("pkg:npm/%40angular/router@4.2.6")
    expect(router426[:relationship]).to eq("")
    expect(router426[:scope]).to eq("runtime")
    expect(router426[:dependencies]).to be_empty

    # similarly, there are less cases where we can be *sure* a package is a
    # transitive (RELATIONSHIP_TRANSITIVE) dep without parent file or "requires"
    transitive_deps = resolved.select { |_, v| v[:relationship] == "transitive" }
    expect(transitive_deps.keys.length).to eq(122)

    guage274 = transitive_deps.find { |k, _| k == "pkg:npm/gauge@2.7.4" }[1]
    expect(guage274[:package_url]).to eq("pkg:npm/gauge@2.7.4")
    expect(guage274[:relationship]).to eq("transitive")
    expect(guage274[:scope]).to eq("development")
    expect(guage274[:dependencies]).to be_empty

    runtime_deps = resolved.select { |_, v| v[:scope] == "runtime" }
    expect(runtime_deps.keys.length).to eq(16)

    zone0812 = runtime_deps.find { |k, _| k == "pkg:npm/zone.js@0.8.12" }[1]
    expect(zone0812[:package_url]).to eq("pkg:npm/zone.js@0.8.12")
    expect(zone0812[:relationship]).to eq("") # ambiguous due to lack of metadata
    expect(zone0812[:scope]).to eq("runtime")
    expect(zone0812[:dependencies]).to be_empty

    development_deps = resolved.select { |_, v| v[:scope] == "development" }
    expect(development_deps.keys.length).to eq(504)

    tfunk310 = development_deps.find { |k, _| k == "pkg:npm/tfunk@3.1.0" }[1]
    expect(tfunk310[:package_url]).to eq("pkg:npm/tfunk@3.1.0")
    expect(tfunk310[:relationship]).to eq("") #ambiguous due to lack of metadata
    expect(tfunk310[:scope]).to eq("development")
    expect(tfunk310[:dependencies].length).to eq(4)
    expect(tfunk310[:dependencies].first).to eq("pkg:npm/ansi-styles@2.2.1")
    expect(tfunk310[:dependencies].last).to eq("pkg:npm/supports-color@2.0.0")
  end

  it "parses simple lockfileVersion 1 package-lock.json and package.json file pairs" do
    content = <<-PKGLOCK
{
  "name": "simple",
  "version": "0.1.2",
  "lockfileVersion": 1,
  "requires": true,
  "dependencies": {}
}
      PKGLOCK

    associated_content = <<-PKGJSON
{
  "name": "simple",
  "version": "0.1.2",
  "license": "MIT",
  "dependencies": {},
  "devDependencies": {}
}
      PKGJSON

    snap_parser = parse_for_snapshot_submission({ content: content, associated_content: associated_content })

    expect(snap_parser.name).to eq("simple")
    expect(snap_parser.version).to eq("0.1.2")
    expect(snap_parser.lockfile_version).to eq(1)

    snapshot = snap_parser.snapshot
    expect(snapshot[:detector][:name]).to eq(ManifestAdapters::Npm::SnapshotParsers::LOCKFILE_DETECTOR)
    expect(snapshot[:job][:correlator]).to eq("123:package-lock.json")
    expect(snapshot[:job][:id]).to eq("789")
    expect(snapshot[:internal]).to be true
    expect(snapshot[:scanned]).to eq(Time.at(1665438024).to_datetime.rfc3339)
    expect(snapshot[:sha]).to eq("c08a08d39619e804a70ef6a1739a920ae73a402a")
    expect(snapshot[:ref]).to eq("refs/heads/main")
    expect(snapshot[:manifests][:"package-lock.json"]).not_to be nil
    expect(snapshot[:manifests][:"package-lock.json"][:resolved]).to be_empty
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_name)).to eq("simple")
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_version)).to eq("0.1.2")
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :license)).to eq("MIT")
  end

  it "parses complex lockfileVersion 1 package-lock.json and package.json file pairs, without 'requires'" do
    # without "requires" entries on deps in the lockfile, we can't map deduplicated libs back to packages that
    # declare a dep on them, other than direct package.json decls. nested "dependencies" lists on these packages
    # only include packages that required an _override_ to satisfy the (missing) bounds for the given package.
    snap_parser = parse_for_snapshot_submission({
      content: file_fixture("snapshot_v1_package-lock.json").read,
      associated_content: file_fixture("snapshot_v1_package.json").read,
    })

    expect(snap_parser.name).to eq("intern-angular")
    expect(snap_parser.version).to eq("1.0.0")
    expect(snap_parser.lockfile_version).to eq(1)

    snapshot = snap_parser.snapshot

    expect(snapshot[:detector][:name]).to eq(ManifestAdapters::Npm::SnapshotParsers::LOCKFILE_DETECTOR)
    expect(snapshot[:job][:correlator]).to eq("123:package-lock.json")
    expect(snapshot[:job][:id]).to eq("789")
    expect(snapshot[:internal]).to be true
    expect(snapshot[:scanned]).to eq(Time.at(1665438024).to_datetime.rfc3339)
    expect(snapshot[:sha]).to eq("c08a08d39619e804a70ef6a1739a920ae73a402a")
    expect(snapshot[:ref]).to eq("refs/heads/main")
    expect(snapshot[:manifests][:"package-lock.json"]).not_to be nil
    expect(snapshot[:manifests][:"package-lock.json"][:resolved]).not_to be_empty
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_name)).to eq("intern-angular")
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_version)).to eq("1.0.0")
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :license)).to eq("BSD-3-Clause")

    resolved = snapshot[:manifests][:"package-lock.json"][:resolved]
    expect(resolved.first[0]).to eq("pkg:npm/%40angular/animations@4.2.6")
    expect(resolved.first[1][:package_url]).to eq("pkg:npm/%40angular/animations@4.2.6")
    expect(resolved.first[1][:relationship]).to eq("direct")
    expect(resolved.first[1][:scope]).to eq("runtime")
    expect(resolved.first[1][:dependencies]).to be_empty

    direct_deps = resolved.select { |_, v| v[:relationship] == "direct" }
    expect(direct_deps.keys.length).to eq(28)

    router426 = direct_deps.find { |k, _| k == "pkg:npm/%40angular/router@4.2.6" }[1]
    expect(router426[:package_url]).to eq("pkg:npm/%40angular/router@4.2.6")
    expect(router426[:relationship]).to eq("direct")
    expect(router426[:scope]).to eq("runtime")
    expect(router426[:dependencies]).to be_empty

    transitive_deps = resolved.select { |_, v| v[:relationship] == "transitive" }
    expect(transitive_deps.keys.length).to eq(122)

    fe061 = transitive_deps.find { |k, _| k == "pkg:npm/forever-agent@0.6.1" }[1]
    expect(fe061[:package_url]).to eq("pkg:npm/forever-agent@0.6.1")
    expect(fe061[:relationship]).to eq("transitive")
    expect(fe061[:scope]).to eq("development")
    expect(fe061[:dependencies]).to be_empty

    runtime_deps = resolved.select { |_, v| v[:scope] == "runtime" }
    expect(runtime_deps.keys.length).to eq(16)

    zone0812 = runtime_deps.find { |k, _| k == "pkg:npm/zone.js@0.8.12" }[1]
    expect(zone0812[:package_url]).to eq("pkg:npm/zone.js@0.8.12")
    expect(zone0812[:relationship]).to eq("direct")
    expect(zone0812[:scope]).to eq("runtime")
    expect(zone0812[:dependencies]).to be_empty

    development_deps = resolved.select { |_, v| v[:scope] == "development" }
    expect(development_deps.keys.length).to eq(504)

    dev043 = development_deps.find { |k, _| k == "pkg:npm/%40theintern/dev@0.4.3" }[1]
    expect(dev043[:package_url]).to eq("pkg:npm/%40theintern/dev@0.4.3")
    # this is a transitive, but without "requires" lists it's impossible to
    # determine it's full parentage; if it's parent is also transitive, it
    # could be a "rootless" component we can't surface in the UI drilldown
    # where 1st tier are *directs* ...so we label it RELATIONSHIP_UNKNOWN
    expect(dev043[:relationship]).to eq("")
    expect(dev043[:scope]).to eq("development")
    expect(dev043[:dependencies].length).to eq(7)
    expect(dev043[:dependencies].first).to eq("pkg:npm/ansi-styles@3.1.0")
    expect(dev043[:dependencies].last).to eq("pkg:npm/typescript@2.4.1")
  end

  it "parses complex lockfileVersion 1 package-lock.json and package.json file pairs, with 'requires'" do
    # like the v2+ lockfile format, old lockfiles declaring "requires" clauses allow us to fully map
    # every resolved package version back to a direct (package.json) or transitive dep on particular
    # packages that required deduplicating or an alternate-versioned entry in the snapshot
    snap_parser = parse_for_snapshot_submission({
      content: file_fixture("snapshot-with-requires_v1_package-lock.json").read,
      associated_content: file_fixture("snapshot-with-requires_v1_package.json").read,
    })

    expect(snap_parser.name).to eq("bluez")
    expect(snap_parser.version).to eq("0.4.4")
    expect(snap_parser.lockfile_version).to eq(1)

    snapshot = snap_parser.snapshot

    expect(snapshot[:detector][:name]).to eq(ManifestAdapters::Npm::SnapshotParsers::LOCKFILE_DETECTOR)
    expect(snapshot[:job][:correlator]).to eq("123:package-lock.json")
    expect(snapshot[:job][:id]).to eq("789")
    expect(snapshot[:internal]).to be true
    expect(snapshot[:scanned]).to eq(Time.at(1665438024).to_datetime.rfc3339)
    expect(snapshot[:sha]).to eq("c08a08d39619e804a70ef6a1739a920ae73a402a")
    expect(snapshot[:ref]).to eq("refs/heads/main")
    expect(snapshot[:manifests][:"package-lock.json"]).not_to be nil
    expect(snapshot[:manifests][:"package-lock.json"][:resolved]).not_to be_empty
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_name)).to eq("bluez")
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :project_version)).to eq("0.4.4")
    expect(snapshot[:manifests][:"package-lock.json"].dig(:metadata, :license)).to eq("MIT")

    resolved = snapshot[:manifests][:"package-lock.json"][:resolved]
    expect(resolved.first[0]).to eq("pkg:npm/abbrev@1.1.1")
    expect(resolved.first[1][:package_url]).to eq("pkg:npm/abbrev@1.1.1")
    expect(resolved.first[1][:relationship]).to eq("transitive")
    expect(resolved.first[1][:scope]).to eq("runtime")
    expect(resolved.first[1][:dependencies]).to be_empty

    direct_deps = resolved.select { |_, v| v[:relationship] == "direct" }
    expect(direct_deps.keys.length).to eq(2)

    dbus107 = direct_deps.find { |k, _| k == "pkg:npm/dbus@1.0.7" }[1]
    expect(dbus107[:package_url]).to eq("pkg:npm/dbus@1.0.7")
    expect(dbus107[:relationship]).to eq("direct")
    expect(dbus107[:scope]).to eq("runtime")

    # dbus lists a *requires* on "nan" at version spec "^2.14.0"
    # that should have been resolved to an exact version for snapshot
    expect(dbus107[:dependencies].length).to eq(1)
    expect(dbus107[:dependencies].first).to eq("pkg:npm/nan@2.15.0")

    transitive_deps = resolved.select { |_, v| v[:relationship] == "transitive" }
    expect(transitive_deps.keys.length).to eq(103)

    nan2150 = transitive_deps.find { |k, _| k == "pkg:npm/nan@2.15.0" }[1]
    expect(nan2150[:package_url]).to eq("pkg:npm/nan@2.15.0")
    expect(nan2150[:relationship]).to eq("transitive")
    expect(nan2150[:scope]).to eq("runtime")
    expect(nan2150[:dependencies]).to be_empty

    runtime_deps = resolved.select { |_, v| v[:scope] == "runtime" }
    expect(runtime_deps.keys.length).to eq(105)

    # this version is resolved based on readable-stream pkg's "requires" of "~1.0.0"
    cui103 = transitive_deps.find { |k, _| k == "pkg:npm/core-util-is@1.0.3" }[1]
    expect(cui103[:package_url]).to eq("pkg:npm/core-util-is@1.0.3")
    expect(cui103[:relationship]).to eq("transitive")
    expect(cui103[:scope]).to eq("runtime")
    expect(cui103[:dependencies]).to be_empty

    rs237 = transitive_deps.find { |k, _| k == "pkg:npm/readable-stream@2.3.7" }[1]
    expect(rs237[:package_url]).to eq("pkg:npm/readable-stream@2.3.7")
    expect(rs237[:relationship]).to eq("transitive")
    expect(rs237[:scope]).to eq("runtime")
    expect(rs237[:dependencies].length).to eq(7)
    expect(rs237[:dependencies].include?("pkg:npm/core-util-is@1.0.3")).to be true

    # this version is a nested override declared on verror pkg's "requires" pinned to "1.0.2"
    cui102 = transitive_deps.find { |k, _| k == "pkg:npm/core-util-is@1.0.2" }[1]
    expect(cui102[:package_url]).to eq("pkg:npm/core-util-is@1.0.2")
    expect(cui102[:relationship]).to eq("transitive")
    expect(cui102[:scope]).to eq("runtime")
    expect(cui102[:dependencies]).to be_empty

    rs237 = transitive_deps.find { |k, _| k == "pkg:npm/verror@1.10.0" }[1]
    expect(rs237[:package_url]).to eq("pkg:npm/verror@1.10.0")
    expect(rs237[:relationship]).to eq("transitive")
    expect(rs237[:scope]).to eq("runtime")
    expect(rs237[:dependencies].length).to eq(3)
    expect(rs237[:dependencies].include?("pkg:npm/core-util-is@1.0.2")).to be true

    # this project's package.json declares no dev dependencies; snap includes none too
    development_deps = resolved.select { |_, v| v[:scope] == "development" }
    expect(development_deps.keys).to be_empty
  end

  it "raises an exception when the lockfile JSON content is malformed" do
    assert_raises ManifestAdapters::Npm::SnapshotParsers::MalformedLockfileError do
      parse_for_snapshot_submission({
        content: "{]",
      })
    end
  end

  it "raises an exception when the lockfile content is missing" do
    assert_raises ManifestAdapters::Npm::SnapshotParsers::MalformedLockfileError do
      parse_for_snapshot_submission({
        content: "",
      })
    end
  end

  it "raises an exception when the Hydro change event is missing" do
    assert_raises ManifestAdapters::Npm::SnapshotParsers::MalformedEventError do
      parse_for_snapshot_submission({
        manifest_file: {}, # this is an inner field on the manifest changed Hydro event
        content: <<-PKGLOCK
{
  "name": "simple",
  "version": "1.2.3",
  "lockfileVersion": 2,
  "license": "MIT",
  "requires": true,
  "packages": {
    "": {
      "version": "1.2.3",
      "license": "MIT",
      "dependencies": {},
      "devDependencies": {}
    }
  }
}
        PKGLOCK
      })
    end
  end

  it "raises an exception when parsing a lockfile and the Hydro event is missing enriched snapshot metadata" do
    assert_raises ManifestAdapters::Npm::SnapshotParsers::MalformedEventError do
      content = <<-PKGLOCK
{
  "name": "simple",
  "version": "0.1.2",
  "lockfileVersion": 1,
  "requires": true,
  "dependencies": {}
}
      PKGLOCK

      parse_for_snapshot_submission({ content: content, snapshot_metadata: {} })
    end
  end

  it "raises an exception when parsing an old lockfile version and the associated 'package.json' content is missing" do
    assert_raises ManifestAdapters::Npm::SnapshotParsers::MalformedManifestError do
      content = <<-PKGLOCK
{
  "name": "simple",
  "version": "0.1.2",
  "lockfileVersion": 1,
  "requires": true,
  "dependencies": {}
}
      PKGLOCK

      parse_for_snapshot_submission({ content: content, associated_content: "" })
    end
  end

  it "raises an exception when parsing an old lockfile version and the associated 'package.json' content is malformed" do
    assert_raises ManifestAdapters::Npm::SnapshotParsers::MalformedManifestError do
      content = <<-PKGLOCK
{
  "name": "simple",
  "version": "0.1.2",
  "lockfileVersion": 1,
  "requires": true,
  "dependencies": {}
}
      PKGLOCK

      parse_for_snapshot_submission({ content: content, associated_content: "{]" })
    end
  end

  # quick hack to print a copy of the snapshot submission generated in a test case
  def view_snapshot(snapshot, local_filename)
    File.open(local_filename, "w") do |f|
      f << snapshot.to_json
    end
  end
end
