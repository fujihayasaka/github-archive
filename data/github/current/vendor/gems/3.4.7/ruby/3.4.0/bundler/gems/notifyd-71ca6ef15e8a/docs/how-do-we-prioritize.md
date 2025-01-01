# How prioritization works in Notification team

Notification team has many activities to handle: 
- Support Newsies: incidents, repair items, bugs, external pull requests, external feature requests, security or compliance issues, company level initiatives.
- Implement a new Notification Platform: development of customer requested features, migration from old to new system, incidents, repair items, bugs, external pull requests, external feature requests, security or compliance issues, company level initiatives.
- Excellence work: improvements in resilience and performance of new and old systems.
- Retrospective items: process changes, documenting,  etc

So, how does the team choose what to work on?

## General guidance:

 **Priority 1**: Newsies support. It means we handle incoming incidents with priority and mitigate customer impact as soon as possible. Keep in mind that Newsies currently has it's [quality of service level](https://thehub.github.com/engineering/products-and-services/internal/service-catalog/service-ownership/#durable-owners-are-explicit-with-the-effort-they-expend-on-the-system) set to "maintenance" . 

This QOS is defined as:

> the application is no longer growing in terms of product functionality. The majority of engineering investment is spent responding to requests (questions, adding capacity, accommodating large-scale production changes, etc.) and keeping their service free of any security concerns.
Incoming PRs are in general welcome(reviewed and merged) if the team considers change simple, straight forward and minimum risk. Otherwise the first responder has the right to say No to the change.
 
 **Priority 2**: Epics committed for the cycle. It can be customer requests for NotifyD(example LLVM Label Subscription), product requests (example is New Subscription UI) or foundamental/DevX work team considers important.
 
 **Priority 3**: NotifyD GA-Readiness. All fundamental work we are planning for NotifyD. Newsies improvement is out of scope as it is with minimized maintenance. Keep in mind, if fundamental work is big enough to become a committed epic, it changes priority from 3 to 2. 
 
 **Priority 4**: New Subscription UI (migration strategy). This is work related to [Migration strategy](https://docs.google.com/document/d/1b1kqDuI6hn0GwsSefNzjZfimRfDjXaNu-Nl14bt0rGo/edit#) in combination with the new Subscription UI. Priority can be changed(4->2) in case epic is committed for the cycle.


The sprint includes all work items that are planned for next two weeks. Ideally the sprint is immutable, meaning no changes. But we know this is not possible because of first responder duty which is hard to predict. So, when we plan a sprint we leave space for one person to be fully committed to first responder duty and do not rely on them present in the sprint backlog. First responder work is tracked on the Sprint dashboard. No work is done outside the sprint [dashboard](https://github.com/orgs/github/projects/3011/views/37?filterQuery=). If there is a necessity to add an issue to the current sprint, the originator speaks on Daily to the team and we all agree or not to add an item to the current sprint. 

Learning from the team experience:
- Do not mix in the one sprint finalizing of the current epic and shaping new epic
- Epic shipping date should match the end of a sprint
- Do not combine DRI and FR duty. Speak up when you DRI+FR and suggest how the team can help you. 

A sprint includes **30%** of excellence work/tech improvement/fundamental work and **70%** of commit to the cycle epic work. This split excluded first responder work from calculation. In case a team considers investing more time into fundamental work, communication to product has to be done. 
