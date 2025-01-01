/* This file inserts roughly the bare minimum data for example snapshot queries to work out of the box.

This script is not idempotent. Subsequent runs will all create rudundant rows,
but the extra rows won't hurt anything.

we'll need at least one row in each of the following tables:
* ds_build_types -- this is the build type for the current build
* ds_snapshot_blobs -- where actual snapshot contents go
* ds_builds -- this is the current build
* ds_snapshots -- point to the snapshot blob and link it to a commit sha
*/

-- use an example repository ID that github.localhost is unlikely to ever use
set @repo_id = 45678;
set @commit_sha ='ddc951f4b1293222421f2c8df679786153acf689';
set @external_build_id = 'dev-data-build-type';
-- a snapshot with a package-lock.json file
set @js_snapshot = '{"version":0,"ref":"refs/heads/main","sha":"ddc951f4b1293222421f2c8df679786153acf689","job":{"name":"build","id":"0"},"detector":{"name":"dev-data.sql"},"scanned":"2021-10-25T21:05:16Z","manifests":{"package-lock.json":{"name":"package-lock.json","file":{"source_location":"package-lock.json"},"resolved":{"@actions/core":{"purl":"pkg:/npm/%40actions/core@1.6.0","relationship":"direct","dependencies":["@actions/http-client"]},"@actions/http-client":{"purl":"pkg:/npm/%40actions/http-client@1.0.11","relationship":"indirect","dependencies":["tunnel"]},"tunnel":{"purl":"pkg:/npm/tunnel@0.0.6","relationship":"indirect"}}}}}';
set @js_snapshot_bytes = 627;
set @js_snapshot_sha = '27fecb7ee2e74adef0c76ddfb02ff92d49a03843cd523c9c30788c919854bfdf';
-- a snapshot with a Gemfile.lock file
set @ruby_snapshot = '{"version":0,"ref":"refs/heads/main","sha":"ddc951f4b1293222421f2c8df679786153acf689","job":{"name":"ruby build","id":"0"},"detector":{"name":"dev-data.sql"},"scanned":"2021-10-25T22:05:16Z","manifests":{"Gemfile.lock":{"name":"Gemfile.lock","file":{"source_location":"Gemfile.lock"},"resolved":{"rails":{"purl":"pkg:gem/rails@5.6.1","relationship":"direct","dependencies":[]}}}}}';
set @ruby_snapshot_bytes = 383;
set @ruby_snapshot_sha = '19a9c75d6461f82cc8ce1f598f7b0b1f1340dc6d92d781fce2eb0549371752d8';

-- create a build type
set @now = now(); -- doing this to make sure the times match within each row, but not necessarily for subsequent rows
insert into ds_build_types (repository_id, external_type_id, external_type_id_display, created_at, updated_at) values (@repo_id, @external_build_id, @external_build_id, @now, @now);
set @build_type_id = last_insert_id();

-- insert a js snapshot for the current tip of the default branch:
set @scanned = now();
insert into ds_snapshot_blobs (repository_id, blob_size_bytes, created_at, blob_hash, `blob`) values (@repo_id, @js_snapshot_bytes, @scanned, @js_snapshot_sha, @js_snapshot);
set @snapshot_blob_id = last_insert_id();

-- create a new build for the js snapshot
set @now = now();
insert into ds_builds (repository_id, external_build_id, build_type_id, scanned_at, created_at, updated_at) values (@repo_id, @external_build_id, @build_type_id, @scanned, @now, @now);
set @build_id = last_insert_id();

-- insert the snapshot record pointing to the js blob
insert into ds_snapshots (repository_id, snapshot_blob_id, source, sha, metadata, created_at, build_id, branch_ref) values (@repo_id, @snapshot_blob_id, 'Example data', @commit_sha, '{"example":true}', @scanned, @build_id, 'refs/heads/main');

-- insert a ruby snapshot for the current tip of the default branch:
set @scanned = now();
insert into ds_snapshot_blobs (repository_id, blob_size_bytes, created_at, blob_hash, `blob`) values (@repo_id, @ruby_snapshot_bytes, @scanned, @ruby_snapshot_sha, @ruby_snapshot);
set @snapshot_blob_id = last_insert_id();

-- create a new build for the ruby snapshot
set @now = now();
insert into ds_builds (repository_id, external_build_id, build_type_id, scanned_at, created_at, updated_at) values (@repo_id, @external_build_id, @build_type_id, @scanned, @now, @now);
set @build_id = last_insert_id();

-- insert the snapshot record pointing to the ruby blob
insert into ds_snapshots (repository_id, snapshot_blob_id, source, sha, metadata, created_at, build_id, branch_ref) values (@repo_id, @snapshot_blob_id, 'Example data', @commit_sha, '{"example":true}', @scanned, @build_id, 'refs/heads/main');
