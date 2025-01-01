# Import

The import process is how Advisory DB downloads and parses security feeds and
then persists each of the feeds' entries in Advisory DB's own database.

Imports are meant to be scheduled and run frequently so we don't miss out on any
data from our security feeds and the data we have is up to date. The result of
an import is newly saved `FeedEntry` records that represent the latest available
information.

## Auditing

Importing feed entries can be expensive because of the number of potential
database writes, but we should avoid bulk inserts or updates at the database
level. We manage feed entry persistence using Active Record and `FeedEntry`
instances to make full use of our validations and PaperTrail auditing.

PaperTrail tracks every change to every feed entry so we can revisit how any
given feed entry has arrived in its current state.

## Writing a New Importer

Whenever a new security feed source is identified, a new importer must be
written. For example, to consume security data from [Rubysec](https://rubysec.com),
a new importer will be written to create feed entries with a `source` attribute
of `rubysec`. Here's how:

1. Append `rubysec` to `SOURCES` in `lib/advisory_db/config/sources.rb`:
   ```ruby
   module Sources < ApplicationRecord
     SOURCES = %i[
       nvd
       rubysec
     ].freeze
   end
   ```
2. Define the `RubysecImporter` class in `app/importers/rubysec_importer.rb`:
   ```ruby
   class RubysecImporter < ApplicationImporter
     def each
       # TODO
     end
   end
   ```
3. Test your importer! Use `test/importers/nvd_importer_test.rb` as a guide.

### The Importer API

Your new importer must define an `each` instance method. This method must
iterate over all entries found in the security feed and yield a hash of
`FeedEntry` attributes for each one. This hash must have values set for the
following keys:

- `:source` - This should be the same value for every hash of feed entry
  attributes yielded by this importer. For example: `"nvd"` or `"rubysec"`
- `:identifier` - The identifier uniquely identifies the feed entry and is used
  to de-duplicate on subsequent imports so we update existing feed entry records
  rather than always creating new records. For example: `"nvd/CVE-2014-0130"` or
  `"rubysec/CVE-2014-0130"`
- `:cve_id` - The CVE ID referenced by the feed entry. For some security feeds
  that don't always reference a CVE ID, this value may be `nil`.
- `:raw_payload` - In order to make reevaluation of feed data easier as we
  improve our ingestion process, the raw payload is a snapshot hash of _all_ of
  that feed entry's available data, not just what we know is important to our
  ingestion process today.
- `:advisory_payload` - In contrast to the raw payload, the advisory payload is
  a very specific subset of information that at the time of import, we take into
  account for creating a new advisory. Today, an advisory payload hash has these
  optional values:
  - `:summary` - The summary is a short, plain text description of the security
    issue and must be 255 characters or shorter.
  - `:description` - The description is a more in-depth explanation of the
    security issue, including information such as how the issue can be
    exploited, remediation steps, etc.
  - `:severity` - The severity is one of four values: `"low"`, `"moderate"`,
    `"high"`, or `"critical"`. Currently, this value is set at the advisory
    level. In the future, this will be determined at the vulnerability level
    and the advisory's severity will be calculated as the maximum of its
    vulnerabilities' severities.
  - `:references` - This is an array of URLs that provide additional information
    on the security issue being described by the feed entry.
  - `:withdrawn` - This is a boolean value describing whether the security issue
    described by this feed entry is still applicable.
  - `:vulnerabilities` - This is a hash of integer index to a hash containing the keys
    {:ecosystem, :package_name, :vulnerable_version_range, :first_patched_version}

Your importer may also define an `initialize` instance method to add finer
grained control over the import operation when run manually, but all arguments
to the `initialize` method must be optional. Advisory DB will instantiate your
importer with no arguments during its scheduled imports.  Please ensure that all
string values are UTF-8 encoded.

The `ApplicationImporter` includes the `Enumerable` module, so your importer's
definition of `#each` allows Advisory DB to import batches of feed entries at
a time for performance. Whenever possible, design your importer to download,
parse, and yield feed entry attributes to the `#each` method as a stream rather
than downloading the entire feed and parsing its entire contents into memory.
This helps to keep Advisory DB's scheduled imports lean and mean, without
hogging resources.

### Other potential changes

If adding a new source, [the hydro schema will need to be updated](https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/advisory_db/v0/entities/advisory.proto#L43). The proto changes then need to be pulled into github/advisory-db using the [generation script](https://github.com/github/hydro-schemas#Code-generation).
If the new source is ecosystem-specific, it should also be added into [ecosystems for `FeedEntry`](https://github.com/github/advisory-db/blob/main/app/models/feed_entry.rb#L11).

There will also be some UI changes. In order to display the source info on advisories, we need to add a label for the new source [here](https://github.com/github/advisory-db/blob/main/app/components/advisory_reviews.rb#L5)

If curators are able to trigger specific individual imports, a new chatop should be added in [`app/controllers/chatops_controller.rb](https://github.com/github/advisory-db/blob/main/app/controllers/chatops_controller.rb)

The [rake task documentation](https://github.com/github/advisory-db/blob/main/lib/tasks/advisory_db.rake#L30) may need to be updated to include the additional importer.


