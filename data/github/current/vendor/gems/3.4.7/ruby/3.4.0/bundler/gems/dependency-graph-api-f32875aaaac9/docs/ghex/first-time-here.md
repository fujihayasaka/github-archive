# Your first time here?

Here's a checklist you can walk through that will help you become more familiar with GitHub's enterprise offerings and how to do dg-api development and customer support on them!

(Videos are optional, but hey, they might help!)

I highly suggest walking through both GHES and GHAE steps, but of course feel free to skip one if you're pinched for time. Since GHES is the more mature enterprise product, I would also suggest starting with GHES documentation first.

### General knowledge

- [ ] Get on a primer on the different Enterprise flavors and how dg-api works with each of them in our [overview doc](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/overview.md).

### Bootstrapping Development

- [ ] Get time intensive GHAE access prep done following [these instructions](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/ghae-kube-dev-instructions.md#prerequisites).
- [ ] Try to bootstrap a GHES bp-dev environment. Docs [here](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/bp-dev.md#bp-dev-supply-chain-bootstrap-sequence), and video tutorial [here](https://github.rewatch.com/video/mdnkcaj34msofu7g-dependency-graph-ghes-development-bootstrapping). Additional resources include: [single tenant ghes-infra doc](https://github.com/github/ghes-infrastructure/blob/main/docs/getting-started/using-single-tenant-ghe-developer-instances.md) and  [admin-experience's bp-dev playbook](https://github.com/github/admin-experience/blob/main/docs/playbooks/bp-dev-bootstrap.md).
- [ ] Try to bootstrap a GHAE ghae-kube environment. Docs [here](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/ghae-kube-dev-instructions.md#ghae-kube-codespaces-bootstrap-recommended), and video tutorial [here](https://github.rewatch.com/video/o8qx3sm8j8jpwjoc-dependency-graph-ghae-development-bootstrapping).

### Testing and Support

- [ ] Check out our [playbook](../playbooks/ghex.md) for some helpful tips and tricks
- [ ] Review [documentation](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/dependency_graph_in_ghes.md#testing-new-changes-in-ghes) for testing dg-api changes in GHES
- [ ] Review [documentation](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/ghae-kube-dev-instructions.md#developing-services-for-ghae-kube) for testing dg-api changes in GHAE
- [ ] Check out this [video walk-through](https://github.rewatch.com/video/qgxyax0xrjt44fno-dependency-graph-ghex-testing) of testing dg-api and dotcom changes in GHES and GHAE
