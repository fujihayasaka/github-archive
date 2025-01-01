# 40. Use notification worker to process Notifyd dotcom background jobs

Date: 2023-03-31

## Status

Accepted

## Context

Historically notifications background jobs used `lowworker` instances to trigger jobs on Notifyd. See high level overview of the architecture of our notifications pipeline for Notifyd:
 
![image](https://user-images.githubusercontent.com/5173831/229092398-eed2c179-5043-4942-bc66-a9eca3892bad.png)

`Lowworker` workers are a shared resource used by many background jobs across GitHub, and it works well when there are enough resources to run background jobs. However, in some cases, background jobs may take longer to run or trigger a lot of retries, which has caused resource starvation, pushing `Lowworker` utilisation close to 100%.

![image](https://user-images.githubusercontent.com/5173831/229093134-9364a732-392a-4400-b018-b56b8954454c.png)

It has caused notifications related jobs to be processed slower and break our delivery SLOs.

## Decision

We decided to move notifications background jobs for Notifyd pipeline to use `notificationworker` deployment instead of `lowworker`.
Also we have decided not to move Newsies background jobs to `notificationworker` yet, because Newsies delivery jobs still are involved in sending emails while Notifyd jobs not.

## Consequences

- Notifyd background jobs on dotcom are indepent from `lowworker` utilisation now
- Notification team should keep an eye on `notificationworker` utilisation and scale the worker accordingly.
