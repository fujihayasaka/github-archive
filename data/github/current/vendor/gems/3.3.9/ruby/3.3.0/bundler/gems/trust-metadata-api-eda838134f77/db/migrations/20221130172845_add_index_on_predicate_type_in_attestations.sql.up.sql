-- We want to look up attestations by predicate_type. Therefore, we'll want to
-- add the predicate_type column to an index.

-- First, let's drop the existing index:
DROP INDEX tenant_purl_attestations_idx on attestations;

-- In mysql index keys are limited to to 3072 bytes. In this point in time, we
-- have an index on {tenant_id (4), purl (4 * 767)} aka {4, 3068} bytes.
-- So in order to add the predicate_type to the index, we will have to reduce
-- the max size of the purl column. How long should purls be?

-- It's hard to know exactly how long folks might want to make purl strings,
-- since the standard allows lots of extra metadata. i.e. the longest example
-- in https://github.com/package-url/purl-spec/blob/master/PURL-TYPES.rst
-- is 245 characters long.

-- How long should we allow predicate_types to be? We feel relatively 
-- confident folks won't need strings much longer than 
-- "https://slsa.dev/provenance/v0.2" (32 chars); there is less room
-- for shenanigans in the predicate_type.

-- Completely arbitrarily let's say... predicate_types get to be 128 chars long.
-- Let's then arbitrarily say that purls can be a max 512 chars long.
-- Nice, clean, powers of 2. So our index ends up being:
-- {tenant_id (4), purl (2048), predicate_type (512) } = 2564 bytes, with plenty
-- of room for growing the index in the future (i.e. adding owner_id, repo_id)

-- Let's resize purls & predicate_types:
ALTER TABLE attestations CHANGE COLUMN purl purl VARCHAR(512) DEFAULT NULL;
ALTER TABLE attestations CHANGE COLUMN predicate_type predicate_type VARCHAR(128) NOT NULL;

-- and then we add the new index:
CREATE INDEX tenant_id_purl_predicate_type_attestations_idx ON attestations (tenant_id, purl, predicate_type);
