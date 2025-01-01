# Production issues with Dependency Insights
Customers who have Enterprise Cloud and Dependency Graph enabled, can access [Dependency Insights](https://docs.github.com/en/enterprise-cloud@latest/organizations/collaborating-with-groups-in-organizations/viewing-insights-for-your-organization#viewing-organization-dependency-insights). Here's [what the page looks like for Github](https://github.com/orgs/github/insights/dependencies).

## Table of Contents
- [Known Customer Issues](#known-customer-issues)
    - [Dependencies Count Mismatch](#dependencies-count-mismatch)


## Known Customer Issues
### Dependencies Count Mismatch
#### How to tell if it's happening:
- A typical Zendesk ticket for this will mention a mismatch in dependencies counts - rather lengthy and mentioning other issues yet here's [an example](https://github.zendesk.com/agent/tickets/1838517).

#### Potential cause
This may happen because a given organization has too many repositories and our query times out.

#### What to do
Rebuild insights by doing the following:
- Once you have the name of the organization, you'll need its `org_id`. You can find it by going into [stafftools](https://admin.github.com/stafftools), searching by the name in the "Search users, organizations, enterprises, teams, repositories, gists, and applications" section. Once you find the account, click on it. On the "Site Admin" page, click on "Overview". The first row under "Organizational information" is ID or `org_id` for our purposes.
- Go into #dg-ops and run `.dg insights rebuild <org_id>` using the `org_id` you got from the step above. Example: `.dg insights rebuild 90800530`.
- Follow up with a support engineer if the counts match.
