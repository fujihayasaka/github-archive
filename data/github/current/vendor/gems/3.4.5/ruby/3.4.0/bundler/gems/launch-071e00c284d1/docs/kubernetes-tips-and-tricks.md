# Kuberentes Tips and Tricks

This page is a collection of a few ways you may need to interact with our Kubernetes clusters as an engineer working on Launch. If you know something helpful, feel free to update this page!

## Looking at pod logs on failed deployments

Sometimes config changes will result in `CrashLoopBackoffs`. These can be annoying because you'll need to look at the pod logs to know what went wrong. Here's how you do that:

1. Connect to a prod shell
2. Now run some commands. Note, you'll get prompts for passwords on some of these:
```bash
# We need very secret secrets to do these next steps
. vault-login

# We need to say what cluster to point kubectl at, you can figure this out based on the Heaven/Moda output
gh-kubeconfig $YOUR_CLUSTER_NAME

# For lab
kubectl get pods -n launch-lab # may not be needed, since you may already have the Pod name from Heaven.

# For production
kubectl get pods -n launch-production # may not be needed, since you may already have the Pod name from Heaven.

# Then get your logs!
kubectl logs -n launch-lab $YOUR_POD_NAME
```

## How to manually trigger the healing job

It's possible to trigger this job at will, for example, if you are deploying a change to the `job-cli` code and don't want to wait for the next scheduled job.

1. Connect to a prod shell
2. Run some commands:

```bash
# We need very secret secrets to do these next steps
. vault-login

# The healing job only runs in one cluster
gh-kubeconfig general-2-ac4-iad

# Now create your Job from the CronJob
kubectl create job  -n launch-production --from=cronjob/launch-heal-workflows test-heal

# Now go watch it
kubectl get pods -n launch-production -w
```

## I need to manually kill a long-running job

Maybe something has gone wrong with our deployment tooling and you need another way to stop a job besides chatops. Here's how you can connect to a k8s cluster and delete a job. Note, you'll need to do this for each cluster where the job is running. You can visually get this information from our [Moda App's web page](https://moda.githubapp.com/apps/launch), by drilling down into the pertinent environment and seeing how many clusters are configured for each environment.

```bash
. vault-login

# Get this from the web page for the Launch Moda App
gh-kubeconfig  general-1-ash1-iad

# The namespace may be one of: launch-backfills, launch-production, launch-lab
kubectl config set-context --current --namespace=launch-backfills

# See what jobs are running
kubectl get jobs

# Enter the name of the applicable job
kubectl delete jobs launch-transitions

# This command will watch the jobs resource as the request to delete is fulfilled.
# You know you're done when your job is gone.
kubectl get -w jobs
```