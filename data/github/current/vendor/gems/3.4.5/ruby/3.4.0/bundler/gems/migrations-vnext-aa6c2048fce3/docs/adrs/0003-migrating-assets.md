# 3. Migrating Assets

Date: 2025-01-21

[Google Doc](https://docs.google.com/document/d/1vitB2Zk-vW3I1s7kYFJUvKoBebr18H4EtEhJTN_NTEk/edit?tab=t.0#heading=h.9gmxcxbdp0f)

## Status

Proposed

## Context

There are many migratable resource types that contain, attach, or otherwise depend on potentially large binary or multimedia files. Resources like Issues can have bodies with embedded mp4 video files which must be migrated separately and would be treated as a separate resource that the Issue depends on. The main Assets of concern are UserAssets (inline issue attachments), RepositoryFiles, and ReleaseAssets. These assets vary in size but could range from a few KB images, 4MB (a short screencast embedded in an issue) and can get as large as 2GB (Releases).

Attempting to send data this large from the Crawler through the Monolith Twirp API we plan to expose for ELM is going to immediately run into load and size limit issues.

## Decision

Expose an API that will allow the Crawler access to upload these larger files to an intermediate store. The Crawler will be responsible for associating a reference to the stored data before calling into ELM to create a resource that will be dependent on the data, such as a ReleaseAsset Resource.

Later in the pipeline, the worker processing the DAG will need to handle the data in the intermediate blob store to flow through the existing CreateAsset pipeline in the monolith to ensure both that the data is in its final location and that any metadata about the upload itself is in place in the monolith's databases. The final location of the data must be known to resolve an Attachment resource in the DAG, allowing dependants like Issues to update their content to reflect the new post-migration URLs of their attachments.

Once the Asset content has been handled and resolved successfully in the DAG then the intermediate storage could be cleaned up, preventing the intermediate store from unbounded growth.

## Consequences

- Intermediate storage will be a concern, as the GHES Crawler must directly upload to it from customer infrastructure.
- Asset data is stored in an intermediate store and not the final destination, increasing the storage and bandwidth cost of migrating every asset.

## Alternatives Considered

A naive approach of passing asset data through the ELM API was considered but did not seem viable for real-life use-cases due to load and data limit concerns.

An approach attempting to upload from the Crawler to the final destination storage location of each asset was considered but creates significant complexity either in:
- the handling of the DAG: where there is a chicken and egg problem for a resource like ReleaseAssets
- needing to backdoor the dependency: creating the concept of a "mannequin Release" for example.

In general this approach would require the Crawler to know more about the state of the migration, such as if the user dependency of an attachment has been created or not. However, implementing this approach successfully would remove duplicated bandwidth costs of intermediate storage at the cost of complexity in the Crawler.
