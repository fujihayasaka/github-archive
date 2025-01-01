# 7. Science experiments

Date: 2020-09-29

## Status

Accepted

## Context

Authentication is an inherantly high-risk project. Failures can cause the entire GitHub platform to become unavailable.
Even worse, functional bugs can cause extremely high-risk security incidents.

GitHub has a long-standing pattern of [science experiments](https://thehub.github.com/engineering/development-and-ops/dotcom/scientist/#how-to-science) to help mitigate this risk.

## Decision

We will make ample usage of "science experiments" to battle-test authnd before putting it in control of authentication decisions.

We will use libraries such as [scientist](https://github.com/github/scientist) (on Ruby) and [go-scientist](https://github.com/github/go-scientist) (on Go) when
converting other services to use authnd.

## Consequences

Science experiments allow us to migrate the Monolith (and other services) to use authnd while mitigating the security and reliability risks inherent to new
authentication systems. However, they usually do not protect us completely. In Ruby, the `scientist` library runs the old and new code paths in sequence
(due to challenges with multi-threading in Ruby). As a result, new code paths could still cause higher latency, even when behind the protection of a "science experiment"

Science experiments also incur additional engineering costs since we have to build logic to correctly compare the old and new results and monitor the experiment.
