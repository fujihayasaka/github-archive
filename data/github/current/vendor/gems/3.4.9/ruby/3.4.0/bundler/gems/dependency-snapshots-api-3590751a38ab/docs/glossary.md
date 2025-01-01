# Snapshots Glossary

This document contains official definitions of the various terms used both in
code and in documentation for dependency-snapshots-api. Definitions are given in
a narrative order, with the most important terms at the top and related definitions
appearing close together.

* **snapshot**: Primarily a submission and storage format for dependency data. These are JSON documents with roughly the following levels:
    - A top level with metadata about the snapshot itself, including the detector that created it and the job that it's associated with.
    - A set of logical manifests, each of which is composed of a graph of dependencies and some metadata about the manifest.
    - A graph of dependencies, each of which is composed of a [purl] and some metadata about the dependency.
* **manifest**: a manifest is a named set of dependencies with some metadata. A manifest may or may not correspond to a file on disk. A manifest is not necessarily associated with a single ecosystem, and it may or may not contain any dependencies. Manifest names are arbitrary strings, and manifests that correspond to files will have the file location included separately.
* **dependency**: for the purposes of this service, a dependency is closely identified with a [purl]. They also support additional metadata in the context of a snapshot.
* **canonical snapshot**: A snapshot whose dependencies are assumed to be in current use as of the tip of the default branch of the repository.
    Importantly, the "repository's dependencies" (as we display them in the
    Insights > Dependency graph page) come from the union of all the canonical snapshots for that repository.
    A snapshot is considered canonical for a given repository iff all of the following are true:
    - It relates to the default branch of the repository
    - There are no snapshots with the same job+detector for a more recent commit
    - There are no snapshots with the same job+detector+commit with a more recent scanned time
* **dependency locator**: A dependency locator is used in a subset of APIs when we're looking for a specific dependency. 
    - A dependency locator is a valid PURL, but generally has fewer fields populated than the full PURL for a package. 
    - You can think of dependency locator as a "partial matching" PURL, but we don't do things like wildcards. It's also comparable to a hash in that it is a grouping key for many PURLs which are likely hits for a given search.
    - In general, any API that accepts a dependency locator expects a specific set of PURL properties to be present.
    - Today, we only have dependency locators that are `<package_type>, <package_namespace>, <package_name>` tuples. 
* **canonical commit**: Deprecated: only _snapshots_ should be considered canonical.
* **noteworthy commit**: Deprecated: only _snapshots_ should be considered canonical.

[purl]: https://github.com/package-url/purl-spec
