# Resetting Hydro Offsets

Occasionally, we may need to adjust the offset of a Hydro processor. This can be done to skip over an unprocessable message or when we decide that we want to run a processor from the beginning of the topic, or have the processor jump to the end of the topic.

To reset the offset of a Hydro processor, first you'll need to scale down the deployment associated with the processor that is reading from the topic. Follow the instructions in the [Manually Scaling Deployments](manually-scaling-deployments.md) runbook to scale down the deployment.

Next visit the Consumer Group page in the GitHub hydro website

https://hydro.githubapp.com/kafka/clusters/potomac/consumer_group?group_id=licensify

By clicking on the `Members` tab you can confirm if all of the deployments have been scaled down. If there are still deployments running, you will need to scale them down before proceeding.

Next, head to the Reset Offsets tab, make sure you type in a topic into the topic field, otherwise you will reset the offsets for all topics in the consumer group, and this is rarely what you want. You have the option of specifying a partition number in the case of a specific message that needs to be skipped, but if you're trying to reset the offset for the entire topic, you can leave this field blank.

Finally choose the offset you want to reset to, like Newest, Oldest, timestamp or offset number and hit the Submit button.


![Screenshot of resetting offsets](https://github.com/user-attachments/assets/16a5d281-acbd-439b-9894-9d5d85491862)
