# 15. Gitauth Impact

Date: 2020-08-25

*NOTE: This was a non-ADR design doc from the Wall-E experiment that has been absorbed in as an ADR. It's number does not represent the actual order in which it was created, and it's format differs from the others.*

## Status

Accepted

## Context

If we're introducing an experiment in to GitAuth, we need to establish appropriate protections to ensure we don't impact user scenarios.

## Protections

We have a few "protections" in place to ensure the impact of failures in authnd on gitauth remain mininal.

### Science

We put authnd codepaths as `try` blocks in [Science Experiments](https://github.com/github/scientist).
This means that authnd responses will not be used in actual decision-making.
Instead, both the existing and the new authnd-enabled codepath will be run in a random order (to reduce risk of order-dependency) and the results compared and logged.

All authnd experiments should be given a name that starts `authnd.` so that they can appear on the [authnd dashboard](https://app.datadoghq.com/dashboard/nu7-a4k-jza/authnd?from_ts=1598291919800&live=true&to_ts=1598295519800) (in the "Experiments" group).
Individual experiment stats can be viewed on the [science.experiments dashboard](https://app.datadoghq.com/dashboard/9w5-jyh-t4n/scienceexperiments?from_ts=1598292287958&live=true&to_ts=1598295887958).

Experiment results can be viewed in the [Devtools Code Experiments](https://devtools.githubapp.com/experiments) view (entitlements required).
We can also adjust the percentage of requests that are allowed to run the experiment there.

NOTE: In a local dotcom instance, experiments are stored in the `github_development.experiments` table and *mismatches* are stored in `github_development_collab.science_events`.
Matches are **not** recorded.

### Timeouts

The gitauth code has the following timeouts on requests to authnd:

* Connection timeout of `0.02s` (`20ms`) - If a TCP connection cannot be established in this time, the experiment is abandoned.
* Request timeout of `0.05s` (`50ms`) - If the request doesn't get a response in this time, the experiment is abandoned.
* Experiment timeout of `0.1s` (`100ms`) - If the entire experimental code path doesn't complete in this time, the experiment is abandoned.

### Circuit Breaker

We configure a circuit breaker based on Resilient to ensure that repeated failures in authnd cause a client-side failure to be generated.
Note: Authentication failures **do not** cause an exception, so are not considered "failures" in this case.
Only networking, client logic, or unexpected server errors cause the breaker to trip.

The configuration for the breaker can be found in `config/initializers/authnd.rb` in github/github.
As of writing, the config is the following:

```ruby
conn.use Faraday::Resilient, name: SERVICE_NAME, options: {
  instrumenter: GitHub,
  sleep_window_seconds: 10,
  error_threshold_percentage: 5,
  window_size_in_seconds: 30,
  bucket_size_in_seconds: 5,
}
```

Consider also the [default configuration for `resilient`](https://github.com/jnunemaker/resilient#default-properties).

The circuit breaker will break results into `30` second windows (`window_size_in_seconds`), made up of `5` second buckets (`bucket_size_in_seconds`).
This means the window "rolls" forward `5` seconds at a time.
For each window, a minimum of `20` requests must be received or the circuit health is not evaluated in that window (`request_volume_threshold`).
In each window that meets the threshold, if `5%` of requests in that window fail, the breaker is tripped and all requests will return a client-generated HTTP `502` error.
After `10` seconds (`sleep_window_seconds`) elapse from the breaker tripping, the breaker will allow requests through to retry and restore the breaker state if fewer than `5%` of requests fail.

## Benchmarking

### Methodology

We run a 100 request benchmark using `ab` against gitauth and collect latency metrics.
We run the benchmark 5 times and take the final results.

```shell
$ ab -T "application/x-www-form-urlencoded" -p ~/tmp/gitauth-verify-key-post -m POST -n 100 http://127.0.0.1:4327/_gitauth
```

Where `~/tmp/gitauth-verify-key-post` contains:

```
action=verify-key&proto=ssh&fingerprint=0d:15:55:ad:98:65:5c:8d:c5:35:dc:5a:8b:7f:25:05&key=ssh-rsa%20AAAAB3NzaC1yc2EAAAADAQABAAACAQCwVVermLef7H0u%2Fv3yn4KOsiOqKJKrjIk47Jjg0pYrqHBHwqS%2FVkzbcVL7sPkXbJi3VsPMjSaR526XBgqdZe0ntBXCB3Ch9xrQWcsZLjDELXpAkJ0b0FDYpL78oPnW8mF62%2FBh%2FWoclwxWj6Fg5CnmlAz1LUGXcP7rXdZIdccZZ1FCSooVupscIyAwJHZwC3MYh5TspSZ2WuhbyxKdUeO2gjpx7PAcUL2iNnOBX2H88PFYggrO4jqytZoorTOVI2bcK2y0AcD0m6U%2FOm3Br6Hpwktq4SJzKi%2B%2FP%2BJZO1V9H1%2Bi1WaSYfG%2BGxLcfuMaj%2FqunE%2FcfX1xouKhKFkvsFIst9yzzkTi5ru2y5ymuBdTBmrZHiyQ1ItAK8xNM0471%2F4ThXsd3bAa3MUo2RTwh4DE5AQ1qa%2FN1M4iwSIhFvcLN2TGywFmJI3T9UaNuzoVcfyvGGWmN44K%2BgyBRwtRp4ZuEuRiac6XfFwt8kdyFKLm%2Bumk%2F3smJ6A6RspvOsSBMn7Sa9ifnM%2BBsfsUAzqzXIasbwmaVw4K9aE3Q8lx2aOly54YVjeuC9F7MLOurVdS%2BVpSE8r%2FFHa8KawvU9RF92ODBeZq699Ty90eTA64XJQyHKxBGPKSEmRCf%2FU%2BCfoP8M3aJveOWQss6Dlw7wFGz9VvqEEZgKLUDR2qq942KBp0UQ%3D%3D&ssh_login=git
```

### Results

The following tables contains latency results from the perf test in milliseconds `ms`. The "scenarios" tested are:

* `master` - Running gh/gh master, commit `96492e0b9cd9a50b1fcf29dc3aa5a11092286fce` (before any gitauth is added)
* `science off` - Running our experiment but with the experiment at 0% enabled (so just testing science overhead, not our experiment)
* `science on + authnd on` - Running our experiment at 100% enabled with authnd present and responding promptly.
* `science on + authnd timeout + no breaker` - Running our experiment at 100% enabled but with authnd blocking responses for 5 seconds (emulating a worst-case networking issue). The circuit breaker is **disabled** but timeouts are enabled (see "Protections").
* `science on + authnd timeout + breaker` - Running our experiment at 100% enabled but with authnd blocking responses for 5 seconds (emulating a worst-case networking issue). The circuit breaker and timeouts are **enabled** (see "Protections").

#### On Localhost

This is a rough testing scenario on anurse's personal Macbook.
I didn't do anything to keep the load on the machine consistent, it's designed to serve as a rough guide for further investigation.

| Scenario | Min | Mean | StdDev | Median | Max | 90th | 95th | 99th |
| -------- | --- | ---- | ------ | ------ | --- | ---- | ---- | ---- |
| `master` | 4 | 7 | 5.5 | 5 | 22 | 20 | 21 | 22 |
| `science off` | 4 | 7 | 5.5 | 5 | 23 | 20 | 21 | 23 | 
| `science on + authnd on` | 6 | 10 | 6.5 | 7 | 24 | 23 | 23 | 24 |
| `science on + authnd timeout + no breaker` | 69 | 82 | 21.0 | 81 | 275 | 90 | 91 | 275 |
| `science on + authnd timeout + breaker` See 1 | 14 | 24 | 22.1 | 16 | 229 | 32 | 33 | 229 |

Chart:

![Chart of the above table results](https://user-images.githubusercontent.com/7574/91088135-5c3e4b00-e606-11ea-9304-c5c3d8f81dae.png)


Notes:

1. Because we run 5 tests in sequence, by the time the final test runs, the breaker has been tripped. We are seeing only the impact of the breaker's 502. 

### Outcome

From the rough testing on localhost, we see that if the experiment is set to `0%` we generally have no impact on gitauth performance. This indicates we'll be in a good position to deploy code and slowly roll out the experiment. It also means that if an issue arises, resetting the experiment to `0%` should allow us to get out of the code path quickly.
