# Transitions

Transitions are required to modify the database. Running transitions in billing platform is still in an experimental phase. Our approach is based on the [transitions best practices document](https://thehub.github.com/epd/engineering/products-and-services/internal/transitions/).

Transitions require a PR with the transition logic that is approved by the team.

*For long running transitions, consider adding resource limits to the Kube job.*

## Table of Contents

- [Terminology](#terminology)
- [Details](#details)
  - [Running a transition](#running-a-transition)
  - [Testing transitions](#testing-transitions)
  - [Debugging transitions](#debugging-transitions)
- [References](#references)

## Terminology

- **Common term**: definition

## Details

### Running a transition

In [#billing-platform-ops](https://github.slack.com/archives/C045DAX94JG) channel, run the following command:

```
.transitions run [pull_request] [environment] [arguments]
```

*Note that if you want to run the transition in all environments, you can use `*` as the environment.*

When a successful transition is run, Hubot will reply to your message with status updates of the transition and a link to Splunk logs when it is complete.

These messages will also show in the PR that transition is run in.

#### Example

```
.transitions run https://github.com/github/billing-platform/pull/798 production --type="line_items"
```

![Example transition job](/docs/images/example_transition_run.png)

### Testing transitions

To test a transition, run the following command in a [billing-platform codespace](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=535981135&skip_quickstart=true):

```bash
./script/transition --dry_run=true --type=delete_by_org_repo_product_sku --customer_id=1
```

### Debugging transitions

- Transitions output links to splunk logs as comments on the orignial PR.
- Empty log messages *may* be due to misconfiguration of a third party lib (e.g like `stats`). Use a fully configured `statter` or use `NilStatter`.
- Logs can also be inspected directly on the gh-console, but you may have to be quick, since these transitions tend to run quickly and terminate and hence take the pods down with them. see https://github.com/github/moda/blob/main/team-docs/debugging-with-kubectl.md
  - `ssh` into bastion
  - `ssh` into an ops-shell
  - run `. vault-login`
  - run `gh-kubeconfig`
  - To see currently running transition pods (you'll need to get the cluster name from the splunk logs i.e `kube_cluster`):

  ```bash
    $> kubectl get pods --context general-2-ash1-iad -n billing-platform-production | grep transition
  ```

  - To view the logs of the pod :

  ```bash
    $> kubectl logs -f --context general-2-ash1-iad -n billing-platform-production <pod_name_from_splunk>
  ```

## References

- [The Hub: Transitions Best Practices](https://thehub.github.com/epd/engineering/products-and-services/internal/transitions/)
