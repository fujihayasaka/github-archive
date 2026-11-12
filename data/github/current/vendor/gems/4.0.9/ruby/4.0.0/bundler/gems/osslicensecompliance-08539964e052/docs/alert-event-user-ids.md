# Alert Event User IDs

This document describes which user ID is recorded on alert events when alerts are closed through remediation.

## Explicit Remediation (Review Approved)

When an alert is explicitly remediated by approving a review request, the following events are created:

| Event | User ID | Description |
|-------|---------|-------------|
| `review_requested` | Requestor | The user who requested the review |
| `review_approved` | Approver | The user who approved the review |
| `licenses_added` / `exception_added` | Approver | The user who made the policy change |
| `closed` | Requestor | The original requestor, not the approver |

The closed event uses the requestor's user ID because they initiated the remediation workflow.

## Side-Effect Closure

When other alerts are closed as a side-effect of a policy change (e.g., adding a license also closes other alerts with that license):

| Event | User ID | Description |
|-------|---------|-------------|
| `licenses_added` / `exception_added` | Editor | The user who edited the policy (required) |
| `closed` | `nil` (bot) | License Compliance Bot |

Side-effect closures can occur from explicit alert remediation or from direct policy edits (e.g., adding a license to an org/enterprise policy via `AddLicensesToEnterprisePolicy`/`AddLicensesToOrganizationPolicy`). The `user_id` is required in these requests so the policy event always has the editor's ID. The closed event uses `nil` because no user explicitly closed those alerts.

## Summary

| Closure Type | Policy Event User | Closed Event User |
|--------------|-------------------|-------------------|
| Explicit (review approved) | Approver | Requestor |
| Side-effect | Editor | `nil` (bot) |
