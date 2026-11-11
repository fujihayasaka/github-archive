## Glossary

- See also [git-systems/glossary](https://github.com/github/git-systems/blob/main/GLOSSARY.md) for a git-systems-wide glossary.

| Term | Definition |
| --- | --- |
| [`Spokes Access API`](https://github.com/github/spokes-proto) | An RPC service that provides access to Git repository data to other applications at GitHub. Spokes Access API is defined by the Protocol Buffer definitions, along with helpers for supported languages, in github/spokes-proto. The entrypoint to the API is using Twirp via Spokesd, which routes requests to the relevant GitRPCd backend. The GitRPCd backend serves the incoming request and assembles the response. |
| [`Spokesd`](https://github.com/github/spokesd) | Spokesd is the service that internal services use to interact with our users’ Git repositories. It manages replication and high availability internally so that clients no longer have to worry about details of the distributed system or talking directly to Git fileservers.|
| [`GitRPC`](https://github.com/github/github/tree/master/vendor/gitrpc)| A legacy RPC library that provides access to Git repository data to the monolith. GitRPC is implemented in the vendor/gitrpc directory of github/github. It uses a custom protocol based on BERTRPC. Its server (ernicorn) runs on the fileservers. It relies on routing information from Spokesd. |
| [`GitRPCd `](https://github.com/github/gitrpcd)| Spokesd interacts with fileservers via GitRPCd. GitRPCd is a service that runs on each github-dfs fileserver. It implements single-fileserver operations. The goal is eventually GitRPCd will be the single point of access to a fileserver. |
| [`Spokes`](https://github.blog/2016-09-07-building-resilience-in-spokes/) |  Spokes is the replication system for the file servers where we store over 38 million Git repositories and over 36 million gists.It keeps at least three copies of every repository and every gist so that we can provide durable, highly available access to content even when servers and networks fail. Spokes uses a combination of Git and rsync to replicate, repair, and rebalance repositories. |

## Current State

There are several ways for internal teams to access Git repository data today.
GitRPC is the most common. However, it suffers from a number of operability and security problems. For example, GitRPC does not encrypt its requests. It also couples implementation details of the Git Systems file server fleet to callsites all over the product. GitRPC uses a bespoke protocol and assumes deep knowledge of how Spokes works, which makes it very difficult to use from services outside of the monolith. This has led to designs where repository data is queried via the monolith, which puts more load on the monolith and injects it as a dependency.

Apps may also clone repositories. This works well, as it's a core feature of the site. However, it requires authentication and is not well-suited to applications that need only a small amount of the data from a repository.

Spokes Access API is the replacement for GitRPC.

## Future State

In the future, Spokes Access API will fully replace GitRPC. It is operable, secure, and well-factored for GitHub's foreseeable future needs. Spokes Access API is a more modern approach to Git data access. It includes end-to-end encryption of requests, authentication of clients, a well-defined interface via Twirp and Protocol Buffers, the ability to do more parallelism on the fileservers, and a consistent architecture across dotcom/GHES/Proxima. 

Spokes Access API will be the most common way for internal teams to access Git repository data. 

Spokes Access API has the following benefits over GitRPC:

- Requests will consist of well-defined messages.
- Requests will be encrypted.
- Requests will be authenticated.
- The backend will be smaller and support more parallelism.
- The monolith will no longer need direct network access to github-dfs nodes (for Git RPCs).
- The monolith will know less about repository replication.

Apps will still also be able to clone repositories. Ideally, teams will only clone customers' repositories when they need to operate on the whole thing. Actions is a prime example of this.

## How Will We Get to the Future State?

For new uses of Git data, we are funneling teams through the Spokes Access API.  As we continue to onboard new partners, we should continue to build out Spokes Access API.

GitRPC calls will be updated to make equivalent Spokes Access API calls. We're planning to build Spokes Access API endpoints as we go. At the end of this effort, we can reduce our number of deployed services (read: attack and maintenance surface) by sunsetting Ernicorn processes on the fileservers.




